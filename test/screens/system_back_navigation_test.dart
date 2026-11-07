import 'dart:async';

import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/analytics_screen.dart';
import 'package:brewverse_cafe_manager/screens/auth_gate.dart';
import 'package:brewverse_cafe_manager/screens/billing_screen.dart';
import 'package:brewverse_cafe_manager/screens/cafe_workspace_gate.dart';
import 'package:brewverse_cafe_manager/screens/inventory_screen.dart';
import 'package:brewverse_cafe_manager/screens/loyalty_screen.dart';
import 'package:brewverse_cafe_manager/screens/more_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_membership_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/services/checkout_recovery_store.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _product = StockItem(
    id: 'product',
    name: 'Test coffee',
    category: 'finished',
    unit: 'cup',
    quantity: 10,
    minimumQuantity: 1,
    purchasePricePerUnit: 0,
    sellingPrice: 80,
    stockMode: 'direct');

class _Service implements CafeService {
  final pendingCheckout = Completer<String>();
  int checkouts = 0;
  @override
  Stream<List<StockItem>> watchStock() => Stream.value(const [_product]);
  @override
  Future<String> checkout(
      {required String checkoutId,
      required Map<String, int> cart,
      required String orderType,
      String? customerPhone,
      int redeemPoints = 0}) {
    checkouts++;
    return pendingCheckout.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, WidgetBuilder page) async {
  final db = FakeFirebaseFirestore();
  await db.collection('cafe_members').doc('user_cafe').set({
    'uid': 'user',
    'cafeId': 'cafe',
    'role': 'owner',
    'status': 'active',
  });
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
      home: SessionNavigationBoundary(
    child: CafeWorkspaceGate(
      uid: 'user',
      membershipService: CafeMembershipService(firestore: db),
      homeBuilder: (context, membership, _) => Scaffold(
          body: Column(children: [
        const Text('Dashboard fixture'),
        TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: page)),
            child: const Text('Open page')),
      ])),
    ),
  )));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open page'));
  await tester.pumpAndSettle();
}

void main() {
  for (final name in ['Inventory', 'Billing', 'Loyalty', 'More', 'Analytics']) {
    testWidgets('system Back from $name returns to the workspace Dashboard',
        (tester) async {
      final service = _Service();
      await _mount(
          tester,
          (_) => switch (name) {
                'Inventory' => InventoryScreen(
                    cafeId: 'cafe',
                    cafeRole: CafeRole.owner,
                    cafeService: service),
                'Billing' => BillingScreen(
                    cafeId: 'cafe',
                    cafeRole: CafeRole.owner,
                    cafeService: service,
                    recoveryStore: MemoryCheckoutRecoveryStore()),
                'Loyalty' => LoyaltyScreen(
                    cafeId: 'cafe',
                    cafeRole: CafeRole.owner,
                    cafeService: service),
                'More' => MoreScreen(
                    cafeId: 'cafe',
                    cafeRole: CafeRole.owner,
                    cafeService: service),
                _ => AnalyticsScreen(
                    cafeId: 'cafe',
                    cafeRole: CafeRole.owner,
                    cafeService: service,
                    functionsService: CafeFunctionsService(
                        invoker: (_, __) async => {
                              'completedBillCount': 0,
                              'grossRevenue': 0,
                              'itemsSold': 0,
                              'bestSellingProducts': [],
                            })),
              });
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Dashboard fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Back at the dashboard must not empty either nested navigator.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Dashboard fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('system Back closes a workspace dialog before its page',
      (tester) async {
    await _mount(
        tester,
        (context) => Scaffold(
                body: TextButton(
              onPressed: () => showDialog<void>(
                  context: context,
                  useRootNavigator: false,
                  builder: (_) =>
                      const AlertDialog(title: Text('Workspace dialog'))),
              child: const Text('Open dialog'),
            )));
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Workspace dialog'), findsNothing);
    expect(find.text('Open dialog'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Dashboard fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'system Back respects Billing checkout veto without losing the workspace',
      (tester) async {
    final service = _Service();
    await _mount(
        tester,
        (_) => BillingScreen(
            cafeId: 'cafe',
            cafeRole: CafeRole.owner,
            cafeService: service,
            recoveryStore: MemoryCheckoutRecoveryStore()));
    await tester.tap(find.byTooltip('Add Test coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Complete checkout'));
    await tester.tap(find.text('Complete checkout'));
    await tester.pump(const Duration(seconds: 1));
    expect(service.checkouts, 1);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BillingScreen), findsOneWidget);
    expect(find.text('Dashboard fixture'), findsNothing);
    expect(tester.takeException(), isNull);
    service.pendingCheckout.completeError(Exception('Simulated lost reply'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Dashboard fixture'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
