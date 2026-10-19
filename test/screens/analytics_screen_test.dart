import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/analytics_screen.dart';
import 'package:brewverse_cafe_manager/screens/home_screen.dart';
import 'package:brewverse_cafe_manager/screens/more_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/widgets/cafe_bottom_navigation.dart';
import 'package:brewverse_cafe_manager/widgets/sales_summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('278px empty report shows no invented figures and stays bounded',
      (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(const MaterialApp(home: AnalyticsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('No café report connected'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .onChanged,
      isNull,
    );
    expect(find.byType(CafeBottomNavigation), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Items'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SalesReportView>(find.byType(SalesReportView)).metric,
      SalesReportMetric.items,
    );
    expect(find.textContaining('₹'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metric tabs reuse the saved report without another callable',
      (tester) async {
    _phoneSize(tester);
    var calls = 0;
    final service = CafeFunctionsService(invoker: (name, data) async {
      expect(name, 'getSalesSummary');
      expect(data['cafeId'], 'cafe-a');
      calls++;
      return _savedReport;
    });
    await tester.pumpWidget(MaterialApp(
      home: AnalyticsScreen(cafeId: 'cafe-a', functionsService: service),
    ));
    await tester.pumpAndSettle();

    expect(calls, 1);
    for (final entry in {
      'Orders': SalesReportMetric.orders,
      'Items': SalesReportMetric.items,
      'Sales': SalesReportMetric.sales,
    }.entries) {
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      final reportView =
          tester.widget<SalesReportView>(find.byType(SalesReportView));
      expect(reportView.metric, entry.value);
      expect(reportView.report, _savedReport);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('30-day date selection requests one supported report range',
      (tester) async {
    _phoneSize(tester);
    final ranges = <Duration>[];
    final service = CafeFunctionsService(invoker: (name, data) async {
      expect(name, 'getSalesSummary');
      ranges.add(DateTime.parse(data['endAt'] as String)
          .difference(DateTime.parse(data['startAt'] as String)));
      return _savedReport;
    });
    await tester.pumpWidget(MaterialApp(
      home: AnalyticsScreen(cafeId: 'cafe-a', functionsService: service),
    ));
    await tester.pumpAndSettle();
    expect(ranges, [const Duration(days: 7)]);

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .style
          ?.color,
      isNot(Colors.white),
    );
    await tester.tap(find.text('30 days').last);
    await tester.pumpAndSettle();

    expect(ranges, [const Duration(days: 7), const Duration(days: 30)]);
    expect(
      tester.widget<SalesReportView>(find.byType(SalesReportView)).rangeDays,
      30,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('More navigation opens its existing screen from Analytics',
      (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      home: AnalyticsScreen(cafeService: _PreviewCafeService()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.byType(MoreScreen), findsOneWidget);
    expect(find.byType(AnalyticsScreen), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(MoreScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back returns to previous route when Analytics was pushed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AnalyticsScreen()),
            ),
            child: const Text('Open analytics'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open analytics'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Open analytics'), findsOneWidget);
    expect(find.byType(AnalyticsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root preview back opens Home using the injected stock service',
      (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(MaterialApp(
      home: AnalyticsScreen(cafeService: _PreviewCafeService()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AnalyticsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(278, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

const _savedReport = <String, dynamic>{
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

class _PreviewCafeService implements CafeService {
  @override
  Stream<List<StockItem>> watchStock() => Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
