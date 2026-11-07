import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'checked_ble_receipt_writer.dart';
import 'printer_settings_store.dart';

abstract interface class ReceiptPrinterTransport {
  Future<void> send(ReceiptPrinterSettings settings, List<int> bytes);
}

/// One process-wide queue shared by checkout, copies and test receipts.
/// A failed job never poisons later jobs. No automatic transport retry.
class ReceiptJobQueue {
  Future<void> _tail = Future<void>.value();
  Future<void> run(Future<void> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}

class ClassicPrinterBridge {
  static const channel = MethodChannel('brewverse/receipt_classic');
  Future<List<ReceiptPrinterSettings>> discover() async {
    final rows =
        await channel.invokeListMethod<dynamic>('pairedPrinters') ?? [];
    return rows.map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      return ReceiptPrinterSettings(
          address: map['address'] as String,
          name: map['name'] as String,
          transport: ReceiptTransport.classic);
    }).toList();
  }

  Future<void> send(ReceiptPrinterSettings settings, List<int> bytes) =>
      channel.invokeMethod<void>('send', {
        'address': settings.address,
        'bytes': Uint8List.fromList(bytes),
      });
}

class BluetoothReceiptPrinterTransport implements ReceiptPrinterTransport {
  BluetoothReceiptPrinterTransport({
    Future<void> Function()? stopScan,
    Future<void> Function(ReceiptPrinterSettings, List<int>)? bleSend,
    Future<void> Function(ReceiptPrinterSettings, List<int>)? classicSend,
    ReceiptJobQueue? queue,
  })  : _stopScan = stopScan ?? FlutterThermalPrinter.instance.stopScan,
        _bleSend = bleSend ?? _sendBle,
        _classicSend = classicSend ?? ClassicPrinterBridge().send,
        _queue = queue ?? sharedQueue;
  static final sharedQueue = ReceiptJobQueue();
  final ReceiptJobQueue _queue;
  final Future<void> Function() _stopScan;
  final Future<void> Function(ReceiptPrinterSettings, List<int>) _bleSend;
  final Future<void> Function(ReceiptPrinterSettings, List<int>) _classicSend;

  @override
  Future<void> send(ReceiptPrinterSettings settings, List<int> bytes) =>
      _queue.run(() async {
        if (bytes.isEmpty) throw ArgumentError('Receipt is empty.');
        await _stopScan().timeout(const Duration(seconds: 5));
        switch (settings.transport) {
          case ReceiptTransport.ble:
            await _bleSend(settings, bytes);
          case ReceiptTransport.classic:
            await _classicSend(settings, bytes);
        }
      });

  static Future<void> _sendBle(
      ReceiptPrinterSettings settings, List<int> bytes) async {
    final plugin = FlutterThermalPrinter.instance;
    final printer = Printer(
        address: settings.address,
        name: settings.name,
        connectionType: ConnectionType.BLE);
    await BleReceiptSession(
      connect: () => plugin.connect(printer),
      disconnect: () => plugin.disconnect(printer),
      write: (beforeChunk) => CheckedBleReceiptWriter(beforeChunk: beforeChunk)
          .write(printer, bytes),
    ).send();
  }
}

/// Holds queue ownership through cleanup, including failed connections.
class BleReceiptSession {
  BleReceiptSession(
      {required this.connect,
      required this.disconnect,
      required this.write,
      DateTime Function()? clock,
      this.receiptTimeout = const Duration(seconds: 60)})
      : clock = clock ?? DateTime.now;
  final Future<bool> Function() connect;
  final Future<void> Function() disconnect;
  final Future<void> Function(void Function()) write;
  final DateTime Function() clock;
  final Duration receiptTimeout;
  Future<void> send() async {
    final deadline = clock().add(receiptTimeout);
    try {
      // Underlying Universal BLE operations have native/command deadlines.
      // Do not release the queue around an uncancelled Future.timeout.
      if (!await connect()) {
        throw StateError('BLE connection failed. Check power and permissions.');
      }
      await write(() {
        if (!clock().isBefore(deadline)) {
          throw TimeoutException(
              'BLE receipt deadline exceeded; delivery uncertain.');
        }
      });
    } finally {
      await disconnect();
    }
  }
}
