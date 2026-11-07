import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brewverse_cafe_manager/screens/thermal_printer_dialog.dart';
import 'package:brewverse_cafe_manager/services/bluetooth_receipt_transport.dart';
import 'package:brewverse_cafe_manager/services/printer_settings_store.dart';

void main() {
  testWidgets('saved Classic profile exposes test action on a narrow phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesPrinterSettingsStore();
    await store.save(
        'cafe',
        const ReceiptPrinterSettings(
            address: 'AA',
            name: 'Counter',
            transport: ReceiptTransport.classic));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            ClassicPrinterBridge.channel, (call) async => []);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ClassicPrinterBridge.channel, null));
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ThermalPrinterDialog.settings(
                cafeId: 'cafe', settingsStore: store))));
    await tester.pumpAndSettle();
    expect(find.text('Print Test Receipt'), findsOneWidget);
    expect(find.text('Classic SPP candidate'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
