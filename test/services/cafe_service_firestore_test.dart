import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

StockItem item({
  String id = '',
  String name = 'Coffee beans',
  String category = 'ingredient',
  double quantity = 0,
  double sellingPrice = 0,
}) =>
    StockItem(
      id: id,
      name: name,
      category: category,
      unit: 'g',
      quantity: quantity,
      minimumQuantity: 5,
      purchasePricePerUnit: 0.02,
      sellingPrice: sellingPrice,
    );

Future<void> seedItem(
  FakeFirebaseFirestore db,
  String id, {
  required String name,
  required String category,
  required double quantity,
  double sellingPrice = 0,
}) async {
  await db.collection('stock_items').doc(id).set({
    ...item(
      name: name,
      category: category,
      quantity: quantity,
      sellingPrice: sellingPrice,
    ).toMap(),
  });
}

void main() {
  group('CafeService Firestore transactions', () {
    test('creates opening stock and movement together', () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);

      final id = await service.addItem(item(quantity: 25));

      final saved = await db.collection('stock_items').doc(id).get();
      final movements = await db.collection('stock_movements').get();
      expect(saved.data()?['quantity'], 25);
      expect(movements.docs, hasLength(1));
      expect(movements.docs.single.data(), containsPair('stockItemId', id));
      expect(movements.docs.single.data(), containsPair('type', 'addition'));
      expect(movements.docs.single.data(), containsPair('quantityChange', 25));
      expect(movements.docs.single.data(), containsPair('quantityAfter', 25));
      expect(movements.docs.single.data(),
          containsPair('reason', 'Opening stock'));
    });

    test('zero opening quantity creates no movement', () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);

      await service.addItem(item());

      expect((await db.collection('stock_movements').get()).docs, isEmpty);
    });

    test('stock additions update quantity and append one movement', () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);
      await seedItem(db, 'beans',
          name: 'Beans', category: 'ingredient', quantity: 8);

      await service.addStock(
          itemId: 'beans', quantity: 2.5, reason: 'Delivery');

      final saved = await db.collection('stock_items').doc('beans').get();
      final movements = await db.collection('stock_movements').get();
      final history = await service.watchRecentMovements().first;
      expect(saved.data()?['quantity'], 10.5);
      expect(movements.docs, hasLength(1));
      expect(movements.docs.single.data(), containsPair('quantityChange', 2.5));
      expect(movements.docs.single.data(), containsPair('quantityAfter', 10.5));
      expect(
          movements.docs.single.data(), containsPair('stockItemName', 'Beans'));
      expect(history, hasLength(1));
      expect(history.single['stockItemId'], 'beans');
      expect(movements.docs.single.data(), containsPair('reason', 'Delivery'));
    });

    test('editing item details preserves the current live quantity', () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);
      await seedItem(db, 'beans',
          name: 'Beans', category: 'ingredient', quantity: 8);

      await service.updateItem(
        item(id: 'beans', name: 'House blend', quantity: 2),
      );

      final saved = await db.collection('stock_items').doc('beans').get();
      expect(saved.data()?['name'], 'House blend');
      expect(saved.data()?['quantity'], 8);
    });

    test('tenant item edits preserve quantity and café ownership', () async {
      final db = FakeFirebaseFirestore();
      await seedItem(db, 'beans',
          name: 'Beans', category: 'ingredient', quantity: 8);
      await db.collection('stock_items').doc('beans').update({
        'cafeId': 'cafe-a',
      });
      final service = CafeService(firestore: db, cafeId: 'cafe-a');

      await service.updateItem(
        item(id: 'beans', name: 'House blend', quantity: 2),
      );

      final saved =
          (await db.collection('stock_items').doc('beans').get()).data()!;
      expect(saved['name'], 'House blend');
      expect(saved['quantity'], 8);
      expect(saved['cafeId'], 'cafe-a');
    });

    test('tenant item edits reject stock belonging to another café', () async {
      final db = FakeFirebaseFirestore();
      await seedItem(db, 'beans',
          name: 'Beans', category: 'ingredient', quantity: 8);
      await db.collection('stock_items').doc('beans').update({
        'cafeId': 'cafe-b',
      });
      final service = CafeService(firestore: db, cafeId: 'cafe-a');

      await expectLater(
        service.updateItem(
          item(id: 'beans', name: 'House blend', quantity: 2),
        ),
        throwsStateError,
      );

      final saved =
          (await db.collection('stock_items').doc('beans').get()).data()!;
      expect(saved['name'], 'Beans');
      expect(saved['quantity'], 8);
      expect(saved['cafeId'], 'cafe-b');
    });

    test('recent movement history rejects unreasonable limits', () {
      final service = CafeService(firestore: FakeFirebaseFirestore());
      expect(() => service.watchRecentMovements(limit: 0), throwsArgumentError);
      expect(
          () => service.watchRecentMovements(limit: 501), throwsArgumentError);
    });

    test('checkout commits bill, deductions and movements once across retry',
        () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);
      await seedItem(db, 'latte',
          name: 'Latte', category: 'finished', quantity: 0, sellingPrice: 4.5);
      await seedItem(db, 'beans',
          name: 'Beans', category: 'ingredient', quantity: 100);
      await seedItem(db, 'cup',
          name: 'Cup', category: 'ingredient', quantity: 3);
      await service.saveRecipe(
        productId: 'latte',
        ingredients: [
          {'stockItemId': 'beans', 'quantity': 18}
        ],
        packaging: [
          {'stockItemId': 'cup', 'quantity': 1}
        ],
      );

      final first = await service.checkout(
        checkoutId: 'checkout-1',
        cart: {'latte': 2},
        orderType: 'takeaway',
      );
      final retry = await service.checkout(
        checkoutId: 'checkout-1',
        cart: {'latte': 2},
        orderType: 'takeaway',
      );

      expect(first, 'checkout-1');
      expect(retry, first);
      expect(
          (await db.collection('stock_items').doc('beans').get())
              .data()?['quantity'],
          64);
      expect(
          (await db.collection('stock_items').doc('cup').get())
              .data()?['quantity'],
          1);
      final bills = await db.collection('bills').get();
      final movements = await db.collection('stock_movements').get();
      expect(bills.docs, hasLength(1));
      expect(bills.docs.single.data()['total'], 9.0);
      expect(movements.docs, hasLength(2));
      expect(
          movements.docs.every((doc) => doc.data()['type'] == 'sale'), isTrue);
    });

    test('checkout stores line and bill totals in whole paise', () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);
      await seedItem(db, 'espresso',
          name: 'Espresso',
          category: 'finished',
          quantity: 0,
          sellingPrice: 0.1);
      await seedItem(db, 'rounding',
          name: 'Rounding test',
          category: 'finished',
          quantity: 0,
          sellingPrice: 0.105);
      await seedItem(db, 'beans',
          name: 'Beans', category: 'ingredient', quantity: 10);
      for (final productId in ['espresso', 'rounding']) {
        await service.saveRecipe(
          productId: productId,
          ingredients: [
            {'stockItemId': 'beans', 'quantity': 1}
          ],
        );
      }

      await service.checkout(
        checkoutId: 'checkout-paise',
        cart: {'espresso': 3, 'rounding': 3},
        orderType: 'dineIn',
      );

      final bill =
          (await db.collection('bills').doc('checkout-paise').get()).data()!;
      final lines = (bill['items'] as List).cast<Map<String, dynamic>>();
      final espresso =
          lines.singleWhere((line) => line['productId'] == 'espresso');
      final rounded =
          lines.singleWhere((line) => line['productId'] == 'rounding');
      expect(espresso['unitPrice'], 0.1);
      expect(espresso['lineTotal'], 0.3);
      expect(rounded['unitPrice'], 0.11);
      expect(rounded['lineTotal'], 0.33);
      expect(bill['total'], 0.63);
    });

    test('checkout rejects carts exceeding transaction write capacity',
        () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);
      final ingredientIds = List.generate(250, (index) => 'ingredient-$index');
      for (final id in ingredientIds) {
        await seedItem(db, id, name: id, category: 'ingredient', quantity: 1);
      }
      final productIds = ['product-a', 'product-b', 'product-c'];
      for (var index = 0; index < productIds.length; index++) {
        final ids = ingredientIds.skip(index * 100).take(100).toList();
        await seedItem(db, productIds[index],
            name: productIds[index],
            category: 'finished',
            quantity: 0,
            sellingPrice: 1);
        await service.saveRecipe(
          productId: productIds[index],
          ingredients: [
            for (final id in ids) {'stockItemId': id, 'quantity': 1},
          ],
        );
      }

      await expectLater(
        service.checkout(
          checkoutId: 'oversized-checkout',
          cart: {for (final id in productIds) id: 1},
          orderType: 'dineIn',
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('too many distinct stock items'),
        )),
      );

      expect((await db.collection('bills').get()).docs, isEmpty);
      expect((await db.collection('stock_movements').get()).docs, isEmpty);
    });

    test('insufficient stock leaves bill, movements and quantities unchanged',
        () async {
      final db = FakeFirebaseFirestore();
      final service = CafeService(firestore: db);
      await seedItem(db, 'latte',
          name: 'Latte', category: 'finished', quantity: 0, sellingPrice: 4.5);
      await seedItem(db, 'beans',
          name: 'Beans', category: 'ingredient', quantity: 10);
      await service.saveRecipe(
        productId: 'latte',
        ingredients: [
          {'stockItemId': 'beans', 'quantity': 18}
        ],
      );

      await expectLater(
        service.checkout(
          checkoutId: 'checkout-fails',
          cart: {'latte': 1},
          orderType: 'dineIn',
        ),
        throwsA(isA<StateError>()),
      );

      expect(
          (await db.collection('stock_items').doc('beans').get())
              .data()?['quantity'],
          10);
      expect((await db.collection('bills').get()).docs, isEmpty);
      expect((await db.collection('stock_movements').get()).docs, isEmpty);
    });
  });

  group('CafeService tenant mode', () {
    test('stock reads are filtered to the selected café', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('stock_items').doc('a-beans').set({
        'cafeId': 'cafe-a',
        'name': 'Beans',
        'category': 'ingredient',
        'unit': 'g',
        'quantity': 10,
      });
      await db.collection('stock_items').doc('b-beans').set({
        'cafeId': 'cafe-b',
        'name': 'Other beans',
        'category': 'ingredient',
        'unit': 'g',
        'quantity': 90,
      });
      final service = CafeService(firestore: db, cafeId: 'cafe-a');

      expect((await service.watchStock().first).map((item) => item.id),
          ['a-beans']);
    });

    test(
        'tenant writes route through trusted callables and avoid client writes',
        () async {
      final db = FakeFirebaseFirestore();
      final calls = <String, Map<String, dynamic>>{};
      final callables = CafeFunctionsService(
        invoker: (name, data) async {
          calls[name] = data;
          return switch (name) {
            'createStockItem' => {'stockItemId': 'new-beans'},
            'checkout' => {'billId': 'bill-a'},
            _ => <String, dynamic>{},
          };
        },
      );
      final service = CafeService(
        firestore: db,
        cafeId: 'cafe-a',
        functionsService: callables,
      );

      final id = await service.addItem(item(quantity: 15));
      await service.addStock(
        itemId: 'beans-a',
        quantity: 5,
        reason: 'Delivery',
      );
      await service.saveRecipe(
        productId: 'latte-a',
        ingredients: const [
          {'stockItemId': 'beans-a', 'quantity': 18},
        ],
      );
      final billId = await service.checkout(
        checkoutId: 'bill-a',
        cart: const {'latte-a': 1},
        orderType: 'dineIn',
      );

      expect(id, 'new-beans');
      expect(billId, 'bill-a');
      expect(calls.values.every((data) => data['cafeId'] == 'cafe-a'), isTrue);
      expect(
          calls.keys,
          containsAll(
              ['createStockItem', 'addStock', 'saveRecipe', 'checkout']));
      expect((await db.collection('stock_items').get()).docs, isEmpty);
      expect((await db.collection('product_recipes').get()).docs, isEmpty);
      expect((await db.collection('bills').get()).docs, isEmpty);
      expect((await db.collection('stock_movements').get()).docs, isEmpty);
    });

    test('tenant recipe lookup hides recipes owned by another café', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('product_recipes').doc('latte').set({
        'cafeId': 'cafe-b',
        'productId': 'latte',
        'ingredients': [],
      });
      final service = CafeService(firestore: db, cafeId: 'cafe-a');

      expect(await service.loadRecipe('latte'), isNull);
    });

    test('loads only the selected café name for tenant receipts', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('cafes').doc('cafe-a').set({'name': 'Morning Brew'});
      await db.collection('cafes').doc('cafe-b').set({'name': 'Other Café'});
      final service = CafeService(firestore: db, cafeId: 'cafe-a');

      expect(await service.loadCafeName(), 'Morning Brew');
    });

    test('returns null when no tenant café name is available', () async {
      final service = CafeService(firestore: FakeFirebaseFirestore());

      expect(await service.loadCafeName(), isNull);
    });
  });
}
