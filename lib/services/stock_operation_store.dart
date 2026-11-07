import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StockOperationStore {
  Future<String> obtain(String payload);
  Future<void> complete(String payload, String operationId);
}

String _operationId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(1 << 32).toRadixString(36)}';

class MemoryStockOperationStore implements StockOperationStore {
  final Map<String, String> _pending = {};
  @override
  Future<String> obtain(String payload) async =>
      _pending.putIfAbsent(payload, _operationId);
  @override
  Future<void> complete(String payload, String operationId) async {
    if (_pending[payload] == operationId) _pending.remove(payload);
  }
}

/// Separate namespace per authenticated user/café; never removes other local data.
/// A failed/lost reply keeps its key across normal app restarts for safe replay.
class DeviceStockOperationStore implements StockOperationStore {
  DeviceStockOperationStore({required String uid, required String cafeId})
      : _key =
            'brewverse.stock-operations.v1.${Uri.encodeComponent(uid)}.${Uri.encodeComponent(cafeId)}';
  final String _key;
  static final Map<String, Future<void>> _tails = {};
  Future<T> _locked<T>(Future<T> Function() operation) {
    final result =
        (_tails[_key] ?? Future<void>.value()).then((_) => operation());
    _tails[_key] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Map<String, String> _read(SharedPreferences preferences) {
    final encoded = preferences.getString(_key);
    if (encoded == null) return {};
    final decoded = jsonDecode(encoded);
    if (decoded is! Map ||
        decoded.entries.any((e) => e.key is! String || e.value is! String)) {
      throw const FormatException(
          'Pending stock-operation storage needs review.');
    }
    return Map<String, String>.from(decoded);
  }

  @override
  Future<String> obtain(String payload) => _locked(() async {
        final preferences = await SharedPreferences.getInstance();
        final pending = _read(preferences);
        final existing = pending[payload];
        if (existing != null) return existing;
        final id = _operationId();
        pending[payload] = id;
        if (!await preferences.setString(_key, jsonEncode(pending))) {
          throw StateError(
              'Stock update was not sent: its retry key could not be saved.');
        }
        return id;
      });
  @override
  Future<void> complete(String payload, String operationId) =>
      _locked(() async {
        final preferences = await SharedPreferences.getInstance();
        final pending = _read(preferences);
        if (pending[payload] != operationId) return;
        pending.remove(payload);
        if (!await preferences.setString(_key, jsonEncode(pending))) {
          throw StateError(
              'Stock update may be confirmed. Retry the same request before entering another update.');
        }
      });
}
