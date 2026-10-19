import 'dart:ui' show SemanticsAction, Tristate;

import 'package:brewverse_cafe_manager/theme/app_theme.dart';
import 'package:brewverse_cafe_manager/widgets/cafe_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destinations = ['Home', 'Inventory', 'Billing', 'Loyalty', 'More'];

void main() {
  testWidgets('reference navigation has compact accessible phone targets',
      (tester) async {
    _phoneViewport(tester);
    final semantics = tester.ensureSemantics();
    try {
      await _pumpNavigation(tester, referenceStyle: true);

      final navigation = find.byType(CafeBottomNavigation);
      expect(tester.getSize(navigation), const Size(278, 48));
      expect(find.byType(NavigationBar), findsNothing);
      for (final entry in _destinations.indexed) {
        final destination = find.bySemanticsLabel(entry.$2);
        expect(destination, findsOneWidget);
        final data = tester.getSemantics(destination).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue, reason: entry.$2);
        expect(data.flagsCollection.isSelected,
            entry.$1 == 0 ? Tristate.isTrue : Tristate.isFalse,
            reason: entry.$2);
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: entry.$2);
        expect(tester.getSize(destination).width, greaterThanOrEqualTo(44),
            reason: entry.$2);
        expect(tester.getSize(destination).height, greaterThanOrEqualTo(44),
            reason: entry.$2);
        expect(find.text(entry.$2).hitTestable(), findsOneWidget);
        expect(tester.widget<Text>(find.text(entry.$2)).style?.fontSize, 9);
      }
      final icons = tester.widgetList<Icon>(
        find.descendant(of: navigation, matching: find.byType(Icon)),
      );
      expect(icons.length, 5);
      expect(icons.every((icon) => icon.size == 18), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reference selection invokes each existing destination callback',
      (tester) async {
    _phoneViewport(tester);
    final calls = <int>[];
    var selected = 0;

    await _pumpNavigation(tester,
        referenceStyle: true, selectedIndex: selected, onSelected: calls.add);
    for (var index = 0; index < _destinations.length; index++) {
      await tester.tap(find.text(_destinations[index]));
      await tester.pumpAndSettle();
      expect(calls.last, index);
      expect(calls.length, index + 1);
    }

    selected = 3;
    await _pumpNavigation(tester,
        referenceStyle: true, selectedIndex: selected, onSelected: calls.add);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Loyalty'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Home'))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      expect(calls.length, 5,
          reason: 'Rebuilding the selected state must not invoke a callback');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('reference navigation grows for enlarged phone text',
      (tester) async {
    _phoneViewport(tester);
    await _pumpNavigation(tester,
        referenceStyle: true, scaler: const TextScaler.linear(1.6));

    final navigation = tester.getRect(find.byType(CafeBottomNavigation));
    expect(navigation.height, greaterThan(48));
    expect(navigation.width, 278);
    for (final label in _destinations) {
      final destination = find.text(label);
      final bounds = tester.getRect(destination);
      expect(destination.hitTestable(), findsOneWidget);
      expect(bounds.left, greaterThanOrEqualTo(navigation.left), reason: label);
      expect(bounds.right, lessThanOrEqualTo(navigation.right), reason: label);
      expect(bounds.top, greaterThanOrEqualTo(navigation.top), reason: label);
      expect(bounds.bottom, lessThanOrEqualTo(navigation.bottom),
          reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('default navigation retains its existing Material presentation',
      (tester) async {
    _phoneViewport(tester);
    var selected = -1;
    await _pumpNavigation(tester,
        selectedIndex: 2, onSelected: (index) => selected = index);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    final materialNavigation = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(materialNavigation.selectedIndex, 2);
    expect(tester.getSize(find.byType(CafeBottomNavigation)).height, 64);
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });
}

void _phoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(278, 650);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpNavigation(
  WidgetTester tester, {
  bool referenceStyle = false,
  int selectedIndex = 0,
  ValueChanged<int>? onSelected,
  TextScaler scaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.emeraldLight,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: child!,
    ),
    home: Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: CafeBottomNavigation(
        referenceStyle: referenceStyle,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected ?? (_) {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
