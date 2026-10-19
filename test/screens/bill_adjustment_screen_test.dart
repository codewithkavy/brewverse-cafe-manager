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
    expect(find.text('partially_refunded · refunded ₹5.00'), findsOneWidget);
  });

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
