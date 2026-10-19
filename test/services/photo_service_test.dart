import 'package:flutter_test/flutter_test.dart';
import 'package:brewverse_cafe_manager/services/photo_service.dart';

void main() {
  group('PhotoService.storagePath', () {
    test('places product images beneath the selected café', () {
      expect(
        PhotoService.storagePath(cafeId: 'cafe-a', itemId: 'espresso'),
        'cafes/cafe-a/products/espresso.jpg',
      );
    });

    test('supports unique photo uploads without leaving the café path', () {
      expect(
        PhotoService.storagePath(
          cafeId: 'cafe-a',
          itemId: 'espresso',
          uploadId: '12345',
        ),
        'cafes/cafe-a/products/espresso_12345.jpg',
      );
      expect(PhotoService.maximumPhotoSizeBytes, 5 * 1024 * 1024);
      expect(
        () =>
            PhotoService.validatePhotoSize(PhotoService.maximumPhotoSizeBytes),
        returnsNormally,
      );
      expect(
        () => PhotoService.validatePhotoSize(
            PhotoService.maximumPhotoSizeBytes + 1),
        throwsStateError,
      );
      expect(() => PhotoService.validatePhotoSize(0), throwsStateError);
    });

    test('rejects empty or path-injecting identifiers', () {
      expect(
        () => PhotoService.storagePath(cafeId: '', itemId: 'espresso'),
        throwsArgumentError,
      );
      expect(
        () => PhotoService.storagePath(cafeId: 'cafe-a', itemId: '../other'),
        throwsArgumentError,
      );
      expect(
        () => PhotoService.storagePath(
          cafeId: 'cafe-a',
          itemId: 'espresso',
          uploadId: '../other',
        ),
        throwsArgumentError,
      );
    });
  });
}
