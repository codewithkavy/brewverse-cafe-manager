import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stock_item.dart';

/// Read-only data access for a single café tenant.
///
/// This prototype deliberately requires a café ID and filters every collection
/// query by it. Tenant-mode screens reach it through [CafeService], while
/// legacy mode remains available until a data migration is planned.
class TenantCafeDataService {
  TenantCafeDataService({
    required String cafeId,
    FirebaseFirestore? firestore,
  })  : cafeId = _validateCafeId(cafeId),
        _db = firestore ?? FirebaseFirestore.instance;

  final String cafeId;
  final FirebaseFirestore _db;

  Query<Map<String, dynamic>> _tenantQuery(String collection) =>
      _db.collection(collection).where('cafeId', isEqualTo: cafeId);

  Stream<List<StockItem>> watchStock() =>
      _tenantQuery('stock_items').snapshots().map((snapshot) {
        final items = snapshot.docs.map(StockItem.fromDoc).toList();
        items.sort((left, right) => left.name.compareTo(right.name));
        return items;
      });

  Stream<List<Map<String, dynamic>>> watchRecipes() =>
      _tenantQuery('product_recipes').snapshots().map((snapshot) {
        final recipes =
            snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
        recipes.sort((left, right) => (left['productId'] as String? ??
                left['id'] as String)
            .compareTo(right['productId'] as String? ?? right['id'] as String));
        return recipes;
      });

  Stream<List<Map<String, dynamic>>> watchRecentMovements({int limit = 100}) {
    _validateLimit(limit);
    return _tenantQuery('stock_movements')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList(growable: false));
  }

  Stream<List<Map<String, dynamic>>> watchRecentBills({int limit = 100}) {
    _validateLimit(limit);
    return _tenantQuery('bills')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList(growable: false));
  }

  Future<Map<String, dynamic>?> getBill(String billId) async {
    if (billId.trim().isEmpty || billId.contains('/')) {
      throw ArgumentError.value(billId, 'billId', 'Must be a document ID.');
    }
    final snapshot = await _db.collection('bills').doc(billId).get();
    final data = snapshot.data();
    if (data == null || data['cafeId'] != cafeId) return null;
    return {...data, 'id': snapshot.id};
  }

  static String _validateCafeId(String value) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError.value(
          value, 'cafeId', 'Must be a non-empty café ID.');
    }
    return value.trim();
  }

  static void _validateLimit(int limit) {
    if (limit < 1 || limit > 500) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 500.');
    }
  }
}
