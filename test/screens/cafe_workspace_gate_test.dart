import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/screens/cafe_workspace_gate.dart';
import 'package:brewverse_cafe_manager/services/cafe_membership_service.dart';

void main() {
  group('CafeWorkspaceGate', () {
    testWidgets('revocation discards pushed workspace screens and dialogs',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _addMembership(firestore, 'user-a', 'cafe-a', 'owner');
      await tester.pumpWidget(MaterialApp(
        home: CafeWorkspaceGate(
          uid: 'user-a',
          membershipService: CafeMembershipService(firestore: firestore),
          homeBuilder: (context, membership, _) => Scaffold(
            body: TextButton(
              child: const Text('Open inventory'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                          body: TextButton(
                            child: const Text('Edit inventory'),
                            onPressed: () => showDialog<void>(
                              context: context,
                              useRootNavigator: false,
                              builder: (_) => const AlertDialog(
                                content: Text('Private inventory dialog'),
                              ),
                            ),
                          ),
                        )),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open inventory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit inventory'));
      await tester.pumpAndSettle();
      expect(find.text('Private inventory dialog'), findsOneWidget);
      await firestore
          .collection('cafe_members')
          .doc('user-a_cafe-a')
          .update({'status': 'revoked'});
      await tester.pumpAndSettle();
      expect(find.text('Private inventory dialog'), findsNothing);
      expect(find.text('Edit inventory'), findsNothing);
      expect(find.text('No active café access'), findsOneWidget);
    });

    testWidgets('changing user clears the previous selected workspace',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      await _addMembership(firestore, 'user-a', 'cafe-a', 'owner');
      await _addMembership(firestore, 'user-b', 'cafe-b', 'staff');
      final service = CafeMembershipService(firestore: firestore);
      Widget app(String uid) => MaterialApp(
              home: CafeWorkspaceGate(
            uid: uid,
            membershipService: service,
            homeBuilder: (_, membership, __) =>
                Text('Tenant: ${membership.cafeId}'),
          ));
      await tester.pumpWidget(app('user-a'));
      await tester.pumpAndSettle();
      expect(find.text('Tenant: cafe-a'), findsOneWidget);
      await tester.pumpWidget(app('user-b'));
      await tester.pumpAndSettle();
      expect(find.text('Tenant: cafe-a'), findsNothing);
      expect(find.text('Tenant: cafe-b'), findsOneWidget);
    });

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
