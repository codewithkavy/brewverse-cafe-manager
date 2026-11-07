import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:brewverse_cafe_manager/screens/inventory_screen.dart';
import 'package:brewverse_cafe_manager/screens/home_screen.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/theme/app_theme.dart';

void main() {
  Future<Widget> inventoryForRole({required bool canManageInventory}) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('stock_items').doc('beans').set({
      'cafeId': 'cafe-a',
      'name': 'Coffee beans',
      'category': 'ingredient',
      'unit': 'g',
      'quantity': 500,
      'minimumQuantity': 100,
      'purchasePricePerUnit': 1,
      'sellingPrice': 2,
    });
    return MaterialApp(
      home: InventoryScreen(
        cafeId: 'cafe-a',
        canManageInventory: canManageInventory,
        cafeService: CafeService(firestore: firestore, cafeId: 'cafe-a'),
      ),
    );
  }

  testWidgets('inventory search and status filters use the loaded stock',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final firestore = FakeFirebaseFirestore();
    await firestore.collection('stock_items').doc('beans').set({
      'cafeId': 'cafe-a',
      'name': 'Coffee beans',
      'category': 'ingredient',
      'unit': 'g',
      'quantity': 2,
      'minimumQuantity': 10,
      'purchasePricePerUnit': 1,
      'sellingPrice': 2,
    });
    await firestore.collection('stock_items').doc('latte').set({
      'cafeId': 'cafe-a',
      'name': 'Vanilla Latte',
      'category': 'finished',
      'unit': 'cup',
      'quantity': 0,
      'minimumQuantity': 0,
      'purchasePricePerUnit': 30,
      'sellingPrice': 120,
    });

    await tester.pumpWidget(MaterialApp(
      home: InventoryScreen(
        cafeId: 'cafe-a',
        cafeService: CafeService(firestore: firestore, cafeId: 'cafe-a'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.text('Vanilla Latte'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'vanilla');
    await tester.pumpAndSettle();
    expect(find.text('Vanilla Latte'), findsOneWidget);
    expect(find.text('Coffee beans'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Low stock'));
    await tester.pumpAndSettle();
    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.text('Vanilla Latte'), findsNothing);
  });

  testWidgets('staff can view tenant stock without mutation controls',
      (tester) async {
    await tester.pumpWidget(
      await inventoryForRole(canManageInventory: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Edit item'), findsNothing);
    expect(find.byTooltip('Manage recipe'), findsNothing);
    expect(find.byTooltip('Add stock'), findsNothing);
    expect(find.byTooltip('Add item'), findsNothing);
    expect(find.byTooltip('Item actions'), findsNothing);
  });

  testWidgets('inventory managers retain the stock mutation controls',
      (tester) async {
    tester.view.physicalSize = const Size(278, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      await inventoryForRole(canManageInventory: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Item actions'), findsOneWidget);
    expect(find.byTooltip('Add item'), findsOneWidget);

    await tester.tap(find.byTooltip('Item actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsOneWidget);
    expect(find.text('Add stock'), findsOneWidget);
    expect(find.text('Manage recipe'), findsNothing);
    await tester.tap(find.text('Add stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Add stock item'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _openItemAction(tester, 'Edit item');
    expect(find.text('Choose product photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stock movement history'));
    await tester.pumpAndSettle();
    expect(find.text('Stock movement history'), findsOneWidget);
    expect(find.text('No stock movements recorded yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager cannot save an item name beyond the rule limit',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('stock_items').doc('beans').set({
      'cafeId': 'cafe-a',
      'name': 'Coffee beans',
      'category': 'ingredient',
      'unit': 'g',
      'quantity': 500,
      'minimumQuantity': 100,
      'purchasePricePerUnit': 1,
      'sellingPrice': 2,
    });
    await tester.pumpWidget(MaterialApp(
      home: InventoryScreen(
        cafeId: 'cafe-a',
        canManageInventory: true,
        cafeService: CafeService(firestore: firestore, cafeId: 'cafe-a'),
      ),
    ));
    await tester.pumpAndSettle();

    await _openItemAction(tester, 'Edit item');
    await tester.enterText(
      find.byType(TextFormField).first,
      List.filled(121, 'x').join(),
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(
      find.text('Item name must be 120 characters or fewer'),
      findsOneWidget,
    );
    final savedItem =
        await firestore.collection('stock_items').doc('beans').get();
    expect(savedItem.data()?['name'], 'Coffee beans');
  });

  testWidgets('278px compact rows reserve readable space for stock names',
      (tester) async {
    _phoneSize(tester);
    await _pumpInventory(tester);

    final title = tester.getRect(find.text('Coffee beans'));
    final actions = tester.getRect(find.byTooltip('Item actions').first);
    expect(title.width, greaterThanOrEqualTo(65));
    expect(title.right, lessThanOrEqualTo(actions.left));
    expect(title.left, greaterThanOrEqualTo(0));
    expect(actions.right, lessThanOrEqualTo(278));
    expect(tester.takeException(), isNull);
  });

  testWidgets('278px inventory loading remains bounded without stock fixtures',
      (tester) async {
    _phoneSize(tester);
    final stock = StreamController<List<StockItem>>();
    addTearDown(stock.close);
    await tester.pumpWidget(MaterialApp(
      home: InventoryScreen(
        cafeId: 'cafe-a',
        cafeService: _InventoryStreamService(stock.stream),
      ),
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Coffee beans'), findsNothing);
    expect(find.text('No stock items yet'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('278px inventory error reports unavailable stock safely',
      (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      home: InventoryScreen(
        cafeId: 'cafe-a',
        cafeService: _InventoryStreamService(
          Stream<List<StockItem>>.error(StateError('fixture stream failure')),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Inventory unavailable'), findsOneWidget);
    expect(
      find.text('Could not load inventory. Check your connection.'),
      findsOneWidget,
    );
    expect(find.text('Coffee beans'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quantity and purchase fields pair normally and stack at 1.6',
      (tester) async {
    _phoneSize(tester);
    final textScale = ValueNotifier<double>(1);
    addTearDown(textScale.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ValueListenableBuilder<double>(
        valueListenable: textScale,
        builder: (context, value, _) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(value)),
          child: child!,
        ),
      ),
      home: InventoryScreen(
        cafeId: 'cafe-a',
        cafeService: _InventoryFixtureService(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    final quantity = _field('Opening quantity');
    final purchase = _field('Purchase (₹)');
    await tester.ensureVisible(quantity);
    final quantityNormal = tester.getRect(quantity);
    final purchaseNormal = tester.getRect(purchase);
    expect(quantityNormal.top, closeTo(purchaseNormal.top, 1));
    expect(quantityNormal.right, lessThan(purchaseNormal.left));
    expect(tester.takeException(), isNull);

    textScale.value = 1.6;
    await tester.pumpAndSettle();
    await tester.ensureVisible(quantity);
    final quantityLarge = tester.getRect(quantity);
    final purchaseLarge = tester.getRect(purchase);
    expect(quantityLarge.left, closeTo(purchaseLarge.left, 1));
    expect(purchaseLarge.top, greaterThanOrEqualTo(quantityLarge.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory and item form fit 278px at 1.6 text scale',
      (tester) async {
    _phoneSize(tester);
    await _pumpInventory(tester, textScale: 1.6);
    expect(find.text('Coffee beans'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    expect(find.text('Add stock item'), findsOneWidget);
    expect(find.byKey(const Key('addItemPhotoTile')), findsOneWidget);
    expect(find.byKey(const Key('addItemChoosePhoto')), findsOneWidget);
    expect(find.text('Choose product photo (optional)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Inventory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('status distinguishes low ingredients from recipe products',
      (tester) async {
    _phoneSize(tester);
    await _pumpInventory(tester);
    expect(find.text('Low stock'), findsWidgets);
    expect(find.text('Recipe product'), findsOneWidget);
    expect(find.text('In stock'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(-260, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Low stock'));
    await tester.pumpAndSettle();
    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.text('Vanilla Latte'), findsNothing);
    expect(find.text('Milk'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear search resets both visible text and the stock filter',
      (tester) async {
    _phoneSize(tester);
    await _pumpInventory(tester);
    await tester.enterText(find.byType(TextField).first, 'vanilla');
    await tester.pumpAndSettle();
    expect(find.text('Coffee beans'), findsNothing);
    expect(find.text('Vanilla Latte'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      isEmpty,
    );
    expect(find.text('Coffee beans'), findsOneWidget);
    expect(find.text('Vanilla Latte'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and category updates reuse one stock subscription',
      (tester) async {
    _phoneSize(tester);
    final service = _InventoryFixtureService();
    await _pumpInventory(tester, service: service);
    expect(service.watchStockCalls, 1);
    expect(service.stockSubscriptions, 1);

    await tester.enterText(find.byType(TextField).first, 'coffee');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ingredients'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();

    expect(service.watchStockCalls, 1);
    expect(service.stockSubscriptions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finished product actions include the existing recipe route',
      (tester) async {
    _phoneSize(tester);
    await _pumpInventory(tester,
        service: _InventoryFixtureService(items: const [_latte]));
    await tester.tap(find.byTooltip('Item actions'));
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsOneWidget);
    expect(find.text('Manage recipe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all inventory forms use Emerald theme under a dark parent',
      (tester) async {
    _phoneSize(tester);
    await _pumpInventory(tester,
        service: _InventoryFixtureService(items: const [_beans]),
        theme: AppTheme.dark);

    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    _expectEmeraldForm(tester, 'Save item');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _openItemAction(tester, 'Edit item');
    _expectEmeraldForm(tester, 'Save changes');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await _openItemAction(tester, 'Add stock');
    _expectEmeraldForm(tester, 'Save stock');
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone inventory Home opens the existing dashboard',
      (tester) async {
    _phoneSize(tester);
    await _pumpInventory(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(InventoryScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone form remains usable with a 280px keyboard inset',
      (tester) async {
    _phoneSize(tester);
    addTearDown(tester.view.resetViewInsets);
    await _pumpInventory(tester);
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    final name = _field('Item name');
    await tester.ensureVisible(name);
    await tester.showKeyboard(name);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Keyboard fixture item');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Add stock item'), findsOneWidget);
    await tester.ensureVisible(find.text('Save item'));
    expect(tester.getBottomRight(find.text('Save item')).dy,
        lessThanOrEqualTo(370));
  });

  testWidgets('opening quantity is passed unchanged to the existing item save',
      (tester) async {
    _phoneSize(tester);
    final service = _InventoryFixtureService();
    await _pumpInventory(tester, service: service);
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Item name'), 'Opening stock fixture');
    await tester.ensureVisible(_field('Opening quantity'));
    await tester.enterText(_field('Opening quantity'), '12.5');
    await tester.ensureVisible(find.text('Save item'));
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(service.addedItems, hasLength(1));
    expect(service.addedItems.single.name, 'Opening stock fixture');
    expect(service.addedItems.single.quantity, 12.5);
    expect(find.text('Add stock item'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit form cannot overwrite stock changed while it was open',
      (tester) async {
    _phoneSize(tester);
    final firestore = FakeFirebaseFirestore();
    final itemRef = firestore.collection('stock_items').doc('beans');
    await itemRef.set({..._beans.toMap(), 'cafeId': 'cafe-a'});
    await tester.pumpWidget(MaterialApp(
      home: InventoryScreen(
        cafeId: 'cafe-a',
        cafeService: CafeService(firestore: firestore, cafeId: 'cafe-a'),
      ),
    ));
    await tester.pumpAndSettle();
    await _openItemAction(tester, 'Edit item');
    final quantity = _field('Current quantity');
    expect(tester.widget<TextField>(quantity).readOnly, isTrue);
    expect(tester.widget<TextField>(quantity).controller?.text, '2.0 g');
    await tester.enterText(_field('Item name'), 'Coffee beans edited');
    await itemRef.update({'quantity': 750});
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    final saved = (await itemRef.get()).data();
    expect(saved?['name'], 'Coffee beans edited');
    expect(saved?['quantity'], 750);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid numeric input never calls item save', (tester) async {
    _phoneSize(tester);
    final service = _InventoryFixtureService();
    await _pumpInventory(tester, service: service);
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Item name'), 'Invalid number fixture');
    await tester.ensureVisible(_field('Opening quantity'));
    await tester.enterText(_field('Opening quantity'), 'not-a-number');
    await tester.ensureVisible(find.text('Save item'));
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid opening quantity'), findsOneWidget);
    expect(service.addedItems, isEmpty);
    expect(find.text('Add stock item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure stays visible and does not imply a saved item',
      (tester) async {
    _phoneSize(tester);
    final service = _InventoryFixtureService(failSaves: true);
    await _pumpInventory(tester, service: service);
    await tester.tap(find.byTooltip('Add item'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Item name'), 'Failed save fixture');
    await tester.ensureVisible(find.text('Save item'));
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save item'), findsOneWidget);
    expect(find.textContaining('fixture save rejected'), findsOneWidget);
    expect(find.text('Add stock item'), findsOneWidget);
    expect(service.addedItems, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'add-stock form validates quantity and preserves the save request',
      (tester) async {
    _phoneSize(tester);
    final service = _InventoryFixtureService(items: const [_beans]);
    await _pumpInventory(tester, service: service);
    await _openItemAction(tester, 'Add stock');
    await tester.enterText(_field('Quantity ('), '0');
    await tester.tap(find.text('Save stock'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a quantity greater than zero'), findsOneWidget);
    expect(service.stockAdditions, isEmpty);

    await tester.enterText(_field('Quantity ('), '25.5');
    await tester.enterText(_field('Reason'), 'Fixture delivery');
    await tester.tap(find.text('Save stock'));
    await tester.pumpAndSettle();
    expect(service.stockAdditions, [
      {'itemId': 'beans', 'quantity': 25.5, 'reason': 'Fixture delivery'},
    ]);
    expect(find.text('Save stock'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(278, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpInventory(WidgetTester tester,
    {_InventoryFixtureService? service,
    double textScale = 1,
    ThemeData? theme}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: InventoryScreen(
      cafeId: 'cafe-a',
      cafeService: service ?? _InventoryFixtureService(),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openItemAction(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Item actions').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate((widget) =>
    widget is TextField &&
    (widget.decoration?.labelText?.startsWith(label) ?? false));

void _expectEmeraldForm(WidgetTester tester, String saveLabel) {
  final theme = Theme.of(tester.element(find.text(saveLabel)));
  expect(theme.brightness, Brightness.light);
  expect(theme.colorScheme.primary, AppTheme.emerald);
}

const _beans = StockItem(
  id: 'beans',
  name: 'Coffee beans',
  category: 'ingredient',
  unit: 'g',
  quantity: 2,
  minimumQuantity: 10,
  purchasePricePerUnit: 1,
  sellingPrice: 2,
);

const _latte = StockItem(
  id: 'latte',
  name: 'Vanilla Latte',
  category: 'finished',
  unit: 'cup',
  quantity: 0,
  minimumQuantity: 0,
  purchasePricePerUnit: 30,
  sellingPrice: 120,
);

const _milk = StockItem(
  id: 'milk',
  name: 'Milk',
  category: 'ingredient',
  unit: 'L',
  quantity: 20,
  minimumQuantity: 5,
  purchasePricePerUnit: 50,
  sellingPrice: 0,
);

class _InventoryFixtureService implements CafeService {
  _InventoryFixtureService({
    this.items = const [_beans, _latte, _milk],
    this.failSaves = false,
  });

  final List<StockItem> items;
  final bool failSaves;
  int watchStockCalls = 0;
  int stockSubscriptions = 0;
  final addedItems = <StockItem>[];
  final stockAdditions = <Map<String, Object>>[];

  @override
  String? get cafeId => 'cafe-a';

  @override
  Stream<List<StockItem>> watchStock() {
    watchStockCalls++;
    return Stream<List<StockItem>>.multi((controller) {
      stockSubscriptions++;
      controller.add(items);
      controller.close();
    });
  }

  @override
  Future<String> addItem(StockItem item) async {
    if (failSaves) throw StateError('fixture save rejected');
    addedItems.add(item);
    return 'fixture-item';
  }

  @override
  Future<void> addStock({
    required String itemId,
    required double quantity,
    required String reason,
  }) async {
    if (failSaves) throw StateError('fixture stock addition rejected');
    stockAdditions.add({
      'itemId': itemId,
      'quantity': quantity,
      'reason': reason,
    });
  }

  @override
  Stream<List<Map<String, dynamic>>> watchRecentMovements({int limit = 100}) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _InventoryStreamService extends _InventoryFixtureService {
  _InventoryStreamService(this.stockStream);

  final Stream<List<StockItem>> stockStream;

  @override
  Stream<List<StockItem>> watchStock() => stockStream;
}
