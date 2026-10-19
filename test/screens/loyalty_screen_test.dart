import 'dart:async';

import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/billing_screen.dart';
import 'package:brewverse_cafe_manager/screens/home_screen.dart';
import 'package:brewverse_cafe_manager/screens/loyalty_customer_details_screen.dart';
import 'package:brewverse_cafe_manager/screens/loyalty_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no workspace shows a clear loyalty empty state without balances',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: LoyaltyScreen(cafeId: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Select a café workspace'), findsOneWidget);
    expect(find.textContaining('No customer or points data'), findsOneWidget);
    expect(find.text('120'), findsNothing);
    expect(find.text('₹60'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.ancestor(
            of: find.text('New customer bill'),
            matching:
                find.byWidgetPredicate((widget) => widget is FilledButton),
          ))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('278px initial member lookup has no fabricated directory data',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, service: service);

    expect(find.text('Find a loyalty member'), findsOneWidget);
    expect(find.text('Customer list unavailable'), findsOneWidget);
    expect(find.textContaining('points available'), findsNothing);
    expect(service.lookupPhones, isEmpty);
    expect(service.settingsCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('278px loyalty states remain bounded at 1.6 text scale',
      (tester) async {
    _phoneSize(tester);
    await _pumpLoyalty(tester,
        service: _LoyaltyFixtureService(), textScale: 1.6);
    expect(tester.takeException(), isNull);
    await _lookup(tester);
    expect(find.text('137 points available'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Transactions'));
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction history unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful lookup shows the actual balance and masked phone',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, service: service);
    await _lookup(tester);

    expect(service.lookupPhones, [_phone]);
    expect(service.settingsCalls, 1);
    expect(find.text('Loyalty member'), findsOneWidget);
    expect(find.text('137 points available'), findsOneWidget);
    expect(find.text('•••••••••3210'), findsOneWidget);
    expect(find.byTooltip('View customer details'), findsOneWidget);
    expect(find.text('Use phone at checkout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing checkout receives the exact looked-up phone',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, service: service);
    await _lookup(tester);
    await tester.ensureVisible(find.text('Use phone at checkout'));
    await tester.tap(find.text('Use phone at checkout'));
    await tester.pumpAndSettle();

    final billing = tester.widget<BillingScreen>(find.byType(BillingScreen));
    expect(billing.initialCustomerPhone, _phone);
    expect(billing.cafeId, 'cafe-a');
    expect(billing.cafeService, same(service));
    expect(service.lookupPhones, [_phone]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not-found customer never invents a balance or successful record',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService(customer: const {'found': false});
    await _pumpLoyalty(tester, service: service);
    await _lookup(tester);

    expect(find.text('No member found'), findsOneWidget);
    expect(find.textContaining('points available'), findsNothing);
    expect(find.byTooltip('View customer details'), findsNothing);
    await tester.ensureVisible(find.text('Start a bill for this phone'));
    await tester.tap(find.text('Start a bill for this phone'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<BillingScreen>(find.byType(BillingScreen))
            .initialCustomerPhone,
        _phone);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty phone validates locally without service requests',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, service: service);
    await tester.tap(find.byTooltip('Find customer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter a customer phone'), findsOneWidget);
    expect(service.lookupPhones, isEmpty);
    expect(service.settingsCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lookup error reports failure without implying a customer found',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService(
        lookupError: StateError('fixture lookup rejected'));
    await _pumpLoyalty(tester, service: service);
    await _lookup(tester);

    expect(find.textContaining('fixture lookup rejected'), findsOneWidget);
    expect(find.text('Loyalty member'), findsNothing);
    expect(find.textContaining('points available'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long lookup error wraps safely at 278px and 1.6 text scale',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService(
        lookupError: StateError(List.filled(45, 'fixture error').join(' ')));
    await _pumpLoyalty(tester, service: service, textScale: 1.6);
    await _lookup(tester);

    expect(find.textContaining('fixture error'), findsOneWidget);
    expect(find.textContaining('points available'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending lookup disables editing and repeated lookup requests',
      (tester) async {
    _phoneSize(tester);
    final response = Completer<Map<String, dynamic>>();
    final service = _LoyaltyFixtureService(pendingLookup: response);
    await _pumpLoyalty(tester, service: service);
    await tester.enterText(find.byType(TextField), _phone);
    await tester.tap(find.byTooltip('Find customer'));
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    final findButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Find customer');
    expect(tester.widget<IconButton>(findButton).onPressed, isNull);
    expect(service.lookupPhones, [_phone]);
    expect(find.textContaining('points available'), findsNothing);
    expect(tester.takeException(), isNull);

    response.complete(_foundCustomer);
    await tester.pumpAndSettle();
    expect(find.text('137 points available'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('tab changes reuse lookup data without further service calls',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, service: service);
    await _lookup(tester);
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction history unavailable'), findsOneWidget);
    expect(find.text('137 points available'), findsNothing);
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();

    expect(find.text('137 points available'), findsOneWidget);
    expect(service.lookupPhones, [_phone]);
    expect(service.settingsCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'settings failure retains balance and marks point value unavailable',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService(
        settingsError: StateError('fixture settings unavailable'));
    await _pumpLoyalty(tester, service: service);
    await _lookup(tester);

    expect(find.text('137 points available'), findsOneWidget);
    expect(find.textContaining('Point value unavailable'), findsOneWidget);
    await tester.tap(find.byTooltip('View customer details'));
    await tester.pumpAndSettle();
    final details = tester.widget<LoyaltyCustomerDetailsScreen>(
        find.byType(LoyaltyCustomerDetailsScreen));
    expect(details.customer['pointsBalance'], 137);
    expect(details.pointValueMinor, isNull);
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear search removes the old customer and actual input text',
      (tester) async {
    _phoneSize(tester);
    await _pumpLoyalty(tester, service: _LoyaltyFixtureService());
    await _lookup(tester);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('137 points available'), findsNothing);
    expect(find.text('Find a loyalty member'), findsOneWidget);
    expect(find.text('New customer bill'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale lookup cannot attach a balance to an edited phone',
      (tester) async {
    _phoneSize(tester);
    final response = Completer<Map<String, dynamic>>();
    final service = _LoyaltyFixtureService(pendingLookup: response);
    await _pumpLoyalty(tester, service: service);
    await tester.enterText(find.byType(TextField), _phone);
    await tester.tap(find.byTooltip('Find customer'));
    await tester.pump();

    // Simulate a programmatic prefill replacement; normal typing is disabled.
    tester.widget<TextField>(find.byType(TextField)).controller!.text =
        '+919999999999';
    response.complete(_foundCustomer);
    await tester.pumpAndSettle();

    expect(find.text('137 points available'), findsNothing);
    expect(find.byTooltip('View customer details'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('standalone Loyalty Home opens the existing dashboard',
      (tester) async {
    _phoneSize(tester);
    await _pumpLoyalty(tester, cafeId: null, service: _LoyaltyFixtureService());
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(LoyaltyScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace replacement rejects pending previous-cafe response',
      (tester) async {
    _phoneSize(tester);
    final response = Completer<Map<String, dynamic>>();
    final oldService = _LoyaltyFixtureService(pendingLookup: response);
    await _pumpLoyalty(tester, service: oldService);
    await tester.enterText(find.byType(TextField), _phone);
    await tester.tap(find.byTooltip('Find customer'));
    await tester.pump();

    final newService = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, cafeId: 'cafe-b', service: newService);
    response.complete(_foundCustomer);
    await tester.pumpAndSettle();
    expect(find.text('137 points available'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('Find a loyalty member'), findsOneWidget);
    expect(newService.lookupPhones, isEmpty);
    await _lookup(tester);
    expect(newService.lookupPhones, [_phone]);
    expect(find.text('137 points available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-cafe service replacement clears previous lookup state',
      (tester) async {
    _phoneSize(tester);
    await _pumpLoyalty(tester, service: _LoyaltyFixtureService());
    await _lookup(tester);
    final newService = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, service: newService);

    expect(find.text('137 points available'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(newService.lookupPhones, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone keyboard submit invokes one existing customer lookup',
      (tester) async {
    _phoneSize(tester);
    final service = _LoyaltyFixtureService();
    await _pumpLoyalty(tester, service: service);
    await tester.enterText(find.byType(TextField), _phone);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(service.lookupPhones, [_phone]);
    expect(find.text('137 points available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(278, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpLoyalty(WidgetTester tester,
    {String? cafeId = 'cafe-a',
    required CafeService service,
    double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: LoyaltyScreen(cafeId: cafeId, cafeService: service),
  ));
  await tester.pumpAndSettle();
}

Future<void> _lookup(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), _phone);
  await tester.tap(find.byTooltip('Find customer'));
  await tester.pumpAndSettle();
}

const _phone = '+919876543210';
const _foundCustomer = <String, dynamic>{
  'found': true,
  'phoneNumber': _phone,
  'pointsBalance': 137,
};

class _LoyaltyFixtureService implements CafeService {
  _LoyaltyFixtureService({
    this.customer = _foundCustomer,
    this.lookupError,
    this.settingsError,
    this.pendingLookup,
  });

  final Map<String, dynamic> customer;
  final Object? lookupError;
  final Object? settingsError;
  final Completer<Map<String, dynamic>>? pendingLookup;
  final lookupPhones = <String>[];
  int settingsCalls = 0;

  @override
  Stream<List<StockItem>> watchStock() => Stream.value(const []);

  @override
  Future<Map<String, dynamic>> lookupLoyaltyCustomer({
    required String phoneNumber,
  }) async {
    lookupPhones.add(phoneNumber);
    if (lookupError case final error?) throw error;
    return pendingLookup == null ? customer : await pendingLookup!.future;
  }

  @override
  Future<Map<String, dynamic>> getLoyaltySettings() async {
    settingsCalls++;
    if (settingsError case final error?) throw error;
    return {'pointValueMinor': 100};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
