import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brewverse_cafe_manager/services/printer_settings_store.dart';
import 'package:brewverse_cafe_manager/services/receipt_print_coordinator.dart';
import 'package:brewverse_cafe_manager/services/thermal_printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ble = ReceiptPrinterSettings(address: 'A', name: 'BLE');
  const classic = ReceiptPrinterSettings(
      address: 'B', name: 'Classic', transport: ReceiptTransport.classic);

  test('legacy settings migrate to BLE and ASCII; profiles round trip', () {
    expect(
        ReceiptPrinterSettings.fromJson({
          'address': 'A',
          'name': 'Old',
          'paperWidth': 58,
          'autoPrint': true
        }).transport,
        ReceiptTransport.ble);
    const profile = ReceiptPrinterSettings(
        address: 'B',
        name: 'SPP',
        transport: ReceiptTransport.classic,
        paperWidth: ReceiptPaperWidth.mm80,
        encoding: ReceiptEncoding.cp1252,
        feedLines: 5,
        cut: false);
    final restored = ReceiptPrinterSettings.fromJson(profile.toJson());
    expect(restored.toJson(), profile.toJson());
    expect(
        () => ReceiptPrinterSettings.fromJson(
            {...profile.toJson(), 'transport': 'usb'}),
        throwsFormatException);
    expect(
        () => ReceiptPrinterSettings.fromJson(
            {...profile.toJson(), 'feedLines': -1}),
        throwsFormatException);
  });

  test('routes BLE and Classic independently and stops scan before each',
      () async {
    final events = <String>[];
    final transport = BluetoothReceiptPrinterTransport(
        queue: ReceiptJobQueue(),
        stopScan: () async => events.add('stop'),
        bleSend: (_, bytes) async => events.add('ble'),
        classicSend: (_, bytes) async => events.add('classic'));
    await transport.send(ble, [1]);
    await transport.send(classic, [2]);
    expect(events, ['stop', 'ble', 'stop', 'classic']);
  });

  test('disconnect and timeout failures release queue for explicit reprint',
      () async {
    for (final settings in [ble, classic]) {
      var attempts = 0;
      Future<void> send(ReceiptPrinterSettings _, List<int> bytes) async {
        attempts++;
        if (attempts == 1) throw StateError('disconnected mid-receipt');
        if (attempts == 2) throw TimeoutException('native operation timed out');
      }

      final transport = BluetoothReceiptPrinterTransport(
          queue: ReceiptJobQueue(),
          stopScan: () async {},
          bleSend: send,
          classicSend: send);
      await expectLater(transport.send(settings, [1]), throwsStateError);
      await expectLater(
          transport.send(settings, [1]), throwsA(isA<TimeoutException>()));
      await transport.send(settings, [1]);
      expect(attempts, 3);
    }
  });

  test('automatic and manual jobs share a queue across transport instances',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPrinterSettingsStore();
    await store.save('cafe', classic);
    final gate = Completer<void>();
    final entered = Completer<void>();
    final events = <String>[];
    Future<void> send(ReceiptPrinterSettings s, List<int> bytes) async {
      events.add(s.name);
      if (s.transport == ReceiptTransport.classic) {
        entered.complete();
        await gate.future;
      }
    }

    BluetoothReceiptPrinterTransport transport() =>
        BluetoothReceiptPrinterTransport(
            stopScan: () async {}, bleSend: send, classicSend: send);
    final automatic =
        ReceiptPrintCoordinator(settingsStore: store, transport: transport())
            .autoPrint(
                cafeId: 'cafe',
                billId: 'bill',
                cafeName: 'Cafe',
                loadBill: () async => {
                      'id': 'bill',
                      'cafeId': 'cafe',
                      'orderType': 'dineIn',
                      'total': 1,
                      'items': [
                        {
                          'name': 'Saved',
                          'quantity': 1,
                          'unitPrice': 1,
                          'lineTotal': 1
                        }
                      ],
                    });
    await entered.future;
    final manual = transport().send(ble, [2]);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['Classic']);
    gate.complete();
    expect((await automatic).status, ReceiptPrintStatus.sent);
    await manual;
    expect(events, ['Classic', 'BLE']);
  });

  test('Classic bridge returns paired candidates and forwards exact bytes',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ClassicPrinterBridge.channel, (call) async {
      calls.add(call);
      if (call.method == 'pairedPrinters') {
        return [
          {'name': 'Veer candidate', 'address': 'AB'}
        ];
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ClassicPrinterBridge.channel, null));
    final bridge = ClassicPrinterBridge();
    final candidates = await bridge.discover();
    expect(candidates.single.transport, ReceiptTransport.classic);
    await bridge.send(candidates.single, [27, 64, 10]);
    expect((calls.last.arguments as Map)['bytes'], [27, 64, 10]);
  });

  test(
      'BLE session cleans up false connect, write failure and expired deadline',
      () async {
    for (final mode in ['connect', 'disconnect', 'timeout', 'success']) {
      final events = <String>[];
      var now = DateTime(2026);
      final session = BleReceiptSession(
          clock: () => now,
          connect: () async {
            events.add('connect');
            return mode != 'connect';
          },
          disconnect: () async {
            events.add('cleanup');
          },
          write: (checkDeadline) async {
            events.add('write');
            if (mode == 'disconnect') throw StateError('device disconnected');
            if (mode == 'timeout') now = now.add(const Duration(minutes: 2));
            checkDeadline();
          });
      if (mode == 'success') {
        await session.send();
      } else {
        await expectLater(session.send(),
            throwsA(anyOf(isA<StateError>(), isA<TimeoutException>())));
      }
      expect(events.last, 'cleanup');
      if (mode == 'connect') expect(events, ['connect', 'cleanup']);
    }
  });

  test('wrapping, Latin profile, feed and cut are explicit', () async {
    expect(wrapReceiptText('Extra long cappuccino with oat milk', 16),
        ['Extra long', 'cappuccino with', 'oat milk']);
    expect(wrapReceiptText('A' * 70, 32).map((s) => s.length), [32, 32, 6]);
    Future<List<int>> receipt(ReceiptEncoding encoding, bool cut) =>
        ThermalPrinterService().buildReceiptBytes(
            cafeName: 'Café',
            billNumber: 'copy',
            orderType: 'dineIn',
            items: [
              {'name': 'Crème', 'quantity': 1, 'unitPrice': 1, 'lineTotal': 1}
            ],
            total: 1,
            encoding: encoding,
            cut: cut,
            feedLines: 0,
            isReprint: true);
    final ascii = latin1.decode(await receipt(ReceiptEncoding.ascii, false));
    final western = await receipt(ReceiptEncoding.cp1252, true);
    expect(ascii, contains('Caf?'));
    expect(ascii, contains('RECEIPT COPY'));
    expect(latin1.decode(western), contains('Café'));
    expect(western, contains(233));
    expect(ascii.contains(String.fromCharCodes([29, 86])), false);
    expect(
        latin1.decode(western).contains(String.fromCharCodes([29, 86])), true);
  });
}
