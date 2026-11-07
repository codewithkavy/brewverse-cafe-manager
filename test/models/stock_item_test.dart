import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StockItem item({String category = 'finished', String stockMode = 'recipe'}) =>
      StockItem(
        id: 'product',
        name: 'Bottled water',
        category: category,
        stockMode: stockMode,
        unit: 'piece',
        quantity: 2,
        minimumQuantity: 5,
        purchasePricePerUnit: 10,
        sellingPrice: 20,
      );

  test('existing finished products remain recipe based without stockMode',
      () async {
    final db = FakeFirebaseFirestore();
    final data = item().toMap()..remove('stockMode');
    final ref = db.collection('stock_items').doc('product');
    await ref.set(data);

    final loaded = StockItem.fromDoc(await ref.get());
    expect(loaded.stockMode, 'recipe');
    expect(loaded.isRecipeProduct, isTrue);
    expect(loaded.isDirectStock, isFalse);
    expect(loaded.isLow, isFalse);
  });

  test('explicit direct products persist their mode and count as low stock',
      () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('stock_items').doc('product');
    await ref.set(item(stockMode: 'direct').toMap());

    final loaded = StockItem.fromDoc(await ref.get());
    expect(loaded.stockMode, 'direct');
    expect(loaded.isDirectStock, isTrue);
    expect(loaded.isRecipeProduct, isFalse);
    expect(loaded.isLow, isTrue);
    expect(loaded.toMap()['stockMode'], 'direct');
  });

  test('ingredients remain quantity tracked and unknown products fail closed',
      () {
    expect(item(category: 'ingredient').isLow, isTrue);
    expect(item(stockMode: 'unknown').isRecipeProduct, isTrue);
    expect(item(stockMode: 'unknown').isDirectStock, isFalse);
  });
}
