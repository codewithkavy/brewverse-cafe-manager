import 'dart:async';

import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/theme/app_theme.dart';
import 'package:brewverse_cafe_manager/widgets/sales_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows saved totals and best sellers from the report',
      (tester) async {
    final service = CafeFunctionsService(
      invoker: (name, data) async {
        expect(name, 'getSalesSummary');
        expect(data['cafeId'], 'cafe-a');
        return {
          'grossRevenue': 42.5,
          'completedBillCount': 3,
          'itemsSold': 5,
          'bestSellingProducts': [
            {
              'productId': 'latte',
              'name': 'Caramel Latte',
              'quantitySold': 3,
              'revenue': 27.5,
            },
          ],
        };
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SalesSummaryCard(cafeId: 'cafe-a', functionsService: service),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('₹42.50'), findsOneWidget);
    expect(find.text('Total orders'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('₹14.17'), findsOneWidget);
    expect(find.text('Caramel Latte'), findsOneWidget);
    expect(find.text('3 sold'), findsOneWidget);
    expect(find.text('₹27.50'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SalesSummaryCard(
          cafeId: 'cafe-a',
          functionsService: service,
          metric: SalesReportMetric.items,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Items sold'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Last 7 days · Billed quantities'), findsOneWidget);
  });

  testWidgets('compact dashboard sales card uses saved report values',
      (tester) async {
    final service = CafeFunctionsService(
      invoker: (_, __) async => {
        'grossRevenue': 42.5,
        'completedBillCount': 3,
        'itemsSold': 5,
        'bestSellingProducts': <Map<String, dynamic>>[],
      },
    );

    await _pumpPhoneCard(tester, service);
    await tester.pumpAndSettle();

    expect(find.text("Today's sales"), findsOneWidget);
    expect(find.text('₹42.50'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('₹14'), findsOneWidget);
    expect(find.text('Daily trend'), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(tester.getSize(_compactSurface).width, 250);
    expect(tester.getSize(_compactSurface).height, lessThan(180));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact loading stays bounded at a 278px phone width',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final service = CafeFunctionsService(invoker: (_, __) => pending.future);

    await _pumpPhoneCard(tester, service);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Loading saved sales…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSize(_compactSurface), const Size(250, 138));
    expect(find.textContaining('₹'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard KPI cards share one saved report with the sales hero',
      (tester) async {
    var calls = 0;
    final service = CafeFunctionsService(invoker: (name, data) async {
      calls++;
      expect(name, 'getSalesSummary');
      expect(data['cafeId'], 'cafe-a');
      return _dashboardReport();
    });

    await _pumpPhoneCard(tester, service, showDashboardMetrics: true);
    await tester.pumpAndSettle();

    _expectDashboardLabels();
    expect(find.text('₹1000.00'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.text('₹50'), findsOneWidget);
    expect(find.text('—'), findsOneWidget,
        reason: 'The report does not provide a new-customer count');
    expect(find.text('Bills'), findsNothing);
    expect(find.text('Avg. bill'), findsNothing);
    expect(calls, 1, reason: 'The KPI grid must reuse the hero report');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard loading shows unavailable KPIs instead of zero totals',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    final service = CafeFunctionsService(invoker: (_, __) => pending.future);

    await _pumpPhoneCard(tester, service, showDashboardMetrics: true);
    await tester.pump(const Duration(milliseconds: 250));

    _expectDashboardLabels();
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('Loading saved sales…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard failed and malformed reports do not invent KPIs',
      (tester) async {
    final failed = CafeFunctionsService(invoker: (_, __) async {
      throw StateError('Offline');
    });
    await _pumpPhoneCard(tester, failed, showDashboardMetrics: true);
    await tester.pumpAndSettle();

    _expectDashboardLabels();
    expect(find.text('—'), findsNWidgets(4));
    expect(find.textContaining('₹'), findsNothing);
    expect(
        find.text('Sales summary is unavailable right now.'), findsOneWidget);

    final malformed = CafeFunctionsService(invoker: (_, __) async => {});
    await _pumpPhoneCard(tester, malformed, showDashboardMetrics: true);
    await tester.pumpAndSettle();

    _expectDashboardLabels();
    expect(find.text('—'), findsNWidgets(4));
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('Saved sales data could not be read.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard saved zero keeps real zero and no invented average',
      (tester) async {
    final service = CafeFunctionsService(
      invoker: (_, __) async =>
          _dashboardReport(revenue: 0, orders: 0, items: 0),
    );

    await _pumpPhoneCard(tester, service, showDashboardMetrics: true);
    await tester.pumpAndSettle();

    _expectDashboardLabels();
    expect(find.text('₹0.00'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2),
        reason: 'No customers count and no average without completed orders');
    expect(find.text('₹50'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard refresh updates hero and KPIs with one new request',
      (tester) async {
    var calls = 0;
    final pending = Completer<Map<String, dynamic>>();
    final service = CafeFunctionsService(invoker: (_, __) {
      calls++;
      return calls == 1 ? Future.value(_dashboardReport()) : pending.future;
    });

    await _pumpPhoneCard(tester, service, showDashboardMetrics: true);
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byTooltip('Refresh sales summary'));
    await tester.pump();

    expect(calls, 2);
    expect(find.text('₹1000.00'), findsNothing);
    expect(find.text('20'), findsNothing);
    expect(find.text('70'), findsNothing);
    expect(find.text('—'), findsNWidgets(4));

    pending.complete(_dashboardReport(revenue: 2400, orders: 30, items: 90));
    await tester.pumpAndSettle();
    expect(find.text('₹2400.00'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    expect(find.text('₹80'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard cafe switch hides the previous report while loading',
      (tester) async {
    final cafes = <String>[];
    final pending = Completer<Map<String, dynamic>>();
    final service = CafeFunctionsService(invoker: (_, data) {
      final cafe = data['cafeId'] as String;
      cafes.add(cafe);
      return cafe == 'cafe-a'
          ? Future.value(_dashboardReport())
          : pending.future;
    });
    await _pumpPhoneCard(tester, service, showDashboardMetrics: true);
    await tester.pumpAndSettle();

    await _pumpPhoneCard(tester, service,
        showDashboardMetrics: true, cafeId: 'cafe-b');
    await tester.pump();
    expect(cafes, ['cafe-a', 'cafe-b']);
    expect(find.text('₹1000.00'), findsNothing);
    expect(find.text('20'), findsNothing);
    expect(find.text('70'), findsNothing);
    expect(find.text('₹50'), findsNothing);
    expect(find.text('—'), findsNWidgets(4));

    pending.complete(_dashboardReport(revenue: 900, orders: 9, items: 18));
    await tester.pumpAndSettle();
    expect(find.text('₹900.00'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('₹100'), findsOneWidget);
    expect(cafes.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard service replacement hides the previous saved report',
      (tester) async {
    var oldCalls = 0;
    var newCalls = 0;
    final oldService = CafeFunctionsService(invoker: (_, __) async {
      oldCalls++;
      return _dashboardReport();
    });
    final pending = Completer<Map<String, dynamic>>();
    final newService = CafeFunctionsService(invoker: (_, __) {
      newCalls++;
      return pending.future;
    });
    await _pumpPhoneCard(tester, oldService, showDashboardMetrics: true);
    await tester.pumpAndSettle();

    await _pumpPhoneCard(tester, newService, showDashboardMetrics: true);
    await tester.pump();
    expect(oldCalls, 1);
    expect(newCalls, 1);
    expect(find.text('₹1000.00'), findsNothing);
    expect(find.text('20'), findsNothing);
    expect(find.text('70'), findsNothing);
    expect(find.text('—'), findsNWidgets(4));

    pending.complete(_dashboardReport(revenue: 600, orders: 12, items: 24));
    await tester.pumpAndSettle();
    expect(find.text('₹600.00'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('₹50'), findsOneWidget);
    expect(oldCalls, 1);
    expect(newCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard large saved totals fit narrow enlarged text',
      (tester) async {
    final service = CafeFunctionsService(
      invoker: (_, __) async => _dashboardReport(
          revenue: 1234567890.12, orders: 123456, items: 125000),
    );
    await _pumpPhoneCard(tester, service,
        showDashboardMetrics: true, scaler: const TextScaler.linear(1.6));
    await tester.pumpAndSettle();

    _expectDashboardLabels();
    expect(find.text('₹1234567890.12'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    expect(find.text('125000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact error wraps and retries the existing saved report call',
      (tester) async {
    var calls = 0;
    final service = CafeFunctionsService(invoker: (_, __) async {
      calls++;
      if (calls == 1) throw StateError('Offline');
      return {
        'grossRevenue': 42.5,
        'completedBillCount': 3,
        'itemsSold': 5,
      };
    });

    await _pumpPhoneCard(tester, service);
    await tester.pumpAndSettle();

    expect(
        find.text('Sales summary is unavailable right now.'), findsOneWidget);
    expect(tester.getSize(_compactSurface), const Size(250, 138));
    expect(find.textContaining('₹'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Retry sales summary'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('₹42.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact malformed data does not show invented totals',
      (tester) async {
    final service = CafeFunctionsService(invoker: (_, __) async => {});

    await _pumpPhoneCard(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Saved sales data could not be read.'), findsOneWidget);
    expect(tester.getSize(_compactSurface), const Size(250, 138));
    expect(find.textContaining('₹'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty-period message instead of invented sales',
      (tester) async {
    final service = CafeFunctionsService(
      invoker: (_, __) async => {
        'grossRevenue': 0,
        'completedBillCount': 0,
        'itemsSold': 0,
        'bestSellingProducts': <Map<String, dynamic>>[],
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SalesSummaryCard(cafeId: 'cafe-a', functionsService: service),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('₹0.00'), findsOneWidget);
    expect(find.text('No completed sales in this period.'), findsOneWidget);
  });

  testWidgets('30-day summary sends a backend-supported bounded date range',
      (tester) async {
    final service = CafeFunctionsService(
      invoker: (_, data) async {
        final startAt = DateTime.parse(data['startAt'] as String);
        final endAt = DateTime.parse(data['endAt'] as String);
        expect(endAt.difference(startAt), const Duration(days: 30));
        return {
          'grossRevenue': 0,
          'completedBillCount': 0,
          'itemsSold': 0,
          'bestSellingProducts': <Map<String, dynamic>>[],
        };
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SalesSummaryCard(
          cafeId: 'cafe-a',
          rangeDays: 30,
          functionsService: service,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Last 30 days · After refunds'), findsOneWidget);
  });

  testWidgets('Analytics amounts and long products fit narrow enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(278, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.emeraldLight,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(14),
          child: SalesReportView(report: {
            'grossRevenue': 1234567890.12,
            'completedBillCount': 123456,
            'itemsSold': 125000,
            'bestSellingProducts': [
              {
                'name': 'Very long café product name with extra ingredients',
                'quantitySold': 125000,
                'revenue': 1234567890.12,
              },
            ],
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('₹1234567890.12'), findsNWidgets(2));
    expect(find.text('Daily trend unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('View all expands only products from the saved report',
      (tester) async {
    final products = List.generate(
        6,
        (index) => {
              'name': 'Product ${index + 1}',
              'quantitySold': 6 - index,
              'revenue': 60 - index * 10,
            });
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.emeraldLight,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SalesReportView(report: {
            'grossRevenue': 210,
            'completedBillCount': 6,
            'itemsSold': 21,
            'bestSellingProducts': products,
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Product 4'), findsOneWidget);
    expect(find.text('Product 5'), findsNothing);
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    expect(find.text('Product 6'), findsOneWidget);
    await tester.ensureVisible(find.text('Show less'));
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();
    expect(find.text('Product 5'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final _compactSurface = find.byWidgetPredicate(
  (widget) =>
      widget is Container &&
      widget.decoration is BoxDecoration &&
      (widget.decoration! as BoxDecoration).gradient != null,
);

Future<void> _pumpPhoneCard(
  WidgetTester tester,
  CafeFunctionsService service, {
  bool showDashboardMetrics = false,
  String cafeId = 'cafe-a',
  TextScaler scaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = const Size(278, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.emeraldLight,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SalesSummaryCard(
          cafeId: cafeId,
          rangeDays: 1,
          compact: true,
          showDashboardMetrics: showDashboardMetrics,
          functionsService: service,
        ),
      ),
    ),
  ));
}

Map<String, dynamic> _dashboardReport({
  num revenue = 1000,
  int orders = 20,
  int items = 70,
}) =>
    {
      'grossRevenue': revenue,
      'completedBillCount': orders,
      'itemsSold': items,
      'bestSellingProducts': <Map<String, dynamic>>[],
    };

void _expectDashboardLabels() {
  for (final label in [
    'Orders',
    'New customers',
    'Items sold',
    'Avg. order value',
  ]) {
    expect(find.text(label), findsOneWidget);
  }
}
