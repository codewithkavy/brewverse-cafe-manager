import 'dart:async';
import 'dart:io' show Platform;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/screens/home_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/widgets/cafe_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Add stock quick action opens the existing item form',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = CafeService(firestore: FakeFirebaseFirestore());
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        cafeService: service,
        stockStream: Stream.value(const <StockItem>[]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Add stock'));
    await tester.tap(find.text('Add stock'));
    await tester.pumpAndSettle();

    expect(find.text('Add stock item'), findsOneWidget);
  });

  testWidgets('compact dashboard keeps its heading and navigation visible',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          stockStream: Stream.value(const <StockItem>[]),
          currentTime: DateTime(2026, 10, 18, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cafe team!'), findsOneWidget);
    expect(find.text('Great coffee. Greater days ahead.'), findsOneWidget);
    expect(find.byType(CafeBottomNavigation), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner actions remain usable on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(278, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var switched = false;
    final functions = CafeFunctionsService(
        invoker: (_, __) async => {
              'grossRevenue': 0,
              'completedBillCount': 0,
              'itemsSold': 0,
              'bestSellingProducts': <Map<String, dynamic>>[],
            });

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        cafeId: 'cafe-a',
        cafeRole: CafeRole.owner,
        stockStream: Stream.value(const <StockItem>[]),
        salesFunctionsService: functions,
        onSwitchCafe: () => switched = true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Cafe Owner!'), findsOneWidget);

    await tester.tap(find.byTooltip('Café actions'));
    await tester.pumpAndSettle();
    expect(find.text('Refund or void bill'), findsOneWidget);
    expect(find.text('Café team'), findsOneWidget);
    await tester.tap(find.text('Switch café'));
    await tester.pumpAndSettle();
    expect(switched, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reference phone layout shows complete welcome and compact actions',
      (tester) async {
    tester.view.physicalSize = const Size(278, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        cafeRole: CafeRole.owner,
        stockStream: Stream.value(const <StockItem>[]),
        currentTime: DateTime(2026, 10, 18, 9),
      ),
    ));
    await tester.pumpAndSettle();

    final appBar = tester.getRect(find.byType(AppBar));
    final greeting = tester.getRect(find.text('Good morning,'));
    final heading = tester.getRect(find.text('Cafe Owner!'));
    final subtitle = tester.getRect(
      find.text('Great coffee. Greater days ahead.'),
    );
    final navigation = tester.getRect(find.byType(CafeBottomNavigation));
    final list = find.byType(ListView).first;

    expect(greeting.top, greaterThanOrEqualTo(appBar.bottom));
    expect(heading.top, greaterThanOrEqualTo(greeting.bottom));
    expect(subtitle.top, greaterThanOrEqualTo(heading.bottom));
    expect(subtitle.left, greaterThanOrEqualTo(0));
    expect(subtitle.right, lessThanOrEqualTo(278));
    expect(subtitle.bottom, lessThan(navigation.top));
    expect(find.text('Today, 18 Oct 2026'), findsOneWidget);
    expect(tester.getSize(find.byType(CafeBottomNavigation)).height, 48);

    for (final label in ['New bill', 'Inventory', 'Add stock', 'Analytics']) {
      final action = find.descendant(of: list, matching: find.text(label));
      // Widget tests use Ahem, whose wider glyphs can wrap the welcome copy.
      // Initial viewport fit is checked separately in the rendered browser.
      await tester.scrollUntilVisible(
        action,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(action.hitTestable(), findsOneWidget, reason: label);
      final fixedNavigation = tester.getRect(find.byType(CafeBottomNavigation));
      expect(tester.getRect(action).bottom, lessThan(fixedNavigation.top),
          reason: '$label should remain usable above the fixed navigation');
      final tapTarget =
          find.ancestor(of: action, matching: find.byType(InkWell));
      expect(tester.getSize(tapTarget.first).height, 56, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference navigation stays fixed when dashboard scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(278, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        stockStream: Stream.value(const <StockItem>[]),
        currentTime: DateTime(2026, 10, 18, 9),
      ),
    ));
    await tester.pumpAndSettle();
    final navigation = find.byType(CafeBottomNavigation);
    final before = tester.getRect(navigation);

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getRect(navigation), before);
    for (final label in ['Home', 'Inventory', 'Billing', 'Loyalty', 'More']) {
      expect(
        find
            .descendant(of: navigation, matching: find.text(label))
            .hitTestable(),
        findsOneWidget,
        reason: label,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone metrics stay compact and text can scale without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget dashboard(TextScaler scaler) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child!,
          ),
          home: HomeScreen(stockStream: Stream.value(const <StockItem>[])),
        );

    await tester.pumpWidget(dashboard(TextScaler.noScaling));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Total items'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final metric = find.ancestor(
      of: find.text('Total items'),
      matching: find.byType(AnimatedContainer),
    );
    expect(tester.getSize(metric.first).height, 72);
    expect(tester.takeException(), isNull);

    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(278, 650);
    await tester.pumpWidget(dashboard(const TextScaler.linear(1.6)));
    await tester.pumpAndSettle();
    expect(find.text('Great coffee. Greater days ahead.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard without a cafe shows unavailable sales KPIs',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        stockStream: Stream.value(const <StockItem>[]),
        currentTime: DateTime(2026, 10, 18, 9),
      ),
    ));
    await tester.pumpAndSettle();

    for (final name in ['orders', 'customers', 'items', 'average']) {
      expect(
        tester.widget<Text>(find.byKey(ValueKey('dashboard-$name-value'))).data,
        '—',
        reason: '$name must not be invented without a connected report',
      );
    }
    for (final label in [
      'Orders',
      'New customers',
      'Items sold',
      'Avg. order value',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('₹'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('relocated stock metrics still reflect the existing stock stream',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final stock = StreamController<List<StockItem>>();
    addTearDown(stock.close);
    const milk = StockItem(
      id: 'milk',
      name: 'Milk',
      category: 'ingredient',
      unit: 'L',
      quantity: 2,
      minimumQuantity: 3,
      purchasePricePerUnit: 50,
      sellingPrice: 0,
    );
    const beans = StockItem(
      id: 'beans',
      name: 'Coffee beans',
      category: 'ingredient',
      unit: 'kg',
      quantity: 10,
      minimumQuantity: 2,
      purchasePricePerUnit: 500,
      sellingPrice: 0,
    );
    const latte = StockItem(
      id: 'latte',
      name: 'Latte',
      category: 'finished',
      unit: 'cup',
      quantity: 8,
      minimumQuantity: 0,
      purchasePricePerUnit: 30,
      sellingPrice: 80,
    );

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        stockStream: stock.stream,
        currentTime: DateTime(2026, 10, 18, 9),
      ),
    ));
    stock.add(const [milk, beans, latte]);
    await tester.pumpAndSettle();

    Future<void> expectStockMetric(String label, String value) async {
      final labelFinder = find.text(label);
      await tester.scrollUntilVisible(
        labelFinder,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final card = find.ancestor(
        of: labelFinder,
        matching: find.byType(AnimatedContainer),
      );
      expect(find.descendant(of: card.first, matching: find.text(value)),
          findsOneWidget,
          reason: label);
    }

    await expectStockMetric('Total items', '3');
    await expectStockMetric('Low stock', '1');
    await expectStockMetric('Ingredients', '2');
    await expectStockMetric('Finished goods', '1');

    stock.add(const [beans, latte]);
    await tester.pumpAndSettle();
    await expectStockMetric('Total items', '2');
    await expectStockMetric('Low stock', '0');
    await expectStockMetric('Ingredients', '1');
    await expectStockMetric('Finished goods', '1');
    expect(find.textContaining('₹'), findsNothing,
        reason: 'Inventory counts must not become invented sales totals');
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the Emerald dashboard empty state without sales figures',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          stockStream: Stream.value(const <StockItem>[]),
          currentTime: DateTime(2026, 10, 18, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cafe team!'), findsOneWidget);
    expect(find.text('Sales report'), findsOneWidget);
    expect(find.text('MIDNIGHT ESPRESSO'), findsNothing);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('New customers'), findsOneWidget);
    expect(find.text('Items sold'), findsOneWidget);
    expect(find.text('Avg. order value'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4));
    expect(find.textContaining('₹'), findsNothing);
    await tester.runAsync(() => precacheImage(
          const AssetImage('assets/images/dashboard-coffee.png'),
          tester.element(find.byType(HomeScreen)),
        ));
    await tester.pumpAndSettle();
    // This reference image was approved on Windows. Linux CI rasterizes
    // the same scene with slightly different pixels (2.34% in CI).
    // Continue running layout and text assertions everywhere; compare the
    // pixel-perfect Windows reference only on its originating platform.
    if (Platform.isWindows) {
      await expectLater(
        find.byType(HomeScreen),
        matchesGoldenFile('goldens/emerald_dashboard_empty.png'),
      );
    }

    await tester.drag(find.byType(ListView).first, const Offset(0, -1400));
    await tester.pumpAndSettle();
    expect(find.text('Inventory is ready for your first item'), findsOneWidget);
  });
}
