import 'dart:async';
import 'dart:typed_data';

import 'package:brewverse_cafe_manager/services/photo_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Snapshot implements TaskSnapshot {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Task implements UploadTask {
  _Task(this.completion);
  final Future<TaskSnapshot> completion;
  Future<bool> Function()? cancelAction;
  bool cancelled = false;
  @override
  Future<bool> cancel() {
    cancelled = true;
    return cancelAction?.call() ?? Future.value(true);
  }

  @override
  Future<TaskSnapshot> timeout(Duration duration,
          {FutureOr<TaskSnapshot> Function()? onTimeout}) =>
      completion.timeout(duration, onTimeout: onTimeout);
  @override
  Future<T> then<T>(FutureOr<T> Function(TaskSnapshot) onValue,
          {Function? onError}) =>
      completion.then(onValue, onError: onError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Reference implements Reference {
  late _Task task;
  Future<String> Function() downloadUrl = () async => 'http://local/photo';
  Future<void> Function() deleteAction = () async {};
  int deletions = 0;
  @override
  UploadTask putData(Uint8List data, [SettableMetadata? metadata]) => task;
  @override
  Future<String> getDownloadURL() => downloadUrl();
  @override
  Future<void> delete() {
    deletions++;
    return deleteAction();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage implements FirebaseStorage {
  _Storage(this.reference);
  final _Reference reference;
  String? path;
  Duration? uploadRetry;
  Duration? operationRetry;
  @override
  Reference ref([String? path]) {
    this.path = path;
    return reference;
  }

  @override
  void setMaxUploadRetryTime(Duration duration) => uploadRetry = duration;
  @override
  void setMaxOperationRetryTime(Duration duration) => operationRetry = duration;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final photo = SelectedProductPhoto(
      bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0]),
      contentType: 'image/jpeg');
  PhotoService service(_Storage storage) => PhotoService(
        cafeId: 'cafe-a',
        storage: storage,
        uploadTimeout: const Duration(milliseconds: 20),
        operationTimeout: const Duration(milliseconds: 20),
        cleanupTimeout: const Duration(milliseconds: 10),
      );

  test('successful upload returns URL and never cleans the committed attempt',
      () async {
    final ref = _Reference()..task = _Task(Future.value(_Snapshot()));
    final storage = _Storage(ref);
    final result = await service(storage).uploadPhoto('burger', photo);
    expect(result.url, 'http://local/photo');
    expect(result.storagePath, storage.path);
    expect(storage.path, startsWith('cafes/cafe-a/products/burger_'));
    expect(ref.deletions, 0);
    expect(storage.uploadRetry, const Duration(milliseconds: 20));
    expect(storage.operationRetry, const Duration(milliseconds: 20));
  });

  test('stalled upload returns timeout, cancels, and bounds stalled cleanup',
      () async {
    final completion = Completer<TaskSnapshot>();
    final ref = _Reference()..task = _Task(completion.future);
    ref.task.cancelAction = () => Completer<bool>().future;
    ref.deleteAction = () => Completer<void>().future;
    await expectLater(
        service(_Storage(ref))
            .uploadPhoto('burger', photo)
            .timeout(const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>().having((error) => error.duration,
            'original deadline', const Duration(milliseconds: 20))));
    expect(ref.task.cancelled, isTrue);
    expect(ref.deletions, 1);
    // If native cancellation completes too late, the unique new object still
    // receives cleanup, without ever touching an existing item's URL.
    completion.complete(_Snapshot());
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ref.deletions, 2);
  });

  test('stalled download URL and delete do not keep the form waiting',
      () async {
    final ref = _Reference()..task = _Task(Future.value(_Snapshot()));
    ref.downloadUrl = () => Completer<String>().future;
    ref.deleteAction = () => Completer<void>().future;
    await expectLater(
        service(_Storage(ref))
            .uploadPhoto('burger', photo)
            .timeout(const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>().having((error) => error.duration,
            'original deadline', const Duration(milliseconds: 20))));
    expect(ref.task.cancelled, isTrue);
  });

  test('permission failure survives cleanup errors and has a useful message',
      () async {
    final failure =
        FirebaseException(plugin: 'firebase_storage', code: 'unauthorized');
    final upload = Completer<TaskSnapshot>();
    final ref = _Reference()..task = _Task(upload.future);
    ref.deleteAction = () async => throw StateError('cleanup also failed');
    final result = service(_Storage(ref)).uploadPhoto('burger', photo);
    upload.completeError(failure);
    await expectLater(result, throwsA(same(failure)));
    expect(PhotoService.failureMessage(failure), contains('owner or manager'));
    expect(PhotoService.failureMessage(TimeoutException('network')),
        contains('try again'));
    expect(
        PhotoService.failureMessage(FirebaseException(
            plugin: 'firebase_storage', code: 'unauthenticated')),
        contains('Sign in again'));
  });
}
