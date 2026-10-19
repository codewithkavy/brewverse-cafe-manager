import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/screens/cafe_workspace_gate.dart';
import 'package:brewverse_cafe_manager/services/cafe_membership_service.dart';

void main() {
  group('CafeWorkspaceGate', () {
    testWidgets('shows onboarding when the user has no active membership',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('cafe_members').doc('user-a_cafe-old').set({
        'uid': 'user-a',
        'cafeId': 'cafe-old',
        'role': 'owner',
        'status': 'revoked',
      });

      await tester.pumpWidget(MaterialApp(
        home: CafeWorkspaceGate(
          uid: 'user-a',
          membershipService: CafeMembershipService(firestore: firestore),
          homeBuilder: (_, membership, __) => Text(membership.cafeId),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No active café access'), findsOneWidget);
      expect(
          find.textContaining('Legacy records are not moved'), findsOneWidget);
      expect(find.text('Create café'), findsOneWidget);
    });

    testWidgets('opens a single active membership with its café ID',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _addMembership(firestore, 'user-a', 'cafe-a', 'owner');

      await tester.pumpWidget(MaterialApp(
        home: CafeWorkspaceGate(
          uid: 'user-a',
          membershipService: CafeMembershipService(firestore: firestore),
          homeBuilder: (_, membership, __) =>
              Text('Tenant: ${membership.cafeId}'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tenant: cafe-a'), findsOneWidget);
    });

    testWidgets('supports selecting and switching between active cafés',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _addMembership(firestore, 'user-a', 'cafe-a', 'owner');
      await _addMembership(firestore, 'user-a', 'cafe-b', 'staff');

      await tester.pumpWidget(MaterialApp(
        home: CafeWorkspaceGate(
          uid: 'user-a',
          membershipService: CafeMembershipService(firestore: firestore),
          homeBuilder: (context, membership, switchCafe) => Scaffold(
            body: Column(
              children: [
                Text('Tenant: ${membership.cafeId}'),
                TextButton(onPressed: switchCafe, child: const Text('Switch')),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Choose a café'), findsOneWidget);
      await tester.tap(find.text('cafe-b'));
      await tester.pumpAndSettle();
      expect(find.text('Tenant: cafe-b'), findsOneWidget);

      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();
      expect(find.text('Your café workspaces'), findsOneWidget);
      await tester.tap(find.text('cafe-a'));
      await tester.pumpAndSettle();
      expect(find.text('Tenant: cafe-a'), findsOneWidget);
    });
  });
}

Future<void> _addMembership(
  FakeFirebaseFirestore firestore,
  String uid,
  String cafeId,
  String role,
) =>
    firestore.collection('cafe_members').doc('${uid}_$cafeId').set({
      'uid': uid,
      'cafeId': cafeId,
      'role': role,
      'status': CafeMembershipStatus.active.name,
    });
