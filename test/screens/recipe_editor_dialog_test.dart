import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/screens/recipe_editor_dialog.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const burger = StockItem(
  id: 'veg-burger',
  name: 'veg burger',
  category: 'finished',
  unit: 'piece',
  quantity: 0,
  minimumQuantity: 0,
  purchasePricePerUnit: 0,
  sellingPrice: 80,
);

class _DeniedRecipeService extends CafeService {
  _DeniedRecipeService()
      : super(firestore: FakeFirebaseFirestore(), cafeId: 'a');
  @override
  Future<Map<String, dynamic>?> loadRecipe(String productId) async =>
      throw FirebaseException(
          plugin: 'cloud_firestore', code: 'permission-denied');
}

Future<void> openEditor(WidgetTester tester, CafeService service) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => RecipeEditorDialog(
                          service: service, product: burger)),
                  child: const Text('Manage Recipe'))))));
  await tester.tap(find.text('Manage Recipe'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first recipe selects burger bun, saves quantity, and reopens',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('stock_items').doc('burger-bun').set({
      'cafeId': 'a',
      'name': 'burger bun',
      'category': 'ingredient',
      'unit': 'piece',
      'quantity': 100,
    });
    await db
        .collection('stock_items')
        .doc(burger.id)
        .set({...burger.toMap(), 'cafeId': 'a'});
    Map<String, dynamic>? saved;
    final service = CafeService(
        firestore: db,
        cafeId: 'a',
        functionsService: CafeFunctionsService(invoker: (name, data) async {
          expect(name, 'saveRecipe');
          saved = data;
          await db.collection('product_recipes').doc(burger.id).set(data);
          return {};
        }));
    await openEditor(tester, service);
    expect(find.text('Could not load the saved recipe.'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save recipe'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    expect(find.text('burger bun'), findsOneWidget);
    expect(find.text('veg burger'),
        findsNothing); // Finished products are excluded.
    await tester.enterText(find.byType(TextFormField), '2');
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(saved!['ingredients'], [
      {
        'stockItemId': 'burger-bun',
        'stockItemName': 'burger bun',
        'quantity': 2.0,
        'unit': 'piece'
      },
    ]);
    expect(find.byType(RecipeEditorDialog), findsNothing);
    await tester.tap(find.text('Manage Recipe'));
    await tester.pumpAndSettle();
    expect(find.text('burger bun'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '2.0');
    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('Save recipe'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive quantity'), findsOneWidget);
    expect(find.byType(RecipeEditorDialog), findsOneWidget);
  });

  testWidgets('permission failures do not become an empty editable recipe',
      (tester) async {
    await openEditor(tester, _DeniedRecipeService());
    expect(find.text('Could not load the saved recipe.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Save recipe'))
            .onPressed,
        isNull);
  });
}
