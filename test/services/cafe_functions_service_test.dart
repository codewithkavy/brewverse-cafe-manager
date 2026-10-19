import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';

void main() {
  group('CafeFunctionsService', () {
    test('sends business mutations to their trusted callable endpoints',
        () async {
      final calls = <String, Map<String, dynamic>>{};
      final service = CafeFunctionsService(
        invoker: (name, data) async {
          calls[name] = data;
          return switch (name) {
            'createCafe' => {'cafeId': 'cafe-a'},
            'createStockItem' => {'stockItemId': 'beans-a'},
            'checkout' => {'billId': 'bill-a', 'duplicate': false},
            'getSalesSummary' => {'grossRevenue': 12.5},
            'listCafeMemberships' => {
                'memberships': [
                  {
                    'uid': 'owner-a',
                    'cafeId': 'cafe-a',
                    'role': 'owner',
                    'status': 'active',
                  },
                ],
                'hasMore': false,
                'nextPageToken': null,
              },
            _ => <String, dynamic>{},
          };
        },
      );
      const item = StockItem(
        id: '',
        name: 'Espresso beans',
        category: 'ingredient',
        unit: 'g',
        quantity: 100,
        minimumQuantity: 10,
        purchasePricePerUnit: 0.12,
        sellingPrice: 0,
      );

      expect(await service.createCafe(name: 'Morning Brew'), 'cafe-a');
      expect(
        await service.createStockItem(cafeId: 'cafe-a', item: item),
        'beans-a',
      );
      await service.addStock(
        cafeId: 'cafe-a',
        stockItemId: 'beans-a',
        quantity: 30,
        reason: 'Supplier delivery',
      );
      await service.saveRecipe(
        cafeId: 'cafe-a',
        productId: 'latte-a',
        ingredients: const [
          {'stockItemId': 'beans-a', 'quantity': 18},
        ],
      );
      expect(
        await service.checkout(
          cafeId: 'cafe-a',
          checkoutId: 'bill-a',
          cart: const {'latte-a': 2},
          orderType: 'dineIn',
        ),
        'bill-a',
      );
      await service.grantCafeMembership(
        cafeId: 'cafe-a',
        targetEmail: 'staff@example.test',
        role: 'staff',
      );
      await service.revokeCafeMembership(
        cafeId: 'cafe-a',
        targetUid: 'staff-a',
      );
      final memberships = await service.listCafeMemberships(cafeId: 'cafe-a');
      final summary = await service.getSalesSummary(
        cafeId: 'cafe-a',
        startAt: DateTime.utc(2026, 10, 16),
        endAt: DateTime.utc(2026, 10, 17),
      );

      expect(
          calls.keys,
          containsAll([
            'createCafe',
            'createStockItem',
            'addStock',
            'saveRecipe',
            'checkout',
            'grantCafeMembership',
            'revokeCafeMembership',
            'listCafeMemberships',
            'getSalesSummary',
          ]));
      expect(calls['createStockItem']!['cafeId'], 'cafe-a');
      expect(calls['createStockItem']!['item'], {
        'name': 'Espresso beans',
        'category': 'ingredient',
        'unit': 'g',
        'quantity': 100.0,
        'minimumQuantity': 10.0,
        'purchasePricePerUnit': 0.12,
        'sellingPrice': 0.0,
        'photoUrl': '',
      });
      expect(calls['checkout']!['cart'], {'latte-a': 2});
      expect(calls['grantCafeMembership']!['email'], 'staff@example.test');
      expect(calls['getSalesSummary']!['startAt'], '2026-10-16T00:00:00.000Z');
      expect(summary['grossRevenue'], 12.5);
      expect(memberships.memberships.single.uid, 'owner-a');
      expect(memberships.hasMore, isFalse);
    });

    test('passes a membership cursor and parses the next-page result',
        () async {
      final calls = <String, Map<String, dynamic>>{};
      final service = CafeFunctionsService(
        invoker: (name, data) async {
          calls[name] = data;
          return {
            'memberships': [
              {
                'uid': 'staff-b',
                'cafeId': 'cafe-a',
                'role': 'staff',
                'status': 'active',
              },
            ],
            'hasMore': true,
            'nextPageToken': 'staff-b_cafe-a',
          };
        },
      );

      final page = await service.listCafeMemberships(
        cafeId: 'cafe-a',
        pageToken: 'staff-a_cafe-a',
      );

      expect(calls['listCafeMemberships'], {
        'cafeId': 'cafe-a',
        'pageToken': 'staff-a_cafe-a',
      });
      expect(page.memberships.single.uid, 'staff-b');
      expect(page.hasMore, isTrue);
      expect(page.nextPageToken, 'staff-b_cafe-a');
    });

    test('rejects callable responses missing a required document ID', () async {
      final service = CafeFunctionsService(invoker: (_, __) async => {});

      await expectLater(
        service.createCafe(name: 'Morning Brew'),
        throwsFormatException,
      );
    });

    test('reads and saves café loyalty policy through trusted callables',
        () async {
      final calls = <String, Map<String, dynamic>>{};
      final settings = <String, dynamic>{
        'enabled': true,
        'spendUnitMinor': 10000,
        'pointsPerSpendUnit': 4,
        'pointValueMinor': 100,
        'maxRedemptionPercent': 80,
        'bonusTiers': const [
          {'minimumSpendMinor': 50000, 'points': 5},
        ],
        'expiryMonths': 12,
        'reverseEarnedOnRefund': true,
        'restoreRedeemedOnRefund': true,
      };
      final service = CafeFunctionsService(
        invoker: (name, data) async {
          calls[name] = data;
          return {'settings': settings};
        },
      );

      expect(
        await service.getLoyaltySettings(cafeId: 'cafe-a'),
        settings,
      );
      expect(
        await service.saveLoyaltySettings(
          cafeId: 'cafe-a',
          settings: settings,
        ),
        settings,
      );
      expect(calls['getLoyaltySettings'], {'cafeId': 'cafe-a'});
      expect(calls['saveLoyaltySettings'], {
        'cafeId': 'cafe-a',
        'settings': settings,
      });
    });

    test('looks up a customer by phone inside the selected café', () async {
      final calls = <String, Map<String, dynamic>>{};
      final service = CafeFunctionsService(
        invoker: (name, data) async {
          calls[name] = data;
          return {
            'customer': {
              'found': true,
              'customerId': 'hashed-customer-id',
              'phoneNumber': '+919876543210',
              'pointsBalance': 8,
            },
          };
        },
      );

      final customer = await service.lookupLoyaltyCustomer(
        cafeId: 'cafe-a',
        phoneNumber: '+91 98765-43210',
      );

      expect(calls['lookupLoyaltyCustomer'], {
        'cafeId': 'cafe-a',
        'phoneNumber': '+91 98765-43210',
      });
      expect(customer['pointsBalance'], 8);
    });

    test('routes bill refunds and voids through trusted callables', () async {
      final calls = <String, Map<String, dynamic>>{};
      final service = CafeFunctionsService(
        invoker: (name, data) async {
          calls[name] = data;
          return {
            'status': name == 'refundBill' ? 'partially_refunded' : 'void'
          };
        },
      );
      await service.refundBill(
        cafeId: 'cafe-a',
        billId: 'bill-a',
        adjustmentId: 'refund-a',
        amountMinor: 500,
        reason: 'Returned drink',
      );
      await service.voidBill(
        cafeId: 'cafe-a',
        billId: 'bill-b',
        adjustmentId: 'void-b',
        reason: 'Duplicate order',
      );

      expect(calls['refundBill'], {
        'cafeId': 'cafe-a',
        'billId': 'bill-a',
        'adjustmentId': 'refund-a',
        'amountMinor': 500,
        'reason': 'Returned drink',
      });
      expect(calls['voidBill'], {
        'cafeId': 'cafe-a',
        'billId': 'bill-b',
        'adjustmentId': 'void-b',
        'reason': 'Duplicate order',
      });
    });

    test('rejects team results from another café', () async {
      final service = CafeFunctionsService(
        invoker: (_, __) async => {
          'memberships': [
            {
              'uid': 'member-b',
              'cafeId': 'cafe-b',
              'role': 'staff',
              'status': 'active',
            },
          ],
          'hasMore': false,
          'nextPageToken': null,
        },
      );

      await expectLater(
        service.listCafeMemberships(cafeId: 'cafe-a'),
        throwsFormatException,
      );
    });
  });
}
