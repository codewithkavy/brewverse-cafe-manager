import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:brewverse_cafe_manager/main.dart' as app;
import 'package:brewverse_cafe_manager/firebase_runtime_config.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_membership_service.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native registration creates cafe, owner access, stock and bill',
      (tester) async {
    expect(BrewVerseFirebaseConfig.useEmulators, isTrue);
    await app.main();
    final firebase = BrewVerseFirebaseConfig.app;
    expect(firebase.name, BrewVerseFirebaseConfig.localAppName);
    expect(firebase.options.projectId, 'brewverse-security-tests');
    expect(BrewVerseFirebaseConfig.auth.app.name, firebase.name);
    expect(BrewVerseFirebaseConfig.firestore.app.name, firebase.name);
    expect(BrewVerseFirebaseConfig.functions.app.name, firebase.name);
    expect(BrewVerseFirebaseConfig.storage.app.name, firebase.name);

    final runId = DateTime.now().microsecondsSinceEpoch.toString();
    final credential =
        await BrewVerseFirebaseConfig.auth.createUserWithEmailAndPassword(
      email: 'phone-integration-$runId@example.test',
      password: 'local-only-test-password',
    );
    final uid = credential.user!.uid;
    try {
      final functions = CafeFunctionsService();
      final cafeId = await functions.createCafe(name: 'Phone test $runId');
      final memberships = await CafeMembershipService()
          .watchForUser(uid)
          .firstWhere((items) => items.any((item) => item.cafeId == cafeId))
          .timeout(const Duration(seconds: 30));
      final owner = memberships.singleWhere((item) => item.cafeId == cafeId);
      expect(owner.isActive, isTrue);
      expect(owner.role.name, 'owner');
      final productId = await functions.createStockItem(
        cafeId: cafeId,
        item: const StockItem(
          id: '',
          name: 'Integration bottled water',
          category: 'finished',
          stockMode: 'direct',
          unit: 'piece',
          quantity: 5,
          minimumQuantity: 1,
          purchasePricePerUnit: 5,
          sellingPrice: 10,
        ),
      );
      final billId = await functions.checkout(
        cafeId: cafeId,
        checkoutId: 'phone-$runId',
        cart: {productId: 2},
        orderType: 'takeaway',
      );
      final db = BrewVerseFirebaseConfig.firestore;
      final bill = await db
          .collection('bills')
          .doc(billId)
          .get(const GetOptions(source: Source.server));
      expect(bill.data()!['cafeId'], cafeId);
      expect(bill.data()!['total'], 20);
      final stock = await CafeService(cafeId: cafeId)
          .watchStock()
          .firstWhere((items) =>
              items.any((item) => item.id == productId && item.quantity == 3))
          .timeout(const Duration(seconds: 30));
      expect(stock.singleWhere((item) => item.id == productId).quantity, 3);
      // A retry must return the same bill and must not deduct twice.
      expect(
          await functions.checkout(
              cafeId: cafeId,
              checkoutId: 'phone-$runId',
              cart: {productId: 2},
              orderType: 'takeaway'),
          billId);
      await tester.pumpAndSettle();
      expect(find.text('No active café access'), findsNothing);
    } finally {
      // Keep synthetic records for diagnosis; never clear user/emulator data.
      await BrewVerseFirebaseConfig.auth.signOut();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
