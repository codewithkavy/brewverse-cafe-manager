import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

class ThermalPrinterService {
  static const int _maxSafeMinorUnits = 9007199254740991;
  final FlutterThermalPrinter _printer = FlutterThermalPrinter.instance;

  String _printerText(String value) => String.fromCharCodes(
        value.runes.map((rune) => rune >= 32 && rune <= 126 ? rune : 63),
      );

  Future<void> printReceipt({
    required Printer device,
    required String cafeName,
    required String billNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    required double total,
    double discount = 0,
  }) async {
    final bytes = await buildReceiptBytes(
      cafeName: cafeName,
      billNumber: billNumber,
      orderType: orderType,
      items: items,
      total: total,
      discount: discount,
    );

    await _printer.printData(device, bytes, longData: true);
  }

  Future<List<int>> buildReceiptBytes({
    required String cafeName,
    required String billNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    required double total,
    double discount = 0,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Cannot print a receipt without bill items.');
    }
    if (!total.isFinite || total < 0 || !discount.isFinite || discount < 0) {
      throw ArgumentError('Receipt total must be finite and non-negative.');
    }
    if (orderType != 'dineIn' && orderType != 'takeaway') {
      throw ArgumentError('Receipt order type is not supported.');
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];
    var totalMinorUnits = 0;
    bytes.addAll(
      generator.text(
        _printerText(cafeName),
        styles: const PosStyles(
            align: PosAlign.center, bold: true, height: PosTextSize.size2),
      ),
    );
    bytes.addAll(generator.text('BILL ${_printerText(billNumber)}',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(
        orderType == 'takeaway' ? 'TAKEAWAY' : 'DINE IN',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.hr());

    for (final item in items) {
      final quantity = item['quantity'];
      final unitPrice = item['unitPrice'];
      final lineTotal = item['lineTotal'];
      if (quantity is! num ||
          unitPrice is! num ||
          lineTotal is! num ||
          !quantity.toDouble().isFinite ||
          !unitPrice.toDouble().isFinite ||
          !lineTotal.toDouble().isFinite ||
          quantity <= 0 ||
          quantity % 1 != 0 ||
          quantity > 10000 ||
          unitPrice < 0 ||
          lineTotal < 0) {
        throw StateError('Bill contains an invalid item row.');
      }
      final unitMinorUnits = _toMinorUnits(unitPrice);
      final lineMinorUnits = _toMinorUnits(lineTotal);
      final expectedLineMinorUnits = unitMinorUnits * quantity.toInt();
      if (expectedLineMinorUnits > _maxSafeMinorUnits ||
          lineMinorUnits != expectedLineMinorUnits ||
          totalMinorUnits > _maxSafeMinorUnits - lineMinorUnits) {
        throw StateError('Bill item totals do not match the saved prices.');
      }
      totalMinorUnits += lineMinorUnits;
      bytes.addAll(generator.text(_printerText('${item['name'] ?? 'Item'}')));
      bytes.addAll(
        generator.row([
          PosColumn(
            text: '${quantity.toString()} x Rs ${unitPrice.toStringAsFixed(2)}',
            width: 7,
          ),
          PosColumn(
            text: 'Rs ${lineTotal.toStringAsFixed(2)}',
            width: 5,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }

    final discountMinorUnits = _toMinorUnits(discount);
    if (discountMinorUnits > totalMinorUnits ||
        _toMinorUnits(total) != totalMinorUnits - discountMinorUnits) {
      throw StateError('Bill total does not match its saved items.');
    }

    bytes.addAll(generator.hr());
    if (discountMinorUnits > 0) {
      bytes.addAll(generator.text(
        'SUBTOTAL  Rs ${(totalMinorUnits / 100).toStringAsFixed(2)}',
        styles: const PosStyles(align: PosAlign.right),
      ));
      bytes.addAll(generator.text(
        'LOYALTY  -Rs ${(discountMinorUnits / 100).toStringAsFixed(2)}',
        styles: const PosStyles(align: PosAlign.right),
      ));
    }
    bytes.addAll(
      generator.text(
        'TOTAL  Rs ${total.toStringAsFixed(2)}',
        styles: const PosStyles(
            align: PosAlign.right, bold: true, height: PosTextSize.size2),
      ),
    );
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    return bytes;
  }

  int _toMinorUnits(num value) {
    final scaled = value * 100;
    if (!scaled.isFinite || scaled > _maxSafeMinorUnits) {
      throw StateError('Bill contains an amount too large to print safely.');
    }
    return scaled.round();
  }
}
