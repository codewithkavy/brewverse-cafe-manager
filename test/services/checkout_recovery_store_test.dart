import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brewverse_cafe_manager/services/checkout_recovery_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  PendingCheckout order() => PendingCheckout(
        id: 'stable-checkout-id',
        cart: {'coffee': 2},
        orderType: 'takeaway',
      );

  test('pending checkout survives recreation and retains its retry ID',
      () async {
    await DeviceCheckoutRecoveryStore(cafeId: 'a', uid: 'owner').save(order());
    final recovered =
        await DeviceCheckoutRecoveryStore(cafeId: 'a', uid: 'owner').load();
    expect(recovered.pending!.id, 'stable-checkout-id');
    expect(recovered.pending!.cart, {'coffee': 2});
  });

  test('pending orders cannot leak between cashiers or cafes', () async {
    await DeviceCheckoutRecoveryStore(cafeId: 'a', uid: 'owner').save(order());
    expect(
        (await DeviceCheckoutRecoveryStore(cafeId: 'b', uid: 'owner').load())
            .pending,
        isNull);
    expect(
        (await DeviceCheckoutRecoveryStore(cafeId: 'a', uid: 'staff').load())
            .pending,
        isNull);
  });

  test('confirmation clears pending state and preserves the receipt bill',
      () async {
    final store = DeviceCheckoutRecoveryStore(cafeId: 'a', uid: 'owner');
    await store.save(order());
    await store.confirm('saved-bill');
    final restored =
        await DeviceCheckoutRecoveryStore(cafeId: 'a', uid: 'owner').load();
    expect(restored.pending, isNull);
    expect(restored.lastBillId, 'saved-bill');
    await store.save(order());
    await store.reject();
    expect((await store.load()).lastBillId, 'saved-bill');
    expect((await store.load()).pending, isNull);
  });
}
