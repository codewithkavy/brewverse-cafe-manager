import 'package:brewverse_cafe_manager/theme/app_theme.dart';
import 'package:brewverse_cafe_manager/widgets/dashboard_sales_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('missing report shows unavailable values without fake totals',
      (tester) async {
    await _pump(tester);
    expect(find.text('—'), findsNWidgets(4));
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(
        find.byTooltip(
            'New customer totals are unavailable in the current sales report.'),
        findsOneWidget);
  });

  testWidgets('loading does not present a stale report as current totals',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pump(tester, report: _report, loading: true);
      expect(find.text('—'), findsNWidgets(4));
      expect(find.text('28'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Loading saved sales metrics')),
          findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('actual saved totals and average retain paise', (tester) async {
    await _pump(tester, report: _report);
    expect(find.text('28'), findsOneWidget);
    expect(find.text('124'), findsOneWidget);
    expect(find.text('₹149.25'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('whole-rupee average is compact without dropping paise',
      (tester) async {
    await _pump(tester, report: {..._report, 'grossRevenue': 4172});
    expect(find.text('₹149'), findsOneWidget);
    await _pump(tester,
        report: {..._report, 'grossRevenue': 42.5, 'completedBillCount': 3});
    expect(find.text('₹14.17'), findsOneWidget);
  });

  testWidgets('confirmed empty report preserves actual zero counts',
      (tester) async {
    await _pump(tester, report: {
      'grossRevenue': 0,
      'completedBillCount': 0,
      'itemsSold': 0,
      'bestSellingProducts': <Map<String, dynamic>>[],
    });
    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.textContaining('₹'), findsNothing);
  });

  for (final invalid in [null, '28', 28.5, -1, double.infinity, double.nan]) {
    testWidgets(
        'invalid order count $invalid does not create a total or average',
        (tester) async {
      await _pump(tester, report: {..._report, 'completedBillCount': invalid});
      expect(_value(tester, 'orders'), '—');
      expect(_value(tester, 'average'), '—');
      expect(_value(tester, 'items'), '124');
    });
  }

  for (final invalid in [null, '124', 124.5, -1, double.infinity, double.nan]) {
    testWidgets('invalid item count $invalid does not create a total',
        (tester) async {
      await _pump(tester, report: {..._report, 'itemsSold': invalid});
      expect(_value(tester, 'items'), '—');
      expect(_value(tester, 'orders'), '28');
      expect(_value(tester, 'average'), '₹149.25');
    });
  }

  for (final invalid in [
    null,
    '4179',
    -1,
    double.infinity,
    double.negativeInfinity,
    double.nan
  ]) {
    testWidgets('invalid revenue $invalid does not create an average',
        (tester) async {
      await _pump(tester, report: {..._report, 'grossRevenue': invalid});
      expect(_value(tester, 'average'), '—');
      expect(_value(tester, 'orders'), '28');
      expect(_value(tester, 'items'), '124');
    });
  }

  testWidgets('new customers cannot be invented by an unrelated report field',
      (tester) async {
    await _pump(tester, report: {..._report, 'newCustomers': 5});
    expect(_value(tester, 'customers'), '—');
    expect(find.text('5'), findsNothing);
  });

  testWidgets('278px reference viewport uses compact two-column cards',
      (tester) async {
    await _pump(tester, report: _report, width: 278);
    final orders = find.byKey(const ValueKey('dashboard-orders-card'));
    final customers = find.byKey(const ValueKey('dashboard-customers-card'));
    final items = find.byKey(const ValueKey('dashboard-items-card'));
    expect(tester.getSize(orders), const Size(121, 72));
    expect(tester.getSize(customers).width, 121);
    // Ahem can wrap this label onto more lines than the actual UI font.
    // The card must grow rather than clip its content.
    expect(tester.getSize(customers).height, greaterThanOrEqualTo(72));
    expect(tester.getTopLeft(orders).dy, tester.getTopLeft(customers).dy);
    expect(
        tester.getTopLeft(items).dy, greaterThan(tester.getTopLeft(orders).dy));
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.6, 2.5]) {
    testWidgets('${scale}x text grows cards and keeps every label visible',
        (tester) async {
      await _pump(tester, report: _report, width: 278, textScale: scale);
      expect(
          tester
              .getSize(find.byKey(const ValueKey('dashboard-orders-card')))
              .height,
          greaterThan(72));
      for (final label in [
        'Orders',
        'New customers',
        'Items sold',
        'Avg. order value'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop presents four metrics on one row', (tester) async {
    await _pump(tester, report: _report, width: 1024);
    final orders = find.byKey(const ValueKey('dashboard-orders-card'));
    final average = find.byKey(const ValueKey('dashboard-average-card'));
    expect(tester.getTopLeft(orders).dy, tester.getTopLeft(average).dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large finite averages fit without ellipsis or loss of paise',
      (tester) async {
    await _pump(tester,
        report: {
          ..._report,
          'grossRevenue': 999999999999.75,
          'completedBillCount': 1
        },
        width: 278);
    expect(find.text('₹999999999999.75'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _pump(tester,
        report: {..._report, 'grossRevenue': 1e25, 'completedBillCount': 1},
        width: 278);
    expect(find.text('₹10000000000000000000000000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _report = <String, dynamic>{
  'grossRevenue': 4179,
  'completedBillCount': 28,
  'itemsSold': 124,
  'bestSellingProducts': <Map<String, dynamic>>[],
};

String? _value(WidgetTester tester, String name) =>
    tester.widget<Text>(find.byKey(ValueKey('dashboard-$name-value'))).data;

Future<void> _pump(WidgetTester tester,
    {Map<String, dynamic>? report,
    bool loading = false,
    double width = 390,
    double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.emeraldLight,
    home: MediaQuery(
      data: MediaQueryData(
          size: Size(width, 650), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
          body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: DashboardSalesMetrics(report: report, loading: loading),
      )),
    ),
  ));
  await tester.pump();
}
