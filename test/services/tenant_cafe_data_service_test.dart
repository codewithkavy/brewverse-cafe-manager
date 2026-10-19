import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/services/tenant_cafe_data_service.dart';

void main() {
  group('TenantCafeDataService', () {
    test('requires a non-empty single café ID', () {
      expect(
        () => TenantCafeDataService(cafeId: ''),
        throwsArgumentError,
      );
      expect(
        () => TenantCafeDataService(cafeId: 'cafe/a'),
        throwsArgumentError,
      );
    });

    test('stock and recipe streams return only the selected café records',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('stock_items').doc('a-beans').set({
        'cafeId': 'cafe-a',
        'name': 'Beans',
        'category': 'ingredient',
        'unit': 'g',
        'quantity': 500,
      });
      await firestore.collection('stock_items').doc('b-beans').set({
        'cafeId': 'cafe-b',
        'name': 'Beans from another café',
        'category': 'ingredient',
        'unit': 'g',
        'quantity': 900,
      });
      await firestore.collection('product_recipes').doc('a-latte').set({
        'cafeId': 'cafe-a',
        'productId': 'latte-a',
      });
      await firestore.collection('product_recipes').doc('b-latte').set({
        'cafeId': 'cafe-b',
        'productId': 'latte-b',
      });

      final service = TenantCafeDataService(
        cafeId: 'cafe-a',
        firestore: firestore,
      );
      final stock = await service.watchStock().first;
      final recipes = await service.watchRecipes().first;

      expect(stock.map((item) => item.id), ['a-beans']);
      expect(recipes.map((recipe) => recipe['id']), ['a-latte']);
    });

    test('movement and bill streams are scoped and bounded', () async {
      final firestore = FakeFirebaseFirestore();
      final timestamp = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
      for (final cafeId in ['cafe-a', 'cafe-b']) {
        await firestore.collection('stock_movements').doc(cafeId).set({
          'cafeId': cafeId,
          'createdAt': timestamp,
        });
        await firestore.collection('bills').doc(cafeId).set({
          'cafeId': cafeId,
          'createdAt': timestamp,
          'total': 12,
        });
      }
      await firestore.collection('stock_movements').doc('z-cafe-a').set({
        'cafeId': 'cafe-a',
        'createdAt': timestamp,
      });
      await firestore.collection('bills').doc('z-cafe-a').set({
        'cafeId': 'cafe-a',
        'createdAt': timestamp,
        'total': 12,
      });
      final service = TenantCafeDataService(
        cafeId: 'cafe-a',
        firestore: firestore,
      );

      expect(
        (await service.watchRecentMovements(limit: 1).first)
            .map((record) => record['id']),
        ['z-cafe-a'],
      );
      expect(
        (await service.watchRecentBills(limit: 1).first)
            .map((record) => record['id']),
        ['z-cafe-a'],
      );
      expect(
        () => service.watchRecentBills(limit: 501),
        throwsArgumentError,
      );
    });

    test('direct bill reads do not return a document belonging to another café',
        () async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('bills').doc('bill-a').set({
        'cafeId': 'cafe-a',
        'total': 10,
      });
      await firestore.collection('bills').doc('bill-b').set({
        'cafeId': 'cafe-b',
        'total': 20,
      });
      final service = TenantCafeDataService(
        cafeId: 'cafe-a',
        firestore: firestore,
      );

      expect((await service.getBill('bill-a'))?['total'], 10);
      expect(await service.getBill('bill-b'), isNull);
    });
  });
}
