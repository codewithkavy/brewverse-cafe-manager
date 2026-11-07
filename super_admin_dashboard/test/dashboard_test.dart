import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_super_admin/backend.dart';
import 'package:brewverse_super_admin/dashboard.dart';
import 'package:brewverse_super_admin/main.dart';

class FakeApi implements AdminApi {
  bool deny = false;
  @override
  Future<Map<String, dynamic>> call(
    String name, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (deny) throw Exception('Denied');
    if (name == 'adminOverview') {
      return {
        'counts': {
          'total': 1,
          'active': 1,
          'grace': 0,
          'expired': 0,
          'suspended': 0,
          'pending': 0,
          'revenueMinor': 99900,
        },
        'settings': {
          'monthlyPriceMinor': 99900,
          'graceDays': 2,
          'enforcementEnabled': true,
          'revision': 1,
        },
      };
    }
    if (name == 'adminListCafes') {
      return {
        'cafes': [
          {
            'id': 'cafe-a',
            'name': 'Sample Cafe',
            'ownerUid': 'owner-a',
            'status': 'active',
            'subscription': {'expiresAt': '2026-11-22T00:00:00Z'},
          },
        ],
        'nextCursor': null,
      };
    }
    return {};
  }
}

void main() {
  testWidgets(
    'overview fits laptop and mobile, navigation and cafe search work',
    (tester) async {
      for (final width in [1280.0, 390.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            home: Dashboard(api: FakeApi(), onSignOut: () async {}),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Recorded revenue'), findsOneWidget);
        expect(find.text('₹999.00'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cafés').first);
        await tester.pumpAndSettle();
        expect(find.text('Sample Cafe'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'does not exist');
        await tester.pumpAndSettle();
        expect(find.text('Sample Cafe'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets('payment confirmation is disabled until manual verification', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EntryDialog(
            title: 'Payment',
            fields: [EntryField('reference', 'Reference')],
            notice: 'Verify externally',
            verification: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    FilledButton button() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Complete all fields.'), findsOneWidget);
  });
  testWidgets('backend rejection never displays the dashboard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthorizationGate(api: FakeApi()..deny = true)),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Administrator access could not be verified.'),
      findsOneWidget,
    );
    expect(find.text('Recorded revenue'), findsNothing);
  });
}
