import 'dart:async';

import 'package:brewverse_cafe_manager/models/saved_bill.dart';
import 'package:brewverse_cafe_manager/screens/bill_history_screen.dart';
import 'package:brewverse_cafe_manager/services/bill_history_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/bill_history_service_test.dart' show historicalBill;

class _PendingRepository implements BillHistoryRepository {
  @override
  final String cafeId = 'cafe-a';
  final pending = Completer<BillHistoryPage>();
  @override
  Future<BillHistoryPage> load(
          {required BillHistoryFilter filter, Object? cursor}) =>
      pending.future;
  @override
  Future<SavedBill?> get(String billId) async => null;
}

class _CachedRepository implements BillHistoryRepository {
  final bill = SavedBill(
      'cached-bill', historicalBill(date: DateTime(2026, 10, 19)),
      isFromCache: true);
  @override
  String get cafeId => 'cafe-a';
  @override
  Future<BillHistoryPage> load(
          {required BillHistoryFilter filter, Object? cursor}) async =>
      BillHistoryPage([bill], fromCache: true);
  @override
  Future<SavedBill?> get(String billId) async => bill;
}

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreBillHistoryRepository repo;
  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = FirestoreBillHistoryRepository(
        cafeId: 'cafe-a', firestore: db, pageSize: 1);
    await db.collection('bills').doc('older').set(
        historicalBill(date: DateTime(2026, 10, 19), phone: '+919876543210'));
    await db
        .collection('bills')
        .doc('newer')
        .set(historicalBill(date: DateTime(2026, 10, 20)));
  });
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(278, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('cached history and details stay explicitly unconfirmed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(
            cafeId: 'cafe-a', repository: _CachedRepository())));
    await tester.pumpAndSettle();
    expect(find.text('Cached bills — may be out of date. Reconnect to verify.'),
        findsOneWidget);
    await tester.tap(find.text('cached-bill'));
    await tester.pumpAndSettle();
    expect(find.text('Cached bill — may be out of date. Reconnect to verify.'),
        findsOneWidget);
  });

  testWidgets('history labels refunded and void bills from saved statuses',
      (tester) async {
    await db.collection('bills').doc('older').update({'status': 'refunded'});
    await db.collection('bills').doc('newer').update({'status': 'void'});
    final allBills = FirestoreBillHistoryRepository(
        cafeId: 'cafe-a', firestore: db, pageSize: 10);
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(cafeId: 'cafe-a', repository: allBills)));
    await tester.pumpAndSettle();
    expect(find.text('Void'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
  });

  testWidgets(
      'history loads and paginates older bills without exposing full phones',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(cafeId: 'cafe-a', repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('newer'), findsOneWidget);
    expect(find.text('older'), findsNothing);
    await tester.ensureVisible(find.text('Load more bills'));
    await tester.tap(find.text('Load more bills'));
    await tester.pumpAndSettle();
    expect(find.text('older'), findsOneWidget);
    expect(find.text('+919876543210'), findsNothing);
    expect(find.textContaining('3210'), findsOneWidget);
    expect(find.text('Load more bills'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'exact ID search, clear filters and details navigation use saved values',
      (tester) async {
    phone(tester);
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(cafeId: 'cafe-a', repository: repo)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'older');
    await tester.tap(find.byTooltip('Search bills'));
    await tester.pumpAndSettle();
    expect(find.text('older'), findsNWidgets(2));
    expect(find.text('newer'), findsNothing);
    await tester.tap(find.text('older').last);
    await tester.pumpAndSettle();
    expect(find.text('Bill details'), findsOneWidget);
    expect(find.text('Saved burger name'), findsOneWidget);
    expect(find.text('+919876543210'), findsNothing);
    await tester.tap(find.byTooltip('Show customer phone'));
    await tester.pump();
    expect(find.text('+919876543210'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('newer'), findsOneWidget);
  });
  testWidgets('loading, no matches and query errors have distinct states',
      (tester) async {
    final pending = _PendingRepository();
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(cafeId: 'cafe-a', repository: pending)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.pending.completeError(FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Café access could not be verified'),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('No bills found'), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(
            key: const ValueKey('empty'),
            cafeId: 'empty',
            repository: FirestoreBillHistoryRepository(
                cafeId: 'empty', firestore: db))));
    await tester.pumpAndSettle();
    expect(find.text('No bills found'), findsOneWidget);
  });
  testWidgets('workspace change rejects a stale history response',
      (tester) async {
    final pending = _PendingRepository();
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(cafeId: 'cafe-a', repository: pending)));
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(
            cafeId: 'cafe-b',
            repository: FirestoreBillHistoryRepository(
                cafeId: 'cafe-b', firestore: db))));
    pending.pending.complete(
        BillHistoryPage([SavedBill('foreign-stale', historicalBill())]));
    await tester.pumpAndSettle();
    expect(find.text('foreign-stale'), findsNothing);
    expect(find.text('No bills found'), findsOneWidget);
  });
  testWidgets('date picker applies range and clear restores all dates',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: BillHistoryScreen(cafeId: 'cafe-a', repository: repo)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All dates'));
    await tester.pumpAndSettle();
    expect(find.text('Filter bill dates'), findsOneWidget);
    // Exercise actual picker through text entry, independent of current month.
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byType(TextField));
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '10/19/2026');
    await tester.enterText(fields.at(1), '10/19/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('older'), findsOneWidget);
    expect(find.text('newer'), findsNothing);
    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('newer'), findsOneWidget);
  });
  testWidgets('missing historical details stay unrecorded and cannot print',
      (tester) async {
    await db.collection('bills').doc('legacy').set({'cafeId': 'cafe-a'});
    await tester.pumpWidget(MaterialApp(
        home: BillDetailsScreen(billId: 'legacy', repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Date not recorded'), findsOneWidget);
    expect(find.text('Not recorded'), findsWidgets);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });
  testWidgets(
      'old bill reprint blocks rapid taps and keeps saved totals at large text scale',
      (tester) async {
    phone(tester);
    final pending = Completer<void>();
    var prints = 0;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: BillDetailsScreen(
            billId: 'older',
            repository: repo,
            printerOpener: (_, bill) async {
              prints++;
              expect(bill.amount('total'), 156);
              await pending.future;
            })));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Reprint receipt'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Reprint receipt'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.runAsync(() async {
      pending.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(prints, 1);
    expect(tester.takeException(), isNull);
  });
}
