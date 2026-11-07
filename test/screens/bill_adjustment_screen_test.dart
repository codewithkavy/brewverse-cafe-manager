import 'dart:async';

import 'package:brewverse_cafe_manager/models/cafe_membership.dart';
import 'package:brewverse_cafe_manager/screens/bill_adjustment_screen.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('manager confirms a refund and sends the requested amount',
      (tester) async {
    String? calledEndpoint;
    Map<String, dynamic>? sentData;
    final service = CafeFunctionsService(
      invoker: (name, data) async {
        calledEndpoint = name;
        sentData = data;
        return {
          'status': 'partially_refunded',
          'refundedMinor': 500,
          'duplicate': false,
        };
      },
    );
    await tester.pumpWidget(MaterialApp(
      home: BillAdjustmentScreen(
        cafeId: 'cafe-a',
        role: CafeRole.manager,
        functionsService: service,
      ),
    ));

    await tester.enterText(find.widgetWithText(TextField, 'Bill ID'), 'bill-a');
    await tester.enterText(
      find.widgetWithText(TextField, 'Refund amount'),
      '5.00',
    );
    await tester.enterText(
        find.widgetWithText(TextField, 'Reason'), 'Returned');
    await tester.tap(find.text('Issue refund'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund').last);
    await tester.pumpAndSettle();

    expect(calledEndpoint, 'refundBill');
    expect(sentData?['cafeId'], 'cafe-a');
    expect(sentData?['billId'], 'bill-a');
    expect(sentData?['amountMinor'], 500);
    expect(sentData?['reason'], 'Returned');
    expect(find.text('Refunded ₹5.00'), findsOneWidget);
  });

  for (final scenario in [
    (status: 'void', amount: 16000, message: 'Voided ₹160.00'),
    (status: 'refunded', amount: 8000, message: 'Refunded ₹80.00'),
  ]) {
    testWidgets('confirmation follows backend ${scenario.status} result',
        (tester) async {
      final service = CafeFunctionsService(
          invoker: (name, data) async => {
                'status': scenario.status,
                'refundedMinor': scenario.amount,
                'duplicate': false,
              });
      await tester.pumpWidget(MaterialApp(
          home: BillAdjustmentScreen(
        cafeId: 'cafe-a',
        role: CafeRole.manager,
        functionsService: service,
      )));
      await tester.enterText(
          find.widgetWithText(TextField, 'Bill ID'), 'bill-a');
      await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Test');
      // The backend result controls the message even if a different action was requested.
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void bill'));
      await tester.pumpAndSettle();
      expect(find.text(scenario.message), findsOneWidget);
    });
  }

  for (final isVoid in [false, true]) {
    testWidgets(
        '${isVoid ? "void" : "refund"} double taps and failed-response retry reuse one request',
        (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final requests = <Map<String, dynamic>>[];
      final service = CafeFunctionsService(invoker: (name, data) {
        requests.add(Map<String, dynamic>.from(data));
        if (requests.length == 1) return pending.future;
        return Future.value({
          'status': isVoid ? 'void' : 'refunded',
          'refundedMinor': 8000,
          'duplicate': true
        });
      });
      await tester.pumpWidget(MaterialApp(
          home: BillAdjustmentScreen(
              cafeId: 'cafe-a',
              role: CafeRole.manager,
              functionsService: service)));
      await tester.enterText(
          find.widgetWithText(TextField, 'Bill ID'), 'bill-a');
      await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Test');
      await tester.enterText(
          find.widgetWithText(TextField, 'Refund amount'), '80');
      final action =
          isVoid ? find.byType(OutlinedButton) : find.text('Issue refund');
      final confirm = isVoid ? 'Void bill' : 'Refund';
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text(confirm).last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(action, warnIfMissed: false);
      await tester.pump();
      expect(requests.length, 1);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Issue refund'))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<OutlinedButton>(
                  find.widgetWithText(OutlinedButton, 'Void remaining bill'))
              .onPressed,
          isNull);
      // The server may have committed before the response was lost.
      pending.completeError(Exception('Response lost'));
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text(confirm).last);
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests[1], requests[0]);
      expect(find.text('This adjustment was already applied.'), findsOneWidget);
    });
  }

  testWidgets('staff cannot issue refunds or void bills', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: BillAdjustmentScreen(
        cafeId: 'cafe-a',
        role: CafeRole.staff,
      ),
    ));

    expect(find.text('Only café owners and managers can adjust bills.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
  });
}
