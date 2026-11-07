import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new tenant product has no recipe and a saved recipe can be reopened',
      () async {
    final db = FakeFirebaseFirestore();
    final service = CafeService(firestore: db, cafeId: 'a');
    expect(await service.loadRecipe('burger'), isNull);
    final recipe = {
      'cafeId': 'a',
      'productId': 'burger',
      'ingredients': [
        {'stockItemId': 'bun', 'quantity': 2},
      ]
    };
    await db.collection('product_recipes').doc('burger').set(recipe);
    expect(await service.loadRecipe('burger'), recipe);
    expect(await CafeService(firestore: db, cafeId: 'b').loadRecipe('burger'),
        isNull);
    expect(await CafeService(firestore: db).loadRecipe('burger'), recipe);
  });
}
