import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/models/cafe_membership.dart';

void main() {
  group('CafeMembership.fromMap', () {
    test('parses an active owner membership', () {
      final membership = CafeMembership.fromMap({
        'uid': 'user-123',
        'cafeId': 'cafe-abc',
        'role': 'owner',
        'status': 'active',
      });

      expect(membership.uid, 'user-123');
      expect(membership.cafeId, 'cafe-abc');
      expect(membership.role, CafeRole.owner);
      expect(membership.status, CafeMembershipStatus.active);
      expect(membership.isActive, isTrue);
    });

    test('parses each supported role', () {
      for (final role in CafeRole.values) {
        final membership = CafeMembership.fromMap({
          'uid': 'user-123',
          'cafeId': 'cafe-abc',
          'role': role.name,
          'status': 'active',
        });

        expect(membership.role, role);
      }
    });

    test('only owners and managers can manage inventory', () {
      CafeMembership membershipFor(CafeRole role) => CafeMembership(
            uid: 'user-123',
            cafeId: 'cafe-abc',
            role: role,
            status: CafeMembershipStatus.active,
          );

      expect(membershipFor(CafeRole.owner).canManageInventory, isTrue);
      expect(membershipFor(CafeRole.manager).canManageInventory, isTrue);
      expect(membershipFor(CafeRole.staff).canManageInventory, isFalse);
    });

    test('revoked membership is not active', () {
      final membership = CafeMembership.fromMap({
        'uid': 'user-123',
        'cafeId': 'cafe-abc',
        'role': 'staff',
        'status': 'revoked',
      });

      expect(membership.isActive, isFalse);
    });

    test('rejects missing or empty user IDs', () {
      for (final uid in [null, '', '   ', 123]) {
        expect(
          () => CafeMembership.fromMap({
            'uid': uid,
            'cafeId': 'cafe-abc',
            'role': 'owner',
            'status': 'active',
          }),
          throwsFormatException,
        );
      }
    });

    test('rejects missing or empty café IDs', () {
      for (final cafeId in [null, '', '   ', 123]) {
        expect(
          () => CafeMembership.fromMap({
            'uid': 'user-123',
            'cafeId': cafeId,
            'role': 'owner',
            'status': 'active',
          }),
          throwsFormatException,
        );
      }
    });

    test('rejects unknown roles and statuses', () {
      expect(
        () => CafeMembership.fromMap({
          'uid': 'user-123',
          'cafeId': 'cafe-abc',
          'role': 'superadmin',
          'status': 'active',
        }),
        throwsFormatException,
      );

      expect(
        () => CafeMembership.fromMap({
          'uid': 'user-123',
          'cafeId': 'cafe-abc',
          'role': 'owner',
          'status': 'pending',
        }),
        throwsFormatException,
      );
    });

    test('serializes to the stable membership map shape', () {
      const membership = CafeMembership(
        uid: 'user-123',
        cafeId: 'cafe-abc',
        role: CafeRole.manager,
        status: CafeMembershipStatus.active,
      );

      expect(membership.toMap(), {
        'uid': 'user-123',
        'cafeId': 'cafe-abc',
        'role': 'manager',
        'status': 'active',
      });
    });
  });
}
