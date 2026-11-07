import 'package:brewverse_cafe_manager/services/cafe_functions_service.dart';
import 'package:brewverse_cafe_manager/models/stock_item.dart';
import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:brewverse_cafe_manager/services/stock_operation_store.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('pending stock key survives recreation and is isolated by identity/cafe',
      () async {
    final original = DeviceStockOperationStore(uid: 'owner', cafeId: 'cafe');
    final first = await original.obtain('payload');
    expect(
        await DeviceStockOperationStore(uid: 'owner', cafeId: 'cafe')
            .obtain('payload'),
        first);
    expect(
        await DeviceStockOperationStore(uid: 'other', cafeId: 'cafe')
            .obtain('payload'),
        isNot(first));
    expect(
        await DeviceStockOperationStore(uid: 'owner', cafeId: 'other')
            .obtain('payload'),
        isNot(first));
    await original.complete('payload', first);
    expect(await original.obtain('payload'), isNot(first));
  });
  test('concurrent store instances retain the same pending operation key',
      () async {
    final values = await Future.wait(List.generate(
        4,
        (_) => DeviceStockOperationStore(uid: 'owner', cafeId: 'cafe')
            .obtain('same')));
    expect(values.toSet().length, 1);
  });
  test(
      'lost add-stock response reuses durable key and later intentional update gets a fresh key',
      () async {
    final ids = <String>[];
    var fail = true;
    final functions = CafeFunctionsService(invoker: (_, data) async {
      ids.add(data['operationId'] as String);
      if (fail) throw Exception('Lost response after commit');
      return {};
    });
    CafeService service() => CafeService(
        cafeId: 'cafe',
        firestore: FakeFirebaseFirestore(),
        functionsService: functions,
        stockOperationStore:
            DeviceStockOperationStore(uid: 'owner', cafeId: 'cafe'));
    await expectLater(
        service().addStock(itemId: 'item', quantity: 2, reason: 'New stock'),
        throwsException);
    fail = false;
    await service().addStock(itemId: 'item', quantity: 2, reason: 'New stock');
    expect(ids[1], ids[0]);
    await service().addStock(itemId: 'item', quantity: 2, reason: 'New stock');
    expect(ids[2], isNot(ids[1]));
  });
  for (final method in ['createCafe', 'createStockItem']) {
    test('$method reuses a persisted operation key after a lost response',
        () async {
      final ids = <String>[];
      var fail = true;
      CafeFunctionsService functions() => CafeFunctionsService(
          operationStore: DeviceStockOperationStore(
              uid: 'owner', cafeId: 'creation-requests'),
          invoker: (name, data) async {
            ids.add(data['operationId'] as String);
            if (fail) throw Exception('Committed response lost');
            return method == 'createCafe'
                ? {'cafeId': 'cafe'}
                : {'stockItemId': 'item'};
          });
      Future<String> create() => method == 'createCafe'
          ? functions().createCafe(name: 'New café')
          : functions().createStockItem(
              cafeId: 'cafe',
              item: const StockItem(
                  id: '',
                  name: 'New stock',
                  category: 'ingredient',
                  unit: 'g',
                  quantity: 10,
                  minimumQuantity: 1,
                  purchasePricePerUnit: 0,
                  sellingPrice: 0));
      await expectLater(create(), throwsException);
      fail = false;
      await create();
      expect(ids[1], ids[0]);
      await create();
      expect(ids[2], isNot(ids[1]));
    });
  }
}
