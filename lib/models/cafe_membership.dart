/// Membership of a Firebase Auth user in a single BrewVerse café.
///
/// This model describes membership data only. It does not grant access by
/// itself; Firestore/Storage Security Rules and trusted backend code must
/// enforce authorization.
enum CafeRole {
  owner,
  manager,
  staff;

  bool get canManageInventory => this == owner || this == manager;

  static CafeRole parse(Object? value) {
    return CafeRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => throw FormatException('Unknown café role: $value'),
    );
  }
}

enum CafeMembershipStatus {
  active,
  revoked;

  static CafeMembershipStatus parse(Object? value) {
    return CafeMembershipStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () =>
          throw FormatException('Unknown café membership status: $value'),
    );
  }
}

class CafeMembership {
  const CafeMembership({
    required this.uid,
    required this.cafeId,
    required this.role,
    required this.status,
  });

  final String uid;
  final String cafeId;
  final CafeRole role;
  final CafeMembershipStatus status;

  bool get isActive => status == CafeMembershipStatus.active;

  bool get canManageInventory => role.canManageInventory;

  factory CafeMembership.fromMap(Map<String, dynamic> data) {
    final uid = data['uid'];
    final cafeId = data['cafeId'];

    if (uid is! String || uid.trim().isEmpty) {
      throw const FormatException('Membership requires a non-empty uid.');
    }
    if (cafeId is! String || cafeId.trim().isEmpty) {
      throw const FormatException('Membership requires a non-empty cafeId.');
    }

    return CafeMembership(
      uid: uid,
      cafeId: cafeId,
      role: CafeRole.parse(data['role']),
      status: CafeMembershipStatus.parse(data['status']),
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'cafeId': cafeId,
        'role': role.name,
        'status': status.name,
      };
}
