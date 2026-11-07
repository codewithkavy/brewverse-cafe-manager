import 'bluetooth_receipt_transport.dart';
export 'bluetooth_receipt_transport.dart';

import 'printer_settings_store.dart';
import 'thermal_printer_service.dart';

enum ReceiptPrintStatus {
  disabled,
  alreadyAttempted,
  sent,
  failed,
  unavailable
}

class ReceiptPrintResult {
  const ReceiptPrintResult(this.status, {this.error});

  final ReceiptPrintStatus status;
  final Object? error;
}

/// Printing is independent of billing. A saved bill is the only receipt source;
/// never submit another checkout to retry receipt delivery.
class ReceiptPrintCoordinator {
  ReceiptPrintCoordinator({
    PrinterSettingsStore? settingsStore,
    ReceiptPrinterTransport? transport,
    ThermalPrinterService? receiptBuilder,
  })  : _settingsStore =
            settingsStore ?? SharedPreferencesPrinterSettingsStore(),
        _transport = transport ?? BluetoothReceiptPrinterTransport(),
        _receiptBuilder = receiptBuilder ?? ThermalPrinterService();

  final PrinterSettingsStore _settingsStore;
  final ReceiptPrinterTransport _transport;
  final ThermalPrinterService _receiptBuilder;

  Future<ReceiptPrintResult> autoPrint({
    required String? cafeId,
    required String billId,
    required String cafeName,
    required Future<Map<String, dynamic>?> Function() loadBill,
  }) async {
    try {
      final settings = await _settingsStore.load(cafeId);
      if (settings == null || !settings.autoPrint) {
        return const ReceiptPrintResult(ReceiptPrintStatus.disabled);
      }
      final bill = await loadBill();
      if (bill == null) {
        return const ReceiptPrintResult(ReceiptPrintStatus.unavailable);
      }
      if (bill['id'] != billId ||
          (cafeId != null && bill['cafeId'] != cafeId)) {
        throw StateError('Saved bill does not match this café and bill ID.');
      }
      final items = bill['items'];
      final total = bill['total'];
      final discount = bill['discount'] ?? 0;
      final orderType = bill['orderType'];
      if (items is! List ||
          items.any((item) => item is! Map) ||
          total is! num ||
          discount is! num ||
          orderType is! String) {
        throw StateError('Saved bill is incomplete; receipt was not sent.');
      }
      final bytes = await _receiptBuilder.buildReceiptBytes(
        cafeName: cafeName,
        billNumber: billId,
        orderType: orderType,
        items: items
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false),
        total: total.toDouble(),
        discount: discount.toDouble(),
        paperWidth: settings.paperWidth,
        encoding: settings.encoding,
        feedLines: settings.feedLines,
        cut: settings.cut,
      );
      if (!await _settingsStore.claimAutoPrint(
          cafeId, billId, settings.address)) {
        return const ReceiptPrintResult(ReceiptPrintStatus.alreadyAttempted);
      }
      // Marked before transport: Bluetooth cannot prove physical delivery.
      await _transport.send(settings, bytes);
      return const ReceiptPrintResult(ReceiptPrintStatus.sent);
    } catch (error) {
      return ReceiptPrintResult(ReceiptPrintStatus.failed, error: error);
    }
  }
}
