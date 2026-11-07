import '../firebase_runtime_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cafe_membership.dart';

class CafeMembershipService {
  CafeMembershipService({FirebaseFirestore? firestore})
      : _db = firestore ?? BrewVerseFirebaseConfig.firestore;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _memberships =>
      _db.collection('cafe_members');

  /// Reads only membership records for [uid]. The caller must pass the
  /// Firebase Auth UID; Firestore rules independently enforce that boundary.
  Stream<List<CafeMembership>> watchForUser(String uid) {
    _validateIdentity(uid, 'User ID');
    return _memberships
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final memberships = snapshot.docs.map((document) {
        final membership = CafeMembership.fromMap(document.data());
        if (membership.uid != uid) {
          throw const FormatException(
            'Membership user does not match the requested user.',
          );
        }
        if (document.id != _documentId(uid, membership.cafeId)) {
          throw FormatException(
            'Membership document ID does not match its café: ${document.id}',
          );
        }
        return membership;
      }).toList()
        ..sort((left, right) => left.cafeId.compareTo(right.cafeId));
      return memberships;
    });
  }

  Future<CafeMembership?> getForUserAndCafe({
    required String uid,
    required String cafeId,
  }) async {
    _validateIdentity(uid, 'User ID');
    _validateIdentity(cafeId, 'Café ID');
    final document = await _memberships.doc(_documentId(uid, cafeId)).get();
    if (!document.exists) return null;

    final membership = CafeMembership.fromMap(document.data()!);
    if (membership.uid != uid || membership.cafeId != cafeId) {
      throw const FormatException(
        'Membership path and document identity do not match.',
      );
    }
    return membership;
  }

  static String _documentId(String uid, String cafeId) => '${uid}_$cafeId';

  static void _validateIdentity(String value, String label) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$label cannot be empty.');
    }
  }
}
