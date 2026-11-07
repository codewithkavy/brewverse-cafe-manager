import 'dart:async';
import 'dart:convert';

import 'package:brewverse_cafe_manager/models/saved_bill.dart';
import 'package:brewverse_cafe_manager/services/bill_history_service.dart';
import 'package:brewverse_cafe_manager/services/bill_reprint_service.dart';
import 'package:brewverse_cafe_manager/services/thermal_printer_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> historicalBill(
        {String cafeId = 'cafe-a', DateTime? date, String? phone}) =>
    {
      'cafeId': cafeId,
      'createdAt': Timestamp.fromDate(date ?? DateTime(2026, 10, 20, 12)),
      'orderType': 'takeaway',
      'status': 'completed',
      'subtotal': 160,
      'discount': 4,
      'total': 156,
      'items': [
        {
          'name': 'Saved burger name',
          'quantity': 2,
          'unitPrice': 80,
          'lineTotal': 160
        }
      ],
      'loyalty': {'pointsRedeemed': 4, 'pointsEarned': 4},
      if (phone != null) 'customerPhone': phone,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore db;
  late FirestoreBillHistoryRepository repo;
  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = FirestoreBillHistoryRepository(
        cafeId: 'cafe-a', firestore: db, pageSize: 2);
    for (final id in ['a', 'b', 'c', 'd']) {
      await db.collection('bills').doc(id).set(historicalBill(
          date: DateTime(2026, 10, id == 'a' ? 19 : 20),
          phone: id == 'a' ? null : '+919876543210'));
    }
    await db
        .collection('bills')
        .doc('foreign')
        .set(historicalBill(cafeId: 'cafe-b'));
  });

  test(
      'server pages sort newest first with deterministic equal-date IDs and no gaps',
      () async {
    final page = await repo.load(filter: const BillHistoryFilter());
    expect(page.bills.map((b) => b.id), ['d', 'c']);
    expect(page.hasMore, true);
    final next =
        await repo.load(filter: const BillHistoryFilter(), cursor: page.cursor);
    expect(next.bills.map((b) => b.id), ['b', 'a']);
    expect(next.hasMore, false);
  });
  test('exact bill search is café scoped and missing IDs are empty', () async {
    expect(
        (await repo.load(filter: const BillHistoryFilter(search: 'c')))
            .bills
            .single
            .id,
        'c');
    expect(
        (await repo.load(filter: const BillHistoryFilter(search: 'foreign')))
            .bills,
        isEmpty);
    expect(await repo.get('foreign'), isNull);
    expect(
        (await repo.load(filter: const BillHistoryFilter(search: 'missing')))
            .bills,
        isEmpty);
    await expectLater(repo.get('../foreign'), throwsArgumentError);
  });
  test(
      'date range is inclusive at start and exclusive at end, including exact-ID search',
      () async {
    final filter = BillHistoryFilter(
        start: DateTime(2026, 10, 19), endExclusive: DateTime(2026, 10, 20));
    expect((await repo.load(filter: filter)).bills.single.id, 'a');
    expect(
        (await repo.load(
                filter: BillHistoryFilter(
                    search: 'a', start: DateTime(2026, 10, 20))))
            .bills,
        isEmpty);
    await expectLater(
        repo.load(
            filter: BillHistoryFilter(
                start: DateTime(2026, 10, 21),
                endExclusive: DateTime(2026, 10, 20))),
        throwsArgumentError);
  });
  test('phone search normalizes separators, combines dates, and paginates',
      () async {
    final filter = BillHistoryFilter(
        search: '+91 98765-43210',
        kind: BillSearchKind.phone,
        start: DateTime(2026, 10, 20),
        endExclusive: DateTime(2026, 10, 21));
    final first = await repo.load(filter: filter);
    expect(first.bills.map((b) => b.id), ['d', 'c']);
    expect(
        (await repo.load(filter: filter, cursor: first.cursor)).bills.single.id,
        'b');
    await expectLater(
        repo.load(
            filter: const BillHistoryFilter(
                search: '9876543210', kind: BillSearchKind.phone)),
        throwsArgumentError);
  });
  test('foreign cursor is rejected and empty workspace history is empty',
      () async {
    await expectLater(
        repo.load(
            filter: const BillHistoryFilter(),
            cursor: await db.collection('bills').doc('foreign').get()),
        throwsArgumentError);
    final empty =
        FirestoreBillHistoryRepository(cafeId: 'new-cafe', firestore: db);
    expect(
        (await empty.load(filter: const BillHistoryFilter())).bills, isEmpty);
  });
  test('missing historical fields stay missing and phone stays masked', () {
    final bill = SavedBill('old', {'cafeId': 'cafe-a'});
    expect(bill.amount('subtotal'), isNull);
    expect(bill.createdAt, isNull);
    expect(bill.hasReceiptFields, false);
    expect(billMoney(null), 'Not recorded');
    expect(SavedBill('id', historicalBill(phone: '+919876543210')).maskedPhone,
        '•••• 3210');
  });

  test(
      'older receipt uses saved prices on both paper widths, never mutates sale, stock or loyalty',
      () async {
    await db.collection('stock_items').doc('bun').set({'quantity': 38});
    final customer = db
        .collection('cafes')
        .doc('cafe-a')
        .collection('loyaltyCustomers')
        .doc('customer');
    await customer.set({'pointsBalance': 12});
    final before =
        (await db.collection('bills').get()).docs.map((d) => d.data()).toList();
    final reprints = BillReprintService(repo);
    for (final width in ReceiptPaperWidth.values) {
      expect(
          await reprints.reprint('a', (bill) async {
            expect(bill.id, 'a');
            final text = latin1.decode(await ThermalPrinterService()
                .buildReceiptBytes(
                    cafeName: 'Saved café',
                    billNumber: bill.id,
                    orderType: bill.text('orderType')!,
                    items: bill.items,
                    total: bill.amount('total')!.toDouble(),
                    discount: bill.amount('discount')!.toDouble(),
                    paperWidth: width,
                    issuedAt: bill.createdAt,
                    transactionStatus: bill.text('status'),
                    isReprint: true));
            expect(text, contains('Saved burger name'));
            expect(text, contains('2 x Rs 80.00'));
            expect(text, contains('TOTAL  Rs 156.00'));
            expect(text, contains('RECEIPT COPY'));
            expect(text, contains('STATUS: completed'));
            expect(text,
                contains('-' * (width == ReceiptPaperWidth.mm58 ? 32 : 48)));
          }),
          true);
    }
    expect(
        (await db.collection('bills').get()).docs.map((d) => d.data()).toList(),
        before);
    expect(
        (await db.collection('stock_items').doc('bun').get())
            .data()!['quantity'],
        38);
    expect((await customer.get()).data()!['pointsBalance'], 12);
  });
  test(
      'rapid reprints open one printer; failure releases guard and foreign/malformed bills cannot print',
      () async {
    final reprints = BillReprintService(repo);
    final pending = Completer<void>();
    var calls = 0;
    final first = reprints.reprint('a', (_) async {
      calls++;
      await pending.future;
    });
    expect(
        await reprints.reprint('a', (_) async {
          calls++;
        }),
        false);
    pending.complete();
    await first;
    expect(calls, 1);
    await expectLater(
        reprints.reprint('a', (_) async => throw StateError('printer failed')),
        throwsStateError);
    expect(await reprints.reprint('a', (_) async {}), true);
    await expectLater(
        reprints.reprint('foreign', (_) async => fail('foreign print')),
        throwsStateError);
    await db
        .collection('bills')
        .doc('bad')
        .set({'cafeId': 'cafe-a', 'total': 100});
    await expectLater(
        reprints.reprint('bad', (_) async => fail('invalid print')),
        throwsStateError);
    await db.collection('bills').doc('a').update({'total': 1});
    await expectLater(
        reprints.reprint('a', (_) async => fail('inconsistent print')),
        throwsStateError);
  });
}
