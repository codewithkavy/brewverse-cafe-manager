import 'package:flutter_thermal_printer/flutter_thermal_printer.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import 'checked_ble_receipt_writer.dart';
import 'printer_settings_store.dart';

enum ReceiptPaperWidth {
  mm58(58, PaperSize.mm58),
  mm80(80, PaperSize.mm80);

  const ReceiptPaperWidth(this.millimeters, this.paperSize);

  final int millimeters;
  final PaperSize paperSize;
}

class ThermalPrinterService {
  ThermalPrinterService({CheckedBleReceiptWriter? byteWriter})
      : _byteWriter = byteWriter ?? CheckedBleReceiptWriter();

  static const int _maxSafeMinorUnits = 9007199254740991;
  final CheckedBleReceiptWriter _byteWriter;

  Future<void> sendReceiptBytes(Printer device, List<int> bytes) =>
      _byteWriter.write(device, bytes);

  String _printerText(String value,
          [ReceiptEncoding encoding = ReceiptEncoding.ascii]) =>
      String.fromCharCodes(
        value.runes.map((rune) => (rune >= 32 && rune <= 126) ||
                (encoding == ReceiptEncoding.cp1252 &&
                    rune >= 160 &&
                    rune <= 255)
            ? rune
            : 63),
      );

  Future<void> printReceipt({
    required Printer device,
    required String cafeName,
    required String billNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    required double total,
    double discount = 0,
    ReceiptPaperWidth paperWidth = ReceiptPaperWidth.mm58,
    DateTime? issuedAt,
    String? transactionStatus,
    bool isReprint = false,
    ReceiptEncoding encoding = ReceiptEncoding.ascii,
    int feedLines = 3,
    bool cut = true,
  }) async {
    final bytes = await buildReceiptBytes(
      cafeName: cafeName,
      billNumber: billNumber,
      orderType: orderType,
      items: items,
      total: total,
      discount: discount,
      paperWidth: paperWidth,
      issuedAt: issuedAt,
      transactionStatus: transactionStatus,
      isReprint: isReprint,
      encoding: encoding,
      feedLines: feedLines,
      cut: cut,
    );

    await sendReceiptBytes(device, bytes);
  }

  Future<List<int>> buildReceiptBytes({
    required String cafeName,
    required String billNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    required double total,
    double discount = 0,
    ReceiptPaperWidth paperWidth = ReceiptPaperWidth.mm58,
    DateTime? issuedAt,
    String? transactionStatus,
    bool isReprint = false,
    ReceiptEncoding encoding = ReceiptEncoding.ascii,
    int feedLines = 3,
    bool cut = true,
  }) async {
    if (feedLines < 0 || feedLines > 10) {
      throw ArgumentError('Feed must be 0–10 lines.');
    }
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
    final generator = Generator(paperWidth.paperSize, profile);
    final bytes = <int>[...generator.reset()];
    if (encoding == ReceiptEncoding.cp1252) {
      bytes.addAll(generator.setGlobalCodeTable('CP1252'));
    }
    final columns = paperWidth == ReceiptPaperWidth.mm58 ? 32 : 48;
    String text(String value) => _printerText(value, encoding);
    var totalMinorUnits = 0;
    bytes.addAll(
      generator.text(
        text(cafeName),
        styles: const PosStyles(
            align: PosAlign.center, bold: true, height: PosTextSize.size2),
      ),
    );
    bytes.addAll(generator.text('BILL ${text(billNumber)}',
        styles: const PosStyles(align: PosAlign.center)));
    if (isReprint) {
      bytes.addAll(generator.text('RECEIPT COPY',
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (issuedAt != null) {
      bytes.addAll(generator.text(text(issuedAt.toLocal().toString()),
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (transactionStatus != null) {
      bytes.addAll(generator.text('STATUS: ${text(transactionStatus)}',
          styles: const PosStyles(align: PosAlign.center)));
    }
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
      for (final line
          in wrapReceiptText(text('${item['name'] ?? 'Item'}'), columns)) {
        bytes.addAll(generator.text(line));
      }
      final left = '${quantity.toInt()} x Rs ${unitPrice.toStringAsFixed(2)}';
      final right = 'Rs ${lineTotal.toStringAsFixed(2)}';
      if (left.length + right.length + 1 <= columns) {
        bytes.addAll(generator.text(
            '$left${' ' * (columns - left.length - right.length)}$right'));
      } else {
        bytes.addAll(generator.text(left));
        bytes.addAll(generator.text(right,
            styles: const PosStyles(align: PosAlign.right)));
      }
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
        '${isReprint ? 'DISCOUNT' : 'LOYALTY'}  -Rs ${(discountMinorUnits / 100).toStringAsFixed(2)}',
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
    bytes.addAll(generator.feed(feedLines));
    if (cut) bytes.addAll(generator.cut());

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

/// Word-wrap names, splitting unbroken identifiers without losing characters.
List<String> wrapReceiptText(String value, int columns) {
  final lines = <String>[];
  var remaining = value.trim();
  while (remaining.length > columns) {
    final space = remaining.lastIndexOf(' ', columns);
    final end = space > 0 ? space : columns;
    lines.add(remaining.substring(0, end));
    remaining = remaining.substring(end).trimLeft();
  }
  if (remaining.isNotEmpty) lines.add(remaining);
  return lines;
}
