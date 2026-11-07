import 'package:brewverse_cafe_manager/screens/loyalty_customer_details_screen.dart';
import 'package:brewverse_cafe_manager/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the lookup balance and routes earning through checkout',
      (tester) async {
    tester.view.physicalSize = const Size(270, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var startedBill = false;
    await tester.pumpWidget(MaterialApp(
      home: LoyaltyCustomerDetailsScreen(
        customer: const {
          'found': true,
          'phoneNumber': '+919876543210',
          'pointsBalance': 120,
        },
        phoneNumber: '+919876543210',
        pointValueMinor: 100,
        onStartBill: () => startedBill = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Customer details'), findsOneWidget);
    expect(find.text('•••••••••3210'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('₹120'), findsOneWidget);
    expect(find.text('Transaction history is not included in this build'),
        findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Earn at checkout'));
    await tester.tap(find.text('Earn at checkout'));
    expect(startedBill, isTrue);
  });

  for (final entry in <String, Map<String, dynamic>>{
    'missing customer': {},
    'not-found customer': {'found': false, 'pointsBalance': 120},
    'unconfirmed customer': {'pointsBalance': 120},
    'negative balance': {'found': true, 'pointsBalance': -1},
    'missing balance': {'found': true},
    'invalid balance type': {'found': true, 'pointsBalance': 120.0},
  }.entries) {
    testWidgets('${entry.key} never invents balances or enabled operations',
        (tester) async {
      _phoneSize(tester);
      var checkoutCalls = 0;
      await _pumpDetails(tester,
          customer: entry.value, onStartBill: () => checkoutCalls++);

      expect(find.text('No customer selected'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
      expect(_action(tester, 'Earn at checkout').onPressed, isNull);
      expect(_action(tester, 'Redeem at checkout').onPressed, isNull);
      expect(checkoutCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final pointValue in <int?>[null, 0, -100]) {
    testWidgets(
        'point value $pointValue preserves points without inventing value',
        (tester) async {
      _phoneSize(tester);
      await _pumpDetails(tester, pointValueMinor: pointValue);

      expect(find.text('120'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('Point value unavailable'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
      expect(_action(tester, 'Earn at checkout').onPressed, isNotNull);
      expect(_action(tester, 'Redeem at checkout').onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('confirmed zero balance remains a real zero and disables redeem',
      (tester) async {
    _phoneSize(tester);
    await _pumpDetails(tester,
        customer: const {'found': true, 'pointsBalance': 0});

    expect(find.text('0'), findsOneWidget);
    expect(find.text('₹0'), findsOneWidget);
    expect(find.text('No customer selected'), findsNothing);
    expect(_action(tester, 'Earn at checkout').onPressed, isNotNull);
    expect(_action(tester, 'Redeem at checkout').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fractional point value retains its actual two decimal amount',
      (tester) async {
    _phoneSize(tester);
    await _pumpDetails(tester,
        customer: const {'found': true, 'pointsBalance': 3},
        pointValueMinor: 25);

    expect(find.text('3'), findsOneWidget);
    expect(find.text('₹0.75'), findsOneWidget);
    expect(_action(tester, 'Redeem at checkout').onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large real balances fit a 278px phone at 1.6 text scale',
      (tester) async {
    _phoneSize(tester);
    await _pumpDetails(tester,
        customer: const {'found': true, 'pointsBalance': 987654321},
        textScale: 1.6);

    expect(find.text('987654321'), findsOneWidget);
    expect(find.text('₹987654321'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Redeem at checkout'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('balance cards stack at large text instead of clipping labels',
      (tester) async {
    _phoneSize(tester);
    await _pumpDetails(tester, textScale: 1.6);

    final points = tester.getRect(find.text('Total points'));
    final value = tester.getRect(find.text('Available value'));
    expect(value.top, greaterThan(points.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'short phone scrolls to existing checkout and unavailable history',
      (tester) async {
    _phoneSize(tester, height: 420);
    var checkoutCalls = 0;
    await _pumpDetails(tester,
        textScale: 1.6, onStartBill: () => checkoutCalls++);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Redeem at checkout'));
    await tester.pumpAndSettle();
    expect(find.text('Redeem at checkout').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Redeem at checkout'));
    await tester.pumpAndSettle();
    expect(checkoutCalls, 1);
    await tester.ensureVisible(
        find.text('Transaction history is not included in this build'));
    await tester.pumpAndSettle();
    expect(
        find
            .text('Transaction history is not included in this build')
            .hitTestable(),
        findsOneWidget);
    expect(find.text('Transaction history is not included in this build'),
        findsOneWidget);
    expect(find.textContaining('points added'), findsNothing);
    expect(find.textContaining('redeemed successfully'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'customer details retains Emerald theme under production dark theme',
      (tester) async {
    _phoneSize(tester);
    await _pumpDetails(tester, theme: AppTheme.dark);

    final theme = Theme.of(tester.element(find.text('Earn at checkout')));
    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, AppTheme.emerald);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earn and redeem each invoke the existing checkout callback once',
      (tester) async {
    _phoneSize(tester);
    var checkoutCalls = 0;
    await _pumpDetails(tester, onStartBill: () => checkoutCalls++);

    await tester.ensureVisible(find.text('Earn at checkout'));
    await tester.tap(find.text('Earn at checkout'));
    await tester.pumpAndSettle();
    expect(checkoutCalls, 1);
    await tester.ensureVisible(find.text('Redeem at checkout'));
    await tester.tap(find.text('Redeem at checkout'));
    await tester.pumpAndSettle();
    expect(checkoutCalls, 2);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('₹120'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing checkout callback disables both actions for a real member',
      (tester) async {
    _phoneSize(tester);
    await _pumpDetails(tester, onStartBill: null);

    expect(find.text('120'), findsOneWidget);
    expect(find.text('₹120'), findsOneWidget);
    expect(_action(tester, 'Earn at checkout').onPressed, isNull);
    expect(_action(tester, 'Redeem at checkout').onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'normalized customer phone is masked instead of showing input phone',
      (tester) async {
    _phoneSize(tester);
    await _pumpDetails(tester, customer: const {
      'found': true,
      'pointsBalance': 120,
      'phoneNumber': '+919999994321',
    });

    expect(find.text('•••••••••4321'), findsOneWidget);
    expect(find.text('+919999994321'), findsNothing);
    expect(find.text('•••••••••3210'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back uses the explicit preview override once', (tester) async {
    _phoneSize(tester);
    var backCalls = 0;
    await _pumpDetails(tester, onBack: () => backCalls++);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(backCalls, 1);
    expect(find.byType(LoyaltyCustomerDetailsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _phoneSize(WidgetTester tester, {double height = 650}) {
  tester.view.physicalSize = Size(278, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpDetails(WidgetTester tester,
    {Map<String, dynamic> customer = const {
      'found': true,
      'phoneNumber': '+919876543210',
      'pointsBalance': 120,
    },
    int? pointValueMinor = 100,
    VoidCallback? onStartBill = _noop,
    VoidCallback? onBack,
    double textScale = 1,
    ThemeData? theme}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: LoyaltyCustomerDetailsScreen(
      customer: customer,
      phoneNumber: '+919876543210',
      pointValueMinor: pointValueMinor,
      onStartBill: onStartBill,
      onBack: onBack,
    ),
  ));
  await tester.pumpAndSettle();
}

ButtonStyleButton _action(WidgetTester tester, String label) =>
    tester.widget(find.ancestor(
        of: find.text(label),
        matching:
            find.byWidgetPredicate((widget) => widget is ButtonStyleButton)));

void _noop() {}
