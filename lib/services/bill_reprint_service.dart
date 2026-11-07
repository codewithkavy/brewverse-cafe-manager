import '../models/saved_bill.dart';
import 'bill_history_service.dart';
import 'thermal_printer_service.dart';

/// Intentionally has no checkout, inventory or loyalty write dependencies.
class BillReprintService {
  BillReprintService(this.repository, {ThermalPrinterService? receiptBuilder})
      : _builder = receiptBuilder ?? ThermalPrinterService();
  final BillHistoryRepository repository;
  final ThermalPrinterService _builder;
  bool _busy = false;

  Future<bool> reprint(
      String billId, Future<void> Function(SavedBill bill) showPrinter) async {
    if (_busy) return false;
    _busy = true;
    try {
      // Recheck authorization and latest status before every printer dialog.
      final bill = await repository.get(billId);
      if (bill == null ||
          bill.id != billId ||
          bill.text('cafeId') != repository.cafeId) {
        throw StateError('Bill is no longer accessible in this café.');
      }
      if (!bill.hasReceiptFields) {
        throw StateError(
            'This bill is missing saved receipt information. Nothing was printed.');
      }
      // Fail before opening Bluetooth if historical amounts are inconsistent.
      await _builder.buildReceiptBytes(
          cafeName: 'Receipt copy',
          billNumber: bill.id,
          orderType: bill.text('orderType')!,
          items: bill.items,
          total: bill.amount('total')!.toDouble(),
          discount: bill.amount('discount')!.toDouble());
      await showPrinter(bill);
      return true;
    } finally {
      _busy = false;
    }
  }
}
