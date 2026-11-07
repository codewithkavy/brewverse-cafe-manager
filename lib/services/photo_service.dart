import '../firebase_runtime_config.dart';
import 'server_connection.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// A locally selected image, validated before any storage write.
class SelectedProductPhoto {
  const SelectedProductPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;

  String get extension => switch (contentType) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

/// The unique storage object created for one upload attempt.
class UploadedProductPhoto {
  const UploadedProductPhoto({required this.url, required this.storagePath});

  final String url;
  final String storagePath;
}

class PhotoService {
  PhotoService({
    required String cafeId,
    ImagePicker? picker,
    FirebaseStorage? storage,
    this.uploadTimeout = const Duration(seconds: 30),
    this.operationTimeout = const Duration(seconds: 10),
    this.cleanupTimeout = const Duration(seconds: 2),
  })  : cafeId = _validateId(cafeId, 'cafeId'),
        _picker = picker ?? ImagePicker(),
        _storage = storage ?? BrewVerseFirebaseConfig.storage;

  final String cafeId;
  final ImagePicker _picker;
  final FirebaseStorage _storage;
  final Duration uploadTimeout;
  final Duration operationTimeout;
  final Duration cleanupTimeout;

  static const int maximumPhotoSizeBytes = 5 * 1024 * 1024;

  Future<SelectedProductPhoto?> choosePhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return null;

    validatePhotoSize(await file.length().timeout(operationTimeout));
    final bytes = await file.readAsBytes().timeout(operationTimeout);
    validatePhotoSize(bytes.length);
    return SelectedProductPhoto(
      bytes: bytes,
      contentType: detectContentType(bytes),
    );
  }

  /// Upload each replacement to its own object. Never overwrite a photo still
  /// referenced by Firestore before the item update has succeeded.
  Future<UploadedProductPhoto> uploadPhoto(
    String itemId,
    SelectedProductPhoto photo,
  ) async {
    ServerConnection.instance.requireConfirmedOnline();
    validatePhotoSize(photo.bytes.length);
    if (detectContentType(photo.bytes) != photo.contentType) {
      throw StateError('Photo content does not match its selected type.');
    }

    final random = Random.secure();
    final uploadId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final path = storagePath(
      cafeId: cafeId,
      itemId: itemId,
      uploadId: uploadId,
      extension: photo.extension,
    );
    final ref = _storage.ref(path);
    // Native Storage retries unavailable networks for minutes by default.
    // Bound native retries as well as the Dart wait so a failed emulator or
    // unplugged USB cable cannot keep the inventory form disabled indefinitely.
    _storage.setMaxUploadRetryTime(uploadTimeout);
    _storage.setMaxOperationRetryTime(operationTimeout);
    UploadTask? task;
    try {
      task = ref.putData(
        photo.bytes,
        SettableMetadata(contentType: photo.contentType),
      );
      await task.timeout(uploadTimeout);
      return UploadedProductPhoto(
        url: await ref.getDownloadURL().timeout(operationTimeout),
        storagePath: path,
      );
    } catch (_) {
      if (task != null) {
        // Cancellation and cleanup can themselves hang on a disconnected
        // service. Neither is allowed to hide/delay the primary upload error.
        try {
          await task.cancel().timeout(cleanupTimeout);
        } catch (_) {}
        // If cancellation loses a race with completion, clean only this unique
        // attempt's object when it finishes, never an existing product image.
        unawaited(task.then<void>((_) => _cleanupAttempt(ref),
            onError: (Object _) {}));
      }
      await _cleanupAttempt(ref);
      rethrow;
    }
  }

  Future<void> _cleanupAttempt(Reference ref) async {
    try {
      await ref.delete().timeout(cleanupTimeout);
    } catch (_) {
      // A bounded best-effort cleanup must preserve the original failure.
    }
  }

  static String failureMessage(Object error) {
    if (error is TimeoutException) {
      return 'The photo operation timed out. Check your connection and try again. Your existing photo has not been replaced.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'Sign in again before uploading a photo.';
        case 'unauthorized':
          return 'An active café owner or manager account is required to update photos.';
        case 'retry-limit-exceeded':
        case 'unavailable':
          return 'The photo service could not be reached. Check your connection and try again.';
        case 'canceled':
          return 'The photo upload was cancelled. You can try again.';
      }
    }
    return error.toString();
  }

  /// Remove only an object created by this service for this café.
  Future<void> deleteUploadedPhoto(UploadedProductPhoto photo) async {
    if (!photo.storagePath.startsWith('cafes/$cafeId/products/')) {
      throw StateError('Refusing to delete an image from another café.');
    }
    await _storage.ref(photo.storagePath).delete().timeout(cleanupTimeout);
  }

  /// Older images or external URLs may not be ours; never delete those.
  /// A failed cleanup is reported to the caller and must not roll back a
  /// successfully updated Firestore document.
  Future<void> deletePreviousPhoto(String itemId, String url) async {
    if (url.trim().isEmpty) return;
    final ref = _storage.refFromURL(url);
    final prefix = 'cafes/$cafeId/products/${_validateId(itemId, 'itemId')}';
    final path = ref.fullPath;
    final suffix = path.startsWith('${prefix}_')
        ? path.substring(prefix.length + 1)
        : path == '$prefix.jpg'
            ? 'legacy.jpg'
            : '';
    if (ref.bucket != _storage.bucket ||
        suffix.isEmpty ||
        !RegExp(r'^(?:[a-f0-9]{32}\.(?:jpg|png|webp)|legacy\.jpg)$')
            .hasMatch(suffix)) {
      return;
    }
    await ref.delete().timeout(cleanupTimeout);
  }

  /// Backward-compatible convenience entry point for older callers.
  Future<String?> chooseAndUpload(String itemId) async {
    final selection = await choosePhoto();
    if (selection == null) return null;
    final uploaded = await uploadPhoto(itemId, selection);
    return uploaded.url;
  }

  static void validatePhotoSize(int sizeBytes) {
    if (sizeBytes <= 0) {
      throw StateError('The selected photo is empty.');
    }
    if (sizeBytes > maximumPhotoSizeBytes) {
      throw StateError('Product photos must be 5 MiB or smaller.');
    }
  }

  /// Do not label PNG or WebP bytes as JPEG based on a file extension.
  static String detectContentType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    throw StateError('Choose a JPEG, PNG, or WebP image.');
  }

  static String storagePath({
    required String cafeId,
    required String itemId,
    String? uploadId,
    String extension = 'jpg',
  }) {
    final safeCafeId = _validateId(cafeId, 'cafeId');
    final safeItemId = _validateId(itemId, 'itemId');
    final suffix =
        uploadId == null ? '' : '_${_validateId(uploadId, 'uploadId')}';
    if (!['jpg', 'png', 'webp'].contains(extension)) {
      throw ArgumentError.value(
          extension, 'extension', 'Unsupported image type.');
    }
    return 'cafes/$safeCafeId/products/$safeItemId$suffix.$extension';
  }

  static String _validateId(String value, String label) {
    final id = value.trim();
    if (id.isEmpty || id.contains('/') || id == '..') {
      throw ArgumentError.value(value, label, 'Must be a non-empty ID.');
    }
    return id;
  }
}
