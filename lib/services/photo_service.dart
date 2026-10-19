import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class PhotoService {
  PhotoService({required String cafeId, ImagePicker? picker})
      : cafeId = _validateId(cafeId, 'cafeId'),
        _picker = picker ?? ImagePicker();

  final String cafeId;
  final ImagePicker _picker;

  Future<String?> chooseAndUpload(String itemId) async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return null;

    final fileLength = await file.length();
    validatePhotoSize(fileLength);
    final Uint8List bytes = await file.readAsBytes();
    final ref = FirebaseStorage.instance.ref(
      storagePath(cafeId: cafeId, itemId: itemId),
    );
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  static const int maximumPhotoSizeBytes = 5 * 1024 * 1024;

  static void validatePhotoSize(int sizeBytes) {
    if (sizeBytes <= 0) {
      throw StateError('The selected photo is empty.');
    }
    if (sizeBytes > maximumPhotoSizeBytes) {
      throw StateError('Product photos must be 5 MiB or smaller.');
    }
  }

  static String storagePath({
    required String cafeId,
    required String itemId,
    String? uploadId,
  }) {
    final safeCafeId = _validateId(cafeId, 'cafeId');
    final safeItemId = _validateId(itemId, 'itemId');
    final suffix =
        uploadId == null ? '' : '_${_validateId(uploadId, 'uploadId')}';
    return 'cafes/$safeCafeId/products/$safeItemId$suffix.jpg';
  }

  static String _validateId(String value, String label) {
    final id = value.trim();
    if (id.isEmpty || id.contains('/')) {
      throw ArgumentError.value(value, label, 'Must be a non-empty ID.');
    }
    return id;
  }
}
