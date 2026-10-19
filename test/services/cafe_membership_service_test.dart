import 'package:brewverse_cafe_manager/services/cafe_membership_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CafeMembershipService', () {
    test('watches only the requested user and sorts memberships by café ID',
        () async {
      final db = FakeFirebaseFirestore();
      final service = CafeMembershipService(firestore: db);
      await db.collection('cafe_members').doc('user-1_cafe-z').set({
        'uid': 'user-1',
        'cafeId': 'cafe-z',
        'role': 'staff',
        'status': 'revoked',
      });
      await db.collection('cafe_members').doc('user-1_cafe-a').set({
        'uid': 'user-1',
        'cafeId': 'cafe-a',
        'role': 'owner',
        'status': 'active',
      });
      await db.collection('cafe_members').doc('user-2_cafe-a').set({
        'uid': 'user-2',
        'cafeId': 'cafe-a',
        'role': 'manager',
        'status': 'active',
      });

      final memberships = await service.watchForUser('user-1').first;

      expect(memberships.map((membership) => membership.cafeId), [
        'cafe-a',
        'cafe-z',
      ]);
      expect(
          memberships.map((membership) => membership.isActive), [true, false]);
    });

    test('returns null when the user has no membership for the café', () async {
      final service = CafeMembershipService(firestore: FakeFirebaseFirestore());

      expect(
        await service.getForUserAndCafe(uid: 'user-1', cafeId: 'cafe-a'),
        isNull,
      );
    });

    test('validates the identity at the membership document path', () async {
      final db = FakeFirebaseFirestore();
      final service = CafeMembershipService(firestore: db);
      await db.collection('cafe_members').doc('user-1_cafe-a').set({
        'uid': 'user-1',
        'cafeId': 'cafe-b',
        'role': 'owner',
        'status': 'active',
      });

      await expectLater(
        service.getForUserAndCafe(uid: 'user-1', cafeId: 'cafe-a'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed membership paths in watched results', () async {
      final db = FakeFirebaseFirestore();
      final service = CafeMembershipService(firestore: db);
      await db.collection('cafe_members').doc('wrong-path').set({
        'uid': 'user-1',
        'cafeId': 'cafe-a',
        'role': 'owner',
        'status': 'active',
      });

      await expectLater(
        service.watchForUser('user-1').first,
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty user or café IDs', () {
      final service = CafeMembershipService(firestore: FakeFirebaseFirestore());
      expect(() => service.watchForUser(' '), throwsArgumentError);
      expect(
        () => service.getForUserAndCafe(uid: 'user-1', cafeId: ' '),
        throwsArgumentError,
      );
    });
  });
}
