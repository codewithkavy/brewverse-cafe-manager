import 'dart:convert';

import 'package:brewverse_cafe_manager/services/printer_settings_store.dart';
import 'package:brewverse_cafe_manager/services/receipt_print_coordinator.dart';
import 'package:brewverse_cafe_manager/services/thermal_printer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Transport implements ReceiptPrinterTransport {
  int sends = 0;
  bool fail = false;
  List<int>? lastBytes;

  @override
  Future<void> send(ReceiptPrinterSettings settings, List<int> bytes) async {
    sends++;
    lastBytes = bytes;
    if (fail) throw StateError('Bluetooth delivery uncertain');
  }
}

Map<String, dynamic> _bill({String cafeId = 'cafe-a'}) => {
      'id': 'bill-1',
      'cafeId': cafeId,
      'orderType': 'takeaway',
      'items': [
        {
          'name': 'Saved latte',
          'quantity': 2,
          'unitPrice': 100,
          'lineTotal': 200,
        },
      ],
      'discount': 20,
      'total': 180,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesPrinterSettingsStore store;
  late _Transport transport;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = SharedPreferencesPrinterSettingsStore();
    transport = _Transport();
  });

  Future<void> configure({
    String? cafeId = 'cafe-a',
    ReceiptPaperWidth width = ReceiptPaperWidth.mm58,
    bool autoPrint = true,
  }) =>
      store.save(
        cafeId,
        ReceiptPrinterSettings(
          address: 'AA:BB',
          name: 'Counter printer',
          paperWidth: width,
          autoPrint: autoPrint,
        ),
      );

  Future<ReceiptPrintResult> autoPrint({
    String? cafeId = 'cafe-a',
    Map<String, dynamic>? bill,
    ReceiptPrintCoordinator? coordinator,
  }) =>
      (coordinator ??
              ReceiptPrintCoordinator(
                  settingsStore: store, transport: transport))
          .autoPrint(
        cafeId: cafeId,
        billId: 'bill-1',
        cafeName: 'Saved cafe name',
        loadBill: () async => bill ?? _bill(),
      );

  test('configuration is persisted per café and separate from legacy mode',
      () async {
    await configure(width: ReceiptPaperWidth.mm80);
    await configure(cafeId: 'cafe-b', autoPrint: false);
    final freshStore = SharedPreferencesPrinterSettingsStore();
    expect(
        (await freshStore.load('cafe-a'))?.paperWidth, ReceiptPaperWidth.mm80);
    expect((await freshStore.load('cafe-b'))?.autoPrint, isFalse);
    expect(await freshStore.load(null), isNull);
    await freshStore.clear('cafe-a');
    expect(await freshStore.load('cafe-a'), isNull);
    expect(await freshStore.load('cafe-b'), isNotNull);
  });

  test('does not load a bill or print without enabled configuration', () async {
    var loads = 0;
    final coordinator = ReceiptPrintCoordinator(
      settingsStore: store,
      transport: transport,
    );
    Future<ReceiptPrintResult> run() => coordinator.autoPrint(
          cafeId: 'cafe-a',
          billId: 'bill-1',
          cafeName: 'Cafe',
          loadBill: () async {
            loads++;
            return _bill();
          },
        );
    expect((await run()).status, ReceiptPrintStatus.disabled);
    await configure(autoPrint: false);
    expect((await run()).status, ReceiptPrintStatus.disabled);
    expect(loads, 0);
    expect(transport.sends, 0);
  });

  test('auto prints saved receipt once across coordinator instances', () async {
    await configure();
    expect((await autoPrint()).status, ReceiptPrintStatus.sent);
    expect(latin1.decode(transport.lastBytes!), contains('Saved latte'));
    expect(latin1.decode(transport.lastBytes!), contains('TOTAL  Rs 180.00'));
    final nextInstance = ReceiptPrintCoordinator(
      settingsStore: SharedPreferencesPrinterSettingsStore(),
      transport: transport,
    );
    expect((await autoPrint(coordinator: nextInstance)).status,
        ReceiptPrintStatus.alreadyAttempted);
    expect(transport.sends, 1);
  });

  test('failed Bluetooth send cannot cause another automatic send', () async {
    await configure();
    transport.fail = true;
    final result = await autoPrint();
    expect(result.status, ReceiptPrintStatus.failed);
    expect(result.error, isStateError);
    transport.fail = false;
    expect((await autoPrint()).status, ReceiptPrintStatus.alreadyAttempted);
    expect(transport.sends, 1);
    // No checkout API is available to this coordinator: printing cannot rebill.
  });

  test('simultaneous completion callbacks claim only one automatic send',
      () async {
    await configure();
    final results = await Future.wait([autoPrint(), autoPrint(), autoPrint()]);
    expect(results.where((r) => r.status == ReceiptPrintStatus.sent).length, 1);
    expect(transport.sends, 1);
  });

  test('rejects mismatched café, bill, and saved totals before transport',
      () async {
    await configure();
    expect((await autoPrint(bill: _bill(cafeId: 'cafe-b'))).status,
        ReceiptPrintStatus.failed);
    expect((await autoPrint(bill: {..._bill(), 'id': 'another-bill'})).status,
        ReceiptPrintStatus.failed);
    expect((await autoPrint(bill: {..._bill(), 'total': 170})).status,
        ReceiptPrintStatus.failed);
    expect(transport.sends, 0);
    expect((await autoPrint()).status, ReceiptPrintStatus.sent);
  });

  test('does not print while persisted receipt lookup is unavailable',
      () async {
    await configure();
    final coordinator = ReceiptPrintCoordinator(
      settingsStore: store,
      transport: transport,
    );
    expect(
      (await coordinator.autoPrint(
        cafeId: 'cafe-a',
        billId: 'bill-1',
        cafeName: 'Cafe',
        loadBill: () async => null,
      ))
          .status,
      ReceiptPrintStatus.unavailable,
    );
    expect(transport.sends, 0);
    expect((await autoPrint()).status, ReceiptPrintStatus.sent);
  });

  test('80 mm configuration changes the receipt layout', () async {
    await configure(width: ReceiptPaperWidth.mm80);
    expect((await autoPrint()).status, ReceiptPrintStatus.sent);
    expect(latin1.decode(transport.lastBytes!), contains('-' * 48));
  });

  test('attempt scope includes café and Bluetooth device identity', () async {
    await configure();
    await configure(cafeId: 'cafe-b');
    expect((await autoPrint()).status, ReceiptPrintStatus.sent);
    expect(
      (await autoPrint(cafeId: 'cafe-b', bill: _bill(cafeId: 'cafe-b'))).status,
      ReceiptPrintStatus.sent,
    );
    await store.save(
      'cafe-a',
      const ReceiptPrinterSettings(address: 'CC:DD', name: 'Second printer'),
    );
    expect((await autoPrint()).status, ReceiptPrintStatus.sent);
    expect(transport.sends, 3);
  });

  test('invalid stored printer settings do not select a destination', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'brewverse.printer.v1.cafe:cafe-a',
      '{"address":"AA:BB","name":"Printer","paperWidth":42,"autoPrint":true}',
    );
    expect(await store.load('cafe-a'), isNull);
    expect((await autoPrint()).status, ReceiptPrintStatus.disabled);
    expect(transport.sends, 0);
  });
}
