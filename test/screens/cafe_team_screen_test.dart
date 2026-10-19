import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/screens/cafe_team_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';

void main() {
  testWidgets('shows a compact empty state and gates add-member UI by role',
      (tester) async {
    tester.view.physicalSize = const Size(270, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = CafeFunctionsService(
      invoker: (name, data) async => {
        'memberships': const <Map<String, dynamic>>[],
        'hasMore': false,
        'nextPageToken': null,
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: CafeTeamScreen(
        cafeId: 'cafe-a',
        callerRole: CafeRole.owner,
        currentUid: 'owner-a',
        functionsService: service,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No café members found'), findsOneWidget);
    expect(find.byTooltip('Add or restore member access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff cannot see the add-member action', (tester) async {
    final service = CafeFunctionsService(
      invoker: (name, data) async => {
        'memberships': [
          {
            'uid': 'staff-a',
            'cafeId': 'cafe-a',
            'role': 'staff',
            'status': 'active',
          },
        ],
        'hasMore': false,
        'nextPageToken': null,
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: CafeTeamScreen(
        cafeId: 'cafe-a',
        callerRole: CafeRole.staff,
        currentUid: 'staff-a',
        functionsService: service,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('staff-a'), findsOneWidget);
    expect(find.byTooltip('Add or restore member access'), findsNothing);
  });

  testWidgets('loads additional café team membership pages', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final service = CafeFunctionsService(
      invoker: (name, data) async {
        expect(name, 'listCafeMemberships');
        calls.add(data);
        if (data['pageToken'] == null) {
          return {
            'memberships': [
              {
                'uid': 'owner-a',
                'cafeId': 'cafe-a',
                'role': 'owner',
                'status': 'active',
              },
            ],
            'hasMore': true,
            'nextPageToken': 'cursor-a',
          };
        }
        return {
          'memberships': [
            {
              'uid': 'staff-b',
              'cafeId': 'cafe-a',
              'role': 'staff',
              'status': 'active',
            },
          ],
          'hasMore': false,
          'nextPageToken': null,
        };
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: CafeTeamScreen(
        cafeId: 'cafe-a',
        callerRole: CafeRole.owner,
        currentUid: 'owner-a',
        functionsService: service,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('owner-a'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(calls, [
      {'cafeId': 'cafe-a'},
      {'cafeId': 'cafe-a', 'pageToken': 'cursor-a'},
    ]);
    expect(find.text('owner-a'), findsOneWidget);
    expect(find.text('staff-b'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });
}
