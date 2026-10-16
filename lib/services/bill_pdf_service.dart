import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BillPdfService {
  Future<Uint8List> create({
    required String cafeName,
    required String billNumber,
    required List<Map<String, dynamic>> items,
    required double total,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                cafeName,
                style: const pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Text('Bill: $billNumber'),
            pw.Divider(),
            pw.TableHelper.fromTextArray(
              headers: ['Item', 'Qty', 'Price', 'Amount'],
              data: items.map((item) {
                final qty = (item['quantity'] as num).toDouble();
                final price = (item['unitPrice'] as num).toDouble();
                return [
                  '${item['name']}',
                  '$qty',
                  'Rs. ${price.toStringAsFixed(2)}',
                  'Rs. ${(qty * price).toStringAsFixed(2)}',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Total: Rs. ${total.toStringAsFixed(2)}',
                style: const pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Spacer(),
            pw.Center(child: pw.Text('Thank you for visiting!')),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  Future<void> printOrShare(Uint8List bytes) async {
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }
}
