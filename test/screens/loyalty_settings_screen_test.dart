import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/screens/loyalty_settings_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _settings = <String, dynamic>{
  'enabled': true,
  'spendUnitMinor': 10000,
  'pointsPerSpendUnit': 4,
  'pointValueMinor': 100,
  'maxRedemptionPercent': 100,
  'bonusTiers': [
    {'minimumSpendMinor': 50000, 'points': 5},
    {'minimumSpendMinor': 100000, 'points': 10},
  ],
  'expiryMonths': 12,
  'reverseEarnedOnRefund': true,
  'restoreRedeemedOnRefund': true,
};

void main() {
  testWidgets('loads café loyalty policy and saves edited values for its owner',
      (tester) async {
    Map<String, dynamic>? savedSettings;
    final service = CafeFunctionsService(
      invoker: (name, data) async {
        if (name == 'getLoyaltySettings') return {'settings': _settings};
        if (name == 'saveLoyaltySettings') {
          savedSettings = Map<String, dynamic>.from(data['settings'] as Map);
          return {'settings': savedSettings};
        }
        return {};
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: LoyaltySettingsScreen(
        cafeId: 'cafe-a',
        role: CafeRole.owner,
        functionsService: service,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bonus tiers'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Expire after months'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Expire after months'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Save loyalty policy'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Save loyalty policy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save loyalty policy'));
    await tester.pumpAndSettle();

    expect(savedSettings?['spendUnitMinor'], 10000);
    expect(savedSettings?['bonusTiers'], _settings['bonusTiers']);
    expect(find.text('Loyalty policy saved.'), findsOneWidget);
  });

  testWidgets('does not allow a café manager to edit loyalty policy',
      (tester) async {
    final service = CafeFunctionsService(
      invoker: (_, __) async => {'settings': _settings},
    );
    await tester.pumpWidget(MaterialApp(
      home: LoyaltySettingsScreen(
        cafeId: 'cafe-a',
        role: CafeRole.manager,
        functionsService: service,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Only the café owner can edit loyalty rules.'),
        findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Save loyalty policy'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Save loyalty policy'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
