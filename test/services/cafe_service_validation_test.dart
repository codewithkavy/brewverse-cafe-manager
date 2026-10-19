import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:flutter_test/flutter_test.dart';

StockItem stockItem({
  String name = 'Beans',
  String category = 'ingredient',
  String unit = 'g',
  double quantity = 0,
  double minimumQuantity = 5,
  double purchasePricePerUnit = 1,
  double sellingPrice = 0,
}) =>
    StockItem(
      id: '',
      name: name,
      category: category,
      unit: unit,
      quantity: quantity,
      minimumQuantity: minimumQuantity,
      purchasePricePerUnit: purchasePricePerUnit,
      sellingPrice: sellingPrice,
    );

void main() {
  group('CafeService.validateNewItem', () {
    test('accepts zero or positive finite inventory values', () {
      expect(() => CafeService.validateNewItem(stockItem()), returnsNormally);
      expect(
        () => CafeService.validateNewItem(stockItem(quantity: 2.5)),
        returnsNormally,
      );
    });

    test('rejects empty names, unsupported categories, and empty units', () {
      expect(
        () => CafeService.validateNewItem(stockItem(name: '  ')),
        throwsArgumentError,
      );
      expect(
        () => CafeService.validateNewItem(stockItem(category: 'other')),
        throwsArgumentError,
      );
      expect(
        () => CafeService.validateNewItem(stockItem(unit: '')),
        throwsArgumentError,
      );
    });

    test('rejects negative and non-finite inventory values', () {
      expect(
        () => CafeService.validateNewItem(stockItem(quantity: -1)),
        throwsArgumentError,
      );
      expect(
        () => CafeService.validateNewItem(
          stockItem(minimumQuantity: double.infinity),
        ),
        throwsArgumentError,
      );
      expect(
        () => CafeService.validateNewItem(
          stockItem(purchasePricePerUnit: double.nan),
        ),
        throwsArgumentError,
      );
      expect(
        () => CafeService.validateNewItem(stockItem(sellingPrice: -0.01)),
        throwsArgumentError,
      );
    });
  });

  group('CafeService.validateRecipe', () {
    test('accepts ingredient and optional packaging quantities', () {
      expect(
        () => CafeService.validateRecipe(
          ingredients: [
            {'stockItemId': 'beans', 'quantity': 18.0},
            {'stockItemId': 'milk', 'quantity': 120},
          ],
          packaging: [
            {'stockItemId': 'cup', 'quantity': 1},
          ],
        ),
        returnsNormally,
      );
    });

    test('requires at least one ingredient', () {
      expect(
        () => CafeService.validateRecipe(ingredients: []),
        throwsArgumentError,
      );
    });

    test('rejects blank or non-string stock item IDs', () {
      for (final id in ['', '  ', null, 12]) {
        expect(
          () => CafeService.validateRecipe(ingredients: [
            {'stockItemId': id, 'quantity': 1},
          ]),
          throwsArgumentError,
        );
      }
    });

    test('rejects non-positive, non-finite, or non-numeric quantities', () {
      for (final quantity in [0, -1, double.infinity, double.nan, 'one']) {
        expect(
          () => CafeService.validateRecipe(ingredients: [
            {'stockItemId': 'beans', 'quantity': quantity},
          ]),
          throwsArgumentError,
        );
      }
    });

    test('validates packaging lines as strictly as ingredients', () {
      expect(
        () => CafeService.validateRecipe(
          ingredients: [
            {'stockItemId': 'beans', 'quantity': 1},
          ],
          packaging: [
            {'stockItemId': 'cup', 'quantity': 0},
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('CafeService checkout helpers', () {
    test('builds a stable request key independent of map insertion order', () {
      expect(
        CafeService.buildCheckoutRequestKey(
          orderType: 'dineIn',
          cart: {'latte': 2, 'tea': 1},
        ),
        CafeService.buildCheckoutRequestKey(
          orderType: 'dineIn',
          cart: {'tea': 1, 'latte': 2},
        ),
      );
      expect(
        CafeService.buildCheckoutRequestKey(
          orderType: 'dineIn',
          cart: {'latte': 2},
        ),
        isNot(
          CafeService.buildCheckoutRequestKey(
            orderType: 'takeaway',
            cart: {'latte': 2},
          ),
        ),
      );
    });

    test('request key cannot collide when document IDs contain delimiters', () {
      final first = CafeService.buildCheckoutRequestKey(
        orderType: 'dineIn',
        cart: {'a': 1, 'b': 2},
      );
      final second = CafeService.buildCheckoutRequestKey(
        orderType: 'dineIn',
        cart: {'a:1|b': 2},
      );

      expect(first, isNot(second));
    });

    test('returns the prior bill for an identical retry', () {
      expect(
        CafeService.resolveExistingCheckout(
          existingBill: {'requestKey': 'takeaway|latte:1'},
          requestKey: 'takeaway|latte:1',
          billId: 'bill-123',
        ),
        'bill-123',
      );
    });

    test('accepts the previous delimiter key for an old bill retry', () {
      final newKey = CafeService.buildCheckoutRequestKey(
        orderType: 'takeaway',
        cart: {'latte': 1},
      );

      expect(
        CafeService.resolveExistingCheckout(
          existingBill: {
            'requestKey': 'takeaway|latte:1',
            'orderType': 'takeaway',
            'items': [
              {'productId': 'latte', 'quantity': 1},
            ],
          },
          requestKey: newKey,
          legacyRequestKey: 'takeaway|latte:1',
          orderType: 'takeaway',
          cart: {'latte': 1},
          billId: 'bill-123',
        ),
        'bill-123',
      );
    });

    test('legacy delimiter collisions do not treat a different cart as retry',
        () {
      expect(
        () => CafeService.resolveExistingCheckout(
          existingBill: {
            'requestKey': 'dineIn|a:1|b:2',
            'orderType': 'dineIn',
            'items': [
              {'productId': 'a', 'quantity': 1},
              {'productId': 'b', 'quantity': 2},
            ],
          },
          requestKey: CafeService.buildCheckoutRequestKey(
            orderType: 'dineIn',
            cart: {'a:1|b': 2},
          ),
          legacyRequestKey: 'dineIn|a:1|b:2',
          orderType: 'dineIn',
          cart: {'a:1|b': 2},
          billId: 'bill-123',
        ),
        throwsStateError,
      );
    });

    test('rejects reusing a checkout ID for a different cart', () {
      expect(
        () => CafeService.resolveExistingCheckout(
          existingBill: {'requestKey': 'takeaway|latte:1'},
          requestKey: 'takeaway|latte:2',
          billId: 'bill-123',
        ),
        throwsStateError,
      );
    });

    test('calculates combined recipe deductions and excludes dine-in packaging',
        () {
      final cart = {'latte': 2, 'tea': 1};
      final recipes = {
        'latte': {
          'ingredients': [
            {'stockItemId': 'beans', 'quantity': 18},
            {'stockItemId': 'milk', 'quantity': 120},
          ],
          'packaging': [
            {'stockItemId': 'cup', 'quantity': 1},
          ],
        },
        'tea': {
          'ingredients': [
            {'stockItemId': 'beans', 'quantity': 2},
          ],
          'packaging': [
            {'stockItemId': 'cup', 'quantity': 1},
          ],
        },
      };

      expect(
        CafeService.calculateRequiredStock(
          cart: cart,
          recipes: recipes,
          includePackaging: false,
        ),
        {'beans': 38, 'milk': 240},
      );
      expect(
        CafeService.calculateRequiredStock(
          cart: cart,
          recipes: recipes,
          includePackaging: true,
        ),
        {'beans': 38, 'milk': 240, 'cup': 3},
      );
    });
  });
}
