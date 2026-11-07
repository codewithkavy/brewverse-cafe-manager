import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/billing_screen.dart';
import 'package:brewverse_cafe_manager/screens/home_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/services/checkout_recovery_store.dart';
import 'package:brewverse_cafe_manager/theme/app_theme.dart';
import 'package:brewverse_cafe_manager/widgets/cafe_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedCafeService implements CafeService {
  @override
  Stream<List<StockItem>> watchStock() => Stream.value(_testProducts);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'lost checkout reply is retained and retries reuse original ID across screen recreation',
      (tester) async {
    _phoneSize(tester);
    final store = MemoryCheckoutRecoveryStore(),
        service = _AmbiguousCheckoutService();
    Future<void> mount() async {
      await tester.pumpWidget(MaterialApp(
          home: BillingScreen(
              cafeId: 'fixture-cafe',
              cafeService: service,
              stockStream: Stream.value(_testProducts),
              recoveryStore: store)));
      await tester.pumpAndSettle();
    }

    await mount();
    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Complete checkout'));
    await tester.tap(find.text('Complete checkout'));
    await tester.pumpAndSettle();
    expect(service.ids.length, 1);
    final id = service.ids.single;
    expect((await store.load()).pending!.id, id);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await mount();
    expect((await store.load()).pending!.id, id);
    final retry = find.textContaining('Retry same checkout');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(service.ids, [id, id]);
    expect((await store.load()).pending!.id, id);
  });
  for (final prefilled in [false, true]) {
    testWidgets(
        'checkout preserves ${prefilled ? "prefilled" : "entered"} loyalty phone without requiring lookup',
        (tester) async {
      _phoneSize(tester);
      final service = _CheckoutPhoneService();
      await tester.pumpWidget(MaterialApp(
        home: BillingScreen(
          cafeId: 'fixture-cafe',
          initialCustomerPhone: prefilled ? '+919876543210' : null,
          cafeService: service,
          stockStream: Stream.value(_testProducts),
          recoveryStore: MemoryCheckoutRecoveryStore(),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Vanilla Latte'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Review order'));
      await tester.pumpAndSettle();
      if (!prefilled) {
        final phone = _fieldWithLabel('Customer phone');
        await tester.ensureVisible(phone);
        await tester.enterText(phone, '+919876543210');
      }
      await tester.ensureVisible(find.text('Complete checkout'));
      await tester.tap(find.text('Complete checkout'));
      await tester.pumpAndSettle();
      expect(service.checkoutPhones, ['+919876543210']);
      expect(service.lookedUpPhones, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'search filters real menu items and selected item appears in cart',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final products = [
      const StockItem(
        id: 'latte',
        name: 'Vanilla Latte',
        category: 'finished',
        unit: 'cup',
        quantity: 0,
        minimumQuantity: 0,
        purchasePricePerUnit: 25,
        sellingPrice: 140,
      ),
      const StockItem(
        id: 'tea',
        name: 'Masala Tea',
        category: 'finished',
        unit: 'cup',
        quantity: 0,
        minimumQuantity: 0,
        purchasePricePerUnit: 8,
        sellingPrice: 35,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: BillingScreen(
        stockStream: Stream.value(products),
        cafeService: _UnusedCafeService(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Vanilla Latte'), findsOneWidget);
    expect(find.text('Masala Tea'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'vanilla');
    await tester.pumpAndSettle();
    expect(find.text('Vanilla Latte'), findsOneWidget);
    expect(find.text('Masala Tea'), findsNothing);

    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('In order · 1'), findsOneWidget);

    await tester.tap(find.byTooltip('View current bill'));
    await tester.pumpAndSettle();
    expect(find.text('Your order'), findsOneWidget);
    expect(find.text('₹140.00'), findsWidgets);
  });

  testWidgets('cart summary fits a narrow phone and shows the live total',
      (tester) async {
    tester.view.physicalSize = const Size(270, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const latte = StockItem(
      id: 'latte',
      name: 'Vanilla Latte',
      category: 'finished',
      unit: 'cup',
      quantity: 0,
      minimumQuantity: 0,
      purchasePricePerUnit: 25,
      sellingPrice: 140,
    );
    await tester.pumpWidget(MaterialApp(
      home: BillingScreen(
        stockStream: Stream.value(const [latte]),
        cafeService: _UnusedCafeService(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View current bill'));
    await tester.pumpAndSettle();

    expect(find.text('Your order'), findsOneWidget);
    expect(find.text('Vanilla Latte'), findsWidgets);
    expect(find.text('₹140.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear search clears both the input and product filter',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester);
    await tester.enterText(find.byType(TextField).first, 'vanilla');
    await tester.pumpAndSettle();
    expect(find.text('Masala Tea'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        isEmpty);
    expect(find.text('Vanilla Latte'), findsOneWidget);
    expect(find.text('Masala Tea'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('278px product grid uses three columns and real order filtering',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester);

    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3);
    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In order'));
    await tester.pumpAndSettle();
    expect(find.text('Vanilla Latte'), findsOneWidget);
    expect(find.text('Masala Tea'), findsNothing);

    await tester.tap(find.text('All products'));
    await tester.pumpAndSettle();
    expect(find.text('Masala Tea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart quantity controls update real line totals and empty state',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester);
    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add one Vanilla Latte'));
    await tester.pumpAndSettle();
    expect(find.text('₹280.00'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Remove one Vanilla Latte'));
    await tester.pumpAndSettle();
    expect(find.text('₹140.00'), findsWidgets);
    await tester.tap(find.byTooltip('Remove one Vanilla Latte'));
    await tester.pumpAndSettle();
    expect(find.text('Your order is empty'), findsOneWidget);
    expect(find.byTooltip('Remove one Vanilla Latte'), findsNothing);
    expect(_completeCheckout(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the full product card adds exactly one item with an accessible action',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester);
    await tester.tap(find.text('Vanilla Latte'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('In order · 1'), findsOneWidget);
    expect(find.byTooltip('In order · 2'), findsNothing);
    expect(find.bySemanticsLabel('Add Vanilla Latte, ₹140, 1 in order'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('278px product and order views fit at 1.6 text scale',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();
    expect(find.text('Your order'), findsOneWidget);
    expect(find.byTooltip('Continue shopping'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty menu keeps search and disabled checkout available',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester, products: const []);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Your menu starts here'), findsOneWidget);
    expect(find.textContaining('No finished products yet'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    await tester.tap(find.byTooltip('View current bill'));
    await tester.pumpAndSettle();
    expect(find.text('Your order is empty'), findsOneWidget);
    expect(_completeCheckout(tester).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'inventory stream loading stays bounded without invented products',
      (tester) async {
    _phoneSize(tester);
    final stream = StreamController<List<StockItem>>();
    addTearDown(stream.close);
    await tester.pumpWidget(MaterialApp(
      home: BillingScreen(
        stockStream: stream.stream,
        cafeService: _UnusedCafeService(),
      ),
    ));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Add Vanilla Latte'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory stream failure shows the actual error',
      (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      home: BillingScreen(
        stockStream: Stream<List<StockItem>>.error(
            StateError('fixture inventory unavailable')),
        cafeService: _UnusedCafeService(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load inventory'), findsOneWidget);
    expect(
        find.textContaining('fixture inventory unavailable'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('order sheet keeps its Emerald theme under production dark theme',
      (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: BillingScreen(
        stockStream: Stream.value(_testProducts),
        cafeService: _UnusedCafeService(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View current bill'));
    await tester.pumpAndSettle();
    final checkout = find.widgetWithText(ElevatedButton, 'Complete checkout');
    expect(Theme.of(tester.element(checkout)).brightness, Brightness.light);
    expect(Theme.of(tester.element(checkout)).colorScheme.primary,
        AppTheme.emerald);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone Billing Home destination opens dashboard',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BillingScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart Home destination dismisses the sheet and opens dashboard',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester);
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(
      find.descendant(of: sheet, matching: find.byType(CafeBottomNavigation)),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: sheet, matching: find.text('Home')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(BillingScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Takeaway remains selected after continuing shopping',
      (tester) async {
    _phoneSize(tester);
    await _pumpBilling(tester);
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Takeaway'));
    await tester.tap(find.text('Takeaway'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'takeaway'},
    );

    await tester.tap(find.byTooltip('Continue shopping'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>))
          .selected,
      {'takeaway'},
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tenant phone keyboard leaves a bounded usable cart at 278px',
      (tester) async {
    _phoneSize(tester);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(MaterialApp(
      home: BillingScreen(
        cafeId: 'fixture-cafe',
        stockStream: Stream.value(_testProducts),
        cafeService: _LoyaltyFixtureService(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();
    final phone = _fieldWithLabel('Customer phone');
    await tester.ensureVisible(phone);
    await tester.showKeyboard(phone);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.ensureVisible(phone);
    await tester.enterText(phone, '+919876543210');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Your order'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(CafeBottomNavigation),
      ),
      findsNothing,
    );
    final checkout = find.widgetWithText(ElevatedButton, 'Complete checkout');
    expect(tester.getBottomRight(checkout).dy, lessThanOrEqualTo(370));
    expect(_completeCheckout(tester).onPressed, isNotNull);
  });

  testWidgets('tenant customer controls live in cart and use existing lookup',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService();
    await tester.pumpWidget(MaterialApp(
      home: BillingScreen(
        cafeId: 'fixture-cafe',
        stockStream: Stream.value(_testProducts),
        cafeService: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(_fieldWithLabel('Customer phone'), findsNothing);
    await tester.tap(find.byTooltip('Add Vanilla Latte'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();
    expect(find.text('Dine-in'), findsOneWidget);
    expect(find.text('Takeaway'), findsOneWidget);
    final phone = _fieldWithLabel('Customer phone');
    await tester.ensureVisible(phone);
    await tester.enterText(phone, '+919876543210');
    await tester.ensureVisible(find.text('Find customer'));
    await tester.tap(find.text('Find customer'));
    await tester.pumpAndSettle();
    expect(service.lookedUpPhones, ['+919876543210']);
    expect(find.text('40 points available'), findsOneWidget);
    final points = _fieldWithLabel('Redeem points');
    await tester.ensureVisible(points);
    await tester.enterText(points, '10');
    await tester.pumpAndSettle();
    expect(find.text('₹130.00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(278, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpBilling(WidgetTester tester,
    {List<StockItem> products = _testProducts, double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: BillingScreen(
      stockStream: Stream.value(products),
      cafeService: _UnusedCafeService(),
    ),
  ));
  await tester.pumpAndSettle();
}

ElevatedButton _completeCheckout(WidgetTester tester) =>
    tester.widget(find.widgetWithText(ElevatedButton, 'Complete checkout'));

Finder _fieldWithLabel(String label) => find.byWidgetPredicate((widget) =>
    widget is TextField &&
    (widget.decoration?.labelText?.startsWith(label) ?? false));

const _testProducts = <StockItem>[
  StockItem(
    id: 'latte',
    name: 'Vanilla Latte',
    category: 'finished',
    unit: 'cup',
    quantity: 0,
    minimumQuantity: 0,
    purchasePricePerUnit: 25,
    sellingPrice: 140,
  ),
  StockItem(
    id: 'tea',
    name: 'Masala Tea',
    category: 'finished',
    unit: 'cup',
    quantity: 0,
    minimumQuantity: 0,
    purchasePricePerUnit: 8,
    sellingPrice: 35,
  ),
];

class _LoyaltyFixtureService extends _UnusedCafeService {
  final lookedUpPhones = <String>[];

  @override
  Future<Map<String, dynamic>> lookupLoyaltyCustomer({
    required String phoneNumber,
  }) async {
    lookedUpPhones.add(phoneNumber);
    return {'found': true, 'pointsBalance': 40};
  }

  @override
  Future<Map<String, dynamic>> getLoyaltySettings() async => {
        'enabled': true,
        'pointValueMinor': 100,
        'maxRedemptionPercent': 100,
      };
}

class _CheckoutPhoneService extends _LoyaltyFixtureService {
  final checkoutPhones = <String?>[];

  @override
  Future<String> checkout({
    required String checkoutId,
    required Map<String, int> cart,
    required String orderType,
    String? customerPhone,
    int redeemPoints = 0,
  }) async {
    checkoutPhones.add(customerPhone);
    // Stop before persistence/printing; this regression observes the request.
    throw StateError('fixture checkout stopped');
  }
}

class _AmbiguousCheckoutService extends _LoyaltyFixtureService {
  final ids = <String>[];
  @override
  Future<String> checkout(
      {required String checkoutId,
      required Map<String, int> cart,
      required String orderType,
      String? customerPhone,
      int redeemPoints = 0}) async {
    ids.add(checkoutId);
    throw FirebaseException(
        plugin: 'cloud_functions',
        code: 'unavailable',
        message: 'Connection lost');
  }
}
