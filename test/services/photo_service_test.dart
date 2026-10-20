import 'dart:typed_data';
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

    test('uses matching extensions for PNG and WebP uploads', () {
      expect(
        PhotoService.storagePath(
          cafeId: 'cafe-a',
          itemId: 'espresso',
          uploadId: 'abc123',
          extension: 'png',
        ),
        'cafes/cafe-a/products/espresso_abc123.png',
      );
      expect(
        PhotoService.storagePath(
          cafeId: 'cafe-a',
          itemId: 'espresso',
          uploadId: 'abc123',
          extension: 'webp',
        ),
        'cafes/cafe-a/products/espresso_abc123.webp',
      );
      expect(
        () => PhotoService.storagePath(
          cafeId: 'cafe-a',
          itemId: 'espresso',
          extension: 'exe',
        ),
        throwsArgumentError,
      );
    });

    test('validates image signatures instead of trusting file names', () {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]);
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      ]);
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0,
        0x57, 0x45, 0x42, 0x50,
      ]);
      expect(PhotoService.detectContentType(jpeg), 'image/jpeg');
      expect(PhotoService.detectContentType(png), 'image/png');
      expect(PhotoService.detectContentType(webp), 'image/webp');
      expect(
        SelectedProductPhoto(
          bytes: png,
          contentType: 'image/png',
        ).extension,
        'png',
      );
      expect(
        () => PhotoService.detectContentType(
          Uint8List.fromList([0, 1, 2, 3]),
        ),
        throwsStateError,
      );
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
