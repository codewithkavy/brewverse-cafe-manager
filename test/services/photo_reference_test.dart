import 'package:brewverse_cafe_manager/services/cafe_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('photo updates succeed only for the current document photo', () async {
    final firestore = FakeFirebaseFirestore();
    final item = firestore.collection('stock_items').doc('espresso');
    await item.set({'cafeId': 'cafe-a', 'photoUrl': 'old-photo'});
    final service = CafeService(firestore: firestore, cafeId: 'cafe-a');

    await service.replacePhotoUrl(
      itemId: 'espresso',
      expectedUrl: 'old-photo',
      newUrl: 'new-photo',
    );

    expect((await item.get()).data()?['photoUrl'], 'new-photo');
    await expectLater(
      service.replacePhotoUrl(
        itemId: 'espresso',
        expectedUrl: 'old-photo',
        newUrl: 'stale-photo',
      ),
      throwsStateError,
    );
    expect((await item.get()).data()?['photoUrl'], 'new-photo');
  });

  test('photo update cannot cross café boundaries', () async {
    final firestore = FakeFirebaseFirestore();
    final item = firestore.collection('stock_items').doc('espresso');
    await item.set({'cafeId': 'cafe-b', 'photoUrl': ''});
    final service = CafeService(firestore: firestore, cafeId: 'cafe-a');

    await expectLater(
      service.replacePhotoUrl(
        itemId: 'espresso',
        expectedUrl: '',
        newUrl: 'wrong-cafe-photo',
      ),
      throwsStateError,
    );
    expect((await item.get()).data()?['photoUrl'], '');
  });

  test('missing inventory documents cannot receive photos', () async {
    final firestore = FakeFirebaseFirestore();
    final service = CafeService(firestore: firestore, cafeId: 'cafe-a');
    await expectLater(
      service.replacePhotoUrl(
        itemId: 'missing',
        expectedUrl: '',
        newUrl: 'missing-photo',
      ),
      throwsStateError,
    );
  });
}
