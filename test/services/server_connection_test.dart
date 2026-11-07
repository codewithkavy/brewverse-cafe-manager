import 'dart:async';

import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/bill_adjustment_screen.dart';
import 'package:brewverse_cafe_manager/screens/billing_screen.dart';
import 'package:brewverse_cafe_manager/screens/inventory_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/services/checkout_recovery_store.dart';
import 'package:brewverse_cafe_manager/services/server_connection.dart';
import 'package:brewverse_cafe_manager/widgets/firebase_connection_scope.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const item = StockItem(
    id: 'item',
    name: 'Cached coffee',
    category: 'finished',
    stockMode: 'direct',
    unit: 'cup',
    quantity: 5,
    minimumQuantity: 1,
    purchasePricePerUnit: 0,
    sellingPrice: 80);

void main() {
  tearDown(() => ServerConnection.instance.endSession());

  test('only a confirmed server response enables managed mutations', () {
    final connection = ServerConnection();
    connection.beginSession();
    expect(connection.canWrite, isFalse);
    connection.reportSnapshot(fromCache: true);
    expect(connection.canWrite, isFalse);
    expect(connection.requireConfirmedOnline,
        throwsA(isA<OfflineOperationException>()));
    connection.reportSnapshot(fromCache: false);
    expect(connection.canWrite, isTrue);
    connection.markUnavailable();
    expect(connection.canWrite, isFalse);
  });
  test('permission errors never qualify for cached fallback', () {
    expect(
        isOfflineReadFailure(
            FirebaseException(plugin: 'firestore', code: 'permission-denied')),
        isFalse);
    expect(
        isOfflineReadFailure(
            FirebaseException(plugin: 'firestore', code: 'unavailable')),
        isTrue);
    expect(isOfflineReadFailure(TimeoutException('offline')), isTrue);
  });
  test(
      'offline service guards leave all fake financial and stock data untouched',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('stock_items').doc('item').set(item.toMap());
    final service = CafeService(
        firestore: db,
        cafeId: 'cafe',
        onlineCheck: () async => throw const OfflineOperationException());
    final before =
        (await db.collection('stock_items').doc('item').get()).data();
    for (final operation in <Future<dynamic> Function()>[
      () => service.addItem(item),
      () => service.updateItem(item),
      () => service.addStock(itemId: 'item', quantity: 1, reason: 'test'),
      () => service.saveRecipe(productId: 'item', ingredients: []),
      () => service.setPhotoUrl('item', 'new-url'),
      () => service.replacePhotoUrl(
          itemId: 'item', expectedUrl: '', newUrl: 'new-url'),
      () => service.checkout(
          checkoutId: 'offline-bill', cart: {'item': 1}, orderType: 'dineIn'),
    ]) {
      await expectLater(operation(), throwsA(isA<OfflineOperationException>()));
    }
    expect(
        (await db.collection('stock_items').doc('item').get()).data(), before);
    expect((await db.collection('bills').get()).docs, isEmpty);
    expect((await db.collection('stock_movements').get()).docs, isEmpty);
  });
  test('offline callables reject mutations before invoking backend', () async {
    var calls = 0;
    final service = CafeFunctionsService(
        invoker: (_, __) async {
          calls++;
          return {};
        },
        onlineCheck: () async => throw const OfflineOperationException());
    await expectLater(
        service.refundBill(
            cafeId: 'cafe',
            billId: 'bill',
            adjustmentId: 'adjustment',
            amountMinor: 8000,
            reason: 'test'),
        throwsA(isA<OfflineOperationException>()));
    await expectLater(
        service.voidBill(
            cafeId: 'cafe',
            billId: 'bill',
            adjustmentId: 'adjustment',
            reason: 'test'),
        throwsA(isA<OfflineOperationException>()));
    expect(calls, 0);
    await service.getSalesSummary(
        cafeId: 'cafe', startAt: DateTime(2026), endAt: DateTime(2026, 2));
    expect(calls, 1);
  });
  testWidgets(
      'connection banner distinguishes cache and recovers automatically',
      (tester) async {
    final events = StreamController<bool>();
    final connection = ServerConnection();
    await tester.pumpWidget(MaterialApp(
        home: FirebaseConnectionScope(
            connection: connection,
            serverConfirmation: events.stream,
            child: const Text('Cached records stay visible'))));
    expect(find.textContaining('Checking connection'), findsOneWidget);
    events.add(false);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Cached data may be out of date'), findsOneWidget);
    expect(find.text('Cached records stay visible'), findsOneWidget);
    events.add(true);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cached data may be out of date'), findsNothing);
    expect(connection.canWrite, isTrue);
    await tester.pumpWidget(const SizedBox());
    unawaited(events.close());
  });
  testWidgets(
      'same-user token refresh restarts confirmation after email verification',
      (tester) async {
    final sessions = StreamController<User?>();
    final first = StreamController<bool>(), verified = StreamController<bool>();
    final connection = ServerConnection();
    var subscriptions = 0;
    await tester.pumpWidget(MaterialApp(
        home: FirebaseConnectionScope(
            connection: connection,
            sessions: sessions.stream,
            membershipConfirmation: (_) =>
                subscriptions++ == 0 ? first.stream : verified.stream,
            child: const Text('Workspace'))));
    sessions.add(_SessionUser());
    await tester.pumpAndSettle();
    first.addError(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'));
    await tester.pumpAndSettle();
    expect(connection.canWrite, isFalse);
    // A verified token is emitted for the same UID, without a sign-out/sign-in.
    sessions.add(_SessionUser());
    await tester.pumpAndSettle();
    verified.add(true);
    await tester.pumpAndSettle();
    expect(subscriptions, 2);
    expect(connection.canWrite, isTrue);
    await tester.pumpWidget(const SizedBox());
    unawaited(sessions.close());
    unawaited(first.close());
    unawaited(verified.close());
  });

  testWidgets(
      'offline inventory keeps cached stock visible and disables mutation controls',
      (tester) async {
    ServerConnection.instance.beginSession();
    ServerConnection.instance.markUnavailable();
    await tester.pumpWidget(MaterialApp(
        home: InventoryScreen(
            cafeId: 'cafe',
            cafeRole: CafeRole.owner,
            cafeService: _CachedService())));
    await tester.pumpAndSettle();
    expect(find.text('Cached coffee'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'Add item'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<PopupMenuButton>(find.byWidgetPredicate((widget) =>
                widget is PopupMenuButton && widget.tooltip == 'Item actions'))
            .enabled,
        isFalse);
  });
  testWidgets('offline financial adjustments are disabled for an owner',
      (tester) async {
    ServerConnection.instance.beginSession();
    ServerConnection.instance.markUnavailable();
    await tester.pumpWidget(const MaterialApp(
        home: BillAdjustmentScreen(cafeId: 'cafe', role: CafeRole.owner)));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
  });
  testWidgets(
      'losing connection while cart is open disables checkout without sending',
      (tester) async {
    final service = _CachedService();
    ServerConnection.instance.beginSession();
    ServerConnection.instance.reportSnapshot(fromCache: false);
    await tester.pumpWidget(MaterialApp(
        home: BillingScreen(
            cafeId: 'cafe',
            cafeRole: CafeRole.owner,
            cafeService: service,
            recoveryStore: MemoryCheckoutRecoveryStore())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add Cached coffee'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Review order'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Complete checkout'))
            .onPressed,
        isNotNull);
    ServerConnection.instance.markUnavailable();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ElevatedButton>(
                find.widgetWithText(ElevatedButton, 'Complete checkout'))
            .onPressed,
        isNull);
    expect(service.checkouts, 0);
  });
}

class _CachedService implements CafeService {
  int checkouts = 0;
  @override
  Stream<List<StockItem>> watchStock() => Stream.value(const [item]);
  @override
  Future<String> checkout(
      {required String checkoutId,
      required Map<String, int> cart,
      required String orderType,
      String? customerPhone,
      int redeemPoints = 0}) async {
    checkouts++;
    return checkoutId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SessionUser extends Fake implements User {
  @override
  String get uid => 'same-owner';
}
