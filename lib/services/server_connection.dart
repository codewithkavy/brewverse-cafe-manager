import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum ServerReadState { checking, confirmed, cached }

class OfflineOperationException implements Exception {
  const OfflineOperationException();
  @override
  String toString() =>
      'A live connection is required. Cached data is read-only; reconnect before changing stock or completing a transaction.';
}

/// Tracks actual Firebase responses rather than Wi-Fi/mobile interface presence.
/// Unmanaged means a preview/test without an application connection scope.
class ServerConnection extends ChangeNotifier {
  ServerConnection();
  static final instance = ServerConnection();
  bool _managed = false;
  ServerReadState _state = ServerReadState.checking;
  bool get managed => _managed;
  ServerReadState get state => _state;
  bool get canWrite => !_managed || _state == ServerReadState.confirmed;
  void beginSession() {
    _managed = true;
    _update(ServerReadState.checking);
  }

  void reportSnapshot({required bool fromCache}) {
    if (_managed) {
      _update(fromCache ? ServerReadState.cached : ServerReadState.confirmed);
    }
  }

  void markUnavailable() {
    if (_managed) _update(ServerReadState.cached);
  }

  void endSession() {
    _managed = false;
    _update(ServerReadState.checking);
  }

  void _update(ServerReadState value) {
    _state = value;
    notifyListeners();
  }

  void requireConfirmedOnline() {
    if (!canWrite) throw const OfflineOperationException();
  }
}

bool isOfflineReadFailure(Object error) =>
    error is TimeoutException ||
    (error is FirebaseException &&
        ['unavailable', 'deadline-exceeded', 'network-request-failed']
            .contains(error.code));

/// Server-only reads never mistake a local Firestore cache hit for connectivity.
Future<void> requireServerConnection(Future<void> Function() probe,
    {Duration timeout = const Duration(seconds: 5)}) async {
  ServerConnection.instance.requireConfirmedOnline();
  try {
    await probe().timeout(timeout);
  } catch (error) {
    if (!isOfflineReadFailure(error)) rethrow;
    ServerConnection.instance.markUnavailable();
    throw const OfflineOperationException();
  }
}
