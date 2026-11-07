import 'package:brewverse_cafe_manager/screens/more_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings list stays compact and marks unavailable actions',
      (tester) async {
    tester.view.physicalSize = const Size(270, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: MoreScreen(cafeId: null)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account settings'), findsOneWidget);
    expect(find.text('Café team'), findsOneWidget);
    expect(find.text('Loyalty settings'), findsOneWidget);
    expect(find.text('Printer settings'), findsOneWidget);
    expect(find.text('Café profile'), findsOneWidget);
    expect(find.text('App preferences'), findsOneWidget);
    expect(find.text('Help & support'), findsOneWidget);
    expect(find.text('About BrewVerse'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(8));
    expect(tester.takeException(), isNull);
  });
}
