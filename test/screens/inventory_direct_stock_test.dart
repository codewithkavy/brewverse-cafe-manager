import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/inventory_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _water = StockItem(
  id: 'water',
  name: 'Bottled water',
  category: 'finished',
  stockMode: 'direct',
  unit: 'piece',
  quantity: 2,
  minimumQuantity: 5,
  purchasePricePerUnit: 10,
  sellingPrice: 20,
);

void main() {
  testWidgets('new finished products default to recipe ingredients',
      (tester) async {
    final service = _InventoryService();
    await _pump(tester, service);
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Item name'), 'Fresh latte');
    await _chooseFinished(tester);

    expect(find.text('Recipe ingredients'), findsOneWidget);
    await tester.ensureVisible(find.text('Save item'));
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(service.added.single.category, 'finished');
    expect(service.added.single.stockMode, 'recipe');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Add item can explicitly select direct stock for packaged goods',
      (tester) async {
    final service = _InventoryService();
    await _pump(tester, service);
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Item name'), 'Packaged water');
    await _chooseFinished(tester);
    await tester.ensureVisible(find.byKey(const Key('itemStockMode')));
    await tester.tap(find.byKey(const Key('itemStockMode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direct stock').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_field('Opening quantity'));
    await tester.enterText(_field('Opening quantity'), '12');
    await tester.ensureVisible(find.text('Save item'));
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(service.added.single.stockMode, 'direct');
    expect(service.added.single.quantity, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'direct finished stock is low, restockable and has no recipe action',
      (tester) async {
    final service = _InventoryService();
    await _pump(tester, service);
    expect(find.text('Recipe product'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Low stock'));
    await tester.pumpAndSettle();
    expect(find.text('Bottled water'), findsOneWidget);

    await tester.tap(find.byTooltip('Item actions'));
    await tester.pumpAndSettle();
    expect(find.text('Manage recipe'), findsNothing);
    await tester.tap(find.text('Add stock'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Quantity ('), '6');
    await tester.tap(find.text('Save stock'));
    await tester.pumpAndSettle();

    expect(service.restocked, [
      {'itemId': 'water', 'quantity': 6.0},
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'low-stock filter follows ingredient threshold, depletion and replenishment',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('stock_items').doc('beans');
    await ref.set({
      ..._water.toMap(),
      'name': 'Threshold beans',
      'category': 'ingredient',
      'stockMode': 'recipe',
      'quantity': 6,
      'minimumQuantity': 5,
      'cafeId': 'cafe-a',
    });
    await _pump(tester, CafeService(firestore: db, cafeId: 'cafe-a'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Low stock'));
    await tester.pumpAndSettle();
    expect(find.text('Threshold beans'), findsNothing);

    await ref.update({'quantity': 5});
    await tester.pumpAndSettle();
    expect(find.text('Threshold beans'), findsOneWidget);
    await ref.update({'quantity': 0});
    await tester.pumpAndSettle();
    expect(find.text('Threshold beans'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    await ref.update({'quantity': 6});
    await tester.pumpAndSettle();
    expect(find.text('Threshold beans'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit item preserves direct mode without overwriting live stock',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('stock_items').doc('water');
    await ref.set({..._water.toMap(), 'cafeId': 'cafe-a'});
    await _pump(tester, CafeService(firestore: db, cafeId: 'cafe-a'));
    await tester.tap(find.byTooltip('Item actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();
    expect(find.text('Direct stock'), findsOneWidget);
    await tester.enterText(_field('Item name'), 'Cold bottled water');
    await ref.update({'quantity': 10});
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved = (await ref.get()).data()!;
    expect(saved['stockMode'], 'direct');
    expect(saved['name'], 'Cold bottled water');
    expect(saved['quantity'], 10);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, CafeService service) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: InventoryScreen(cafeId: 'cafe-a', cafeService: service),
  ));
  await tester.pumpAndSettle();
}

Future<void> _chooseFinished(WidgetTester tester) async {
  final stockType = find.byType(DropdownButtonFormField<String>).first;
  await tester.ensureVisible(stockType);
  await tester.tap(stockType);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Finished product').last);
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate((widget) =>
    widget is TextField &&
    (widget.decoration?.labelText?.startsWith(label) ?? false));

class _InventoryService implements CafeService {
  final added = <StockItem>[];
  final restocked = <Map<String, Object>>[];

  @override
  String get cafeId => 'cafe-a';

  @override
  Stream<List<StockItem>> watchStock() => Stream.value(const [_water]);

  @override
  Future<String> addItem(StockItem item) async {
    added.add(item);
    return 'new-item';
  }

  @override
  Future<void> addStock({
    required String itemId,
    required double quantity,
    required String reason,
  }) async {
    restocked.add({'itemId': itemId, 'quantity': quantity});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
