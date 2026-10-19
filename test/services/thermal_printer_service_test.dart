import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:brewverse_cafe_manager/services/thermal_printer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThermalPrinterService.buildReceiptBytes', () {
    final service = ThermalPrinterService();

    test('builds a receipt containing the saved sale details', () async {
      final bytes = await service.buildReceiptBytes(
        cafeName: 'Midnight Espresso',
        billNumber: 'bill-123',
        orderType: 'dineIn',
        items: [
          {
            'name': 'Latte',
            'quantity': 2,
            'unitPrice': 120.0,
            'lineTotal': 240.0,
          },
        ],
        total: 240.0,
      );
      final receipt = latin1.decode(bytes);

      expect(receipt, contains('Midnight Espresso'));
      expect(receipt, contains('BILL bill-123'));
      expect(receipt, contains('DINE IN'));
      expect(receipt, contains('2 x Rs 120.00'));
      expect(receipt, contains('TOTAL  Rs 240.00'));
    });

    test('prints the loyalty discount and net paid total', () async {
      final bytes = await service.buildReceiptBytes(
        cafeName: 'Midnight Espresso',
        billNumber: 'bill-loyalty',
        orderType: 'dineIn',
        items: [
          {
            'name': 'Latte',
            'quantity': 1,
            'unitPrice': 100.0,
            'lineTotal': 100.0,
          },
        ],
        total: 80,
        discount: 20,
      );

      final receipt = latin1.decode(bytes);
      expect(receipt, contains('SUBTOTAL  Rs 100.00'));
      expect(receipt, contains('LOYALTY  -Rs 20.00'));
      expect(receipt, contains('TOTAL  Rs 80.00'));
    });

    test('replaces unsupported non-ASCII receipt characters', () async {
      final bytes = await service.buildReceiptBytes(
        cafeName: 'Café ☕',
        billNumber: 'bill-1',
        orderType: 'takeaway',
        items: [
          {
            'name': 'Café ☕',
            'quantity': 1,
            'unitPrice': 10.0,
            'lineTotal': 10.0,
          },
        ],
        total: 10.0,
      );

      expect(latin1.decode(bytes), contains('Caf? ?'));
      expect(latin1.decode(bytes), contains('TAKEAWAY'));
    });

    test('rejects an empty receipt', () async {
      await expectLater(
        service.buildReceiptBytes(
          cafeName: 'Cafe',
          billNumber: 'bill-1',
          orderType: 'dineIn',
          items: const [],
          total: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid item quantities before printing', () async {
      await expectLater(
        service.buildReceiptBytes(
          cafeName: 'Cafe',
          billNumber: 'bill-1',
          orderType: 'dineIn',
          items: [
            {
              'name': 'Latte',
              'quantity': 0,
              'unitPrice': 10.0,
              'lineTotal': 0.0,
            },
          ],
          total: 0,
        ),
        throwsStateError,
      );
    });

    test('rejects a line total that differs from quantity times unit price',
        () async {
      await expectLater(
        service.buildReceiptBytes(
          cafeName: 'Cafe',
          billNumber: 'bill-1',
          orderType: 'dineIn',
          items: [
            {
              'name': 'Latte',
              'quantity': 2,
              'unitPrice': 10.00,
              'lineTotal': 19.99,
            },
          ],
          total: 19.99,
        ),
        throwsStateError,
      );
    });

    test('rejects a receipt total that differs from the saved line totals',
        () async {
      await expectLater(
        service.buildReceiptBytes(
          cafeName: 'Cafe',
          billNumber: 'bill-1',
          orderType: 'dineIn',
          items: [
            {
              'name': 'Latte',
              'quantity': 2,
              'unitPrice': 10.00,
              'lineTotal': 20.00,
            },
          ],
          total: 19.99,
        ),
        throwsStateError,
      );
    });

    test('rejects unsupported order types', () async {
      await expectLater(
        service.buildReceiptBytes(
          cafeName: 'Cafe',
          billNumber: 'bill-1',
          orderType: 'delivery',
          items: [
            {
              'name': 'Latte',
              'quantity': 1,
              'unitPrice': 10.0,
              'lineTotal': 10.0,
            },
          ],
          total: 10,
        ),
        throwsArgumentError,
      );
    });
  });
}
