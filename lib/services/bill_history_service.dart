import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_runtime_config.dart';
import '../models/saved_bill.dart';
import 'server_connection.dart';

enum BillSearchKind { billId, phone }

class BillHistoryFilter {
  const BillHistoryFilter(
      {this.search = '',
      this.kind = BillSearchKind.billId,
      this.start,
      this.endExclusive});
  final String search;
  final BillSearchKind kind;
  final DateTime? start;
  final DateTime? endExclusive;
}

class BillHistoryPage {
  const BillHistoryPage(this.bills,
      {this.cursor, this.hasMore = false, this.fromCache = false});
  final List<SavedBill> bills;
  final Object? cursor;
  final bool hasMore;
  final bool fromCache;
}

abstract interface class BillHistoryRepository {
  String get cafeId;
  Future<BillHistoryPage> load(
      {required BillHistoryFilter filter, Object? cursor});
  Future<SavedBill?> get(String billId);
}

/// Read-only and server-verified. Firestore rules enforce active membership.
class FirestoreBillHistoryRepository implements BillHistoryRepository {
  FirestoreBillHistoryRepository(
      {required this.cafeId, FirebaseFirestore? firestore, this.pageSize = 25})
      : _db = firestore ?? BrewVerseFirebaseConfig.firestore {
    if (cafeId.trim().isEmpty || cafeId.contains('/')) {
      throw ArgumentError('A café workspace is required.');
    }
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError('Invalid page size.');
    }
  }
  @override
  final String cafeId;
  final FirebaseFirestore _db;
  final int pageSize;
  Query<Map<String, dynamic>> get _query =>
      _db.collection('bills').where('cafeId', isEqualTo: cafeId);

  @override
  Future<SavedBill?> get(String billId) async {
    if (billId.trim().isEmpty || billId.contains('/')) {
      throw ArgumentError('Enter a complete bill ID.');
    }
    // Rules authorize the document before it is returned. A second workspace
    // check also isolates users who belong to multiple cafés. Missing/denied
    // IDs have the same result, so searching cannot reveal another tenant.
    try {
      final ref = _db.collection('bills').doc(billId);
      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
      } catch (error) {
        if (!isOfflineReadFailure(error)) rethrow;
        ServerConnection.instance.markUnavailable();
        doc = await ref.get(const GetOptions(source: Source.cache));
      }
      final data = doc.data();
      if (data == null || data['cafeId'] != cafeId) return null;
      return SavedBill(doc.id, data, isFromCache: doc.metadata.isFromCache);
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  @override
  Future<BillHistoryPage> load(
      {required BillHistoryFilter filter, Object? cursor}) async {
    final search = filter.search.trim();
    if (filter.start != null &&
        filter.endExclusive != null &&
        !filter.start!.isBefore(filter.endExclusive!)) {
      throw ArgumentError('Choose a valid date range.');
    }
    if (search.isNotEmpty && filter.kind == BillSearchKind.billId) {
      final bill = await get(search);
      final date = bill?.createdAt;
      final inRange = (filter.start == null ||
              (date != null && !date.isBefore(filter.start!))) &&
          (filter.endExclusive == null ||
              (date != null && date.isBefore(filter.endExclusive!)));
      return BillHistoryPage(bill == null || !inRange ? [] : [bill],
          fromCache: bill?.isFromCache ?? false);
    }
    var query = _query;
    if (search.isNotEmpty) {
      final phone = search.replaceAll(RegExp(r'[\s()\-]'), '');
      if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
        throw ArgumentError('Use the full customer phone with country code.');
      }
      query = query.where('customerPhone', isEqualTo: phone);
    }
    if (filter.start != null) {
      query = query.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(filter.start!));
    }
    if (filter.endExclusive != null) {
      query = query.where('createdAt',
          isLessThan: Timestamp.fromDate(filter.endExclusive!));
    }
    query = query
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true);
    if (cursor != null) {
      if (cursor is! DocumentSnapshot<Map<String, dynamic>> ||
          cursor.data()?['cafeId'] != cafeId) {
        throw ArgumentError('Invalid bill history cursor.');
      }
      query = query.startAfterDocument(cursor);
    }
    final pageQuery = query.limit(pageSize + 1);
    QuerySnapshot<Map<String, dynamic>> result;
    try {
      result = await pageQuery
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      if (!isOfflineReadFailure(error)) rethrow;
      ServerConnection.instance.markUnavailable();
      result = await pageQuery.get(const GetOptions(source: Source.cache));
    }
    final docs = result.docs.take(pageSize).toList();
    if (docs.any((doc) => doc.data()['cafeId'] != cafeId)) {
      throw StateError('Bill workspace mismatch.');
    }
    return BillHistoryPage(
        docs
            .map((d) => SavedBill(d.id, d.data(),
                isFromCache: result.metadata.isFromCache))
            .toList(),
        cursor: docs.isEmpty ? null : docs.last,
        hasMore: result.docs.length > pageSize,
        fromCache: result.metadata.isFromCache);
  }
}
