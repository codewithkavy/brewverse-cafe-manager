import '../firebase_runtime_config.dart';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// An immutable order token is also its unique bill ID. It is saved before RPC.
class PendingCheckout {
  PendingCheckout({
    required this.id,
    required Map<String, int> cart,
    required this.orderType,
    this.customerPhone,
    this.redeemPoints = 0,
  }) : cart = Map.unmodifiable(cart);

  final String id;
  final Map<String, int> cart;
  final String orderType;
  final String? customerPhone;
  final int redeemPoints;

  static String newId() {
    final random = Random.secure();
    return List.generate(
            20, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'cart': cart,
        'orderType': orderType,
        'customerPhone': customerPhone,
        'redeemPoints': redeemPoints,
      };

  factory PendingCheckout.fromMap(Map<String, dynamic> value) {
    final id = value['id'];
    final orderType = value['orderType'];
    final cart = value['cart'];
    final phone = value['customerPhone'];
    final points = value['redeemPoints'];
    if (id is! String ||
        id.isEmpty ||
        id.contains('/') ||
        !['dineIn', 'takeaway'].contains(orderType) ||
        cart is! Map ||
        cart.isEmpty ||
        cart.length > 100 ||
        points is! int ||
        points < 0 ||
        (phone != null && phone is! String)) {
      throw const FormatException('Saved pending checkout is invalid.');
    }
    final items = <String, int>{};
    for (final entry in cart.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.key as String).contains('/') ||
          entry.value is! int ||
          (entry.value as int) < 1 ||
          (entry.value as int) > 10000) {
        throw const FormatException('Saved pending cart is invalid.');
      }
      items[entry.key as String] = entry.value as int;
    }
    return PendingCheckout(
        id: id,
        cart: items,
        orderType: orderType as String,
        customerPhone: phone as String?,
        redeemPoints: points);
  }
}

class CheckoutRecoveryState {
  const CheckoutRecoveryState({this.pending, this.lastBillId});
  final PendingCheckout? pending;
  final String? lastBillId;
}

abstract class CheckoutRecoveryStore {
  Future<CheckoutRecoveryState> load();
  Future<void> save(PendingCheckout request);
  Future<void> confirm(String billId);
  Future<void> reject();
}

/// Device-local recovery, scoped to the authenticated cashier and café.
/// A single preferences write replaces pending state with the confirmed bill.
class DeviceCheckoutRecoveryStore implements CheckoutRecoveryStore {
  DeviceCheckoutRecoveryStore({required String cafeId, String? uid})
      : _uid = uid ?? _currentUid(),
        _cafeId = cafeId;

  final String? _uid;
  final String _cafeId;
  static String? _currentUid() {
    try {
      return BrewVerseFirebaseConfig.auth.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  String get _key =>
      'checkout.recovery.v1.${base64UrlEncode(utf8.encode(jsonEncode([
            _uid,
            _cafeId
          ])))}';

  @override
  Future<CheckoutRecoveryState> load() async {
    if (_uid == null) return const CheckoutRecoveryState();
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const CheckoutRecoveryState();
    final value = jsonDecode(raw);
    if (value is! Map ||
        (value['lastBillId'] != null && value['lastBillId'] is! String)) {
      throw const FormatException('Checkout recovery record is invalid.');
    }
    return CheckoutRecoveryState(
      pending: value['pending'] == null
          ? null
          : PendingCheckout.fromMap(
              Map<String, dynamic>.from(value['pending'] as Map)),
      lastBillId: value['lastBillId'] as String?,
    );
  }

  Future<void> _write(Map<String, dynamic> value) async {
    if (_uid == null) throw StateError('Sign in before completing checkout.');
    final saved = await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(value));
    if (!saved) {
      throw StateError('Could not save checkout recovery on this device.');
    }
  }

  @override
  Future<void> save(PendingCheckout request) async {
    final current = await load();
    await _write(
        {'pending': request.toMap(), 'lastBillId': current.lastBillId});
  }

  @override
  Future<void> confirm(String billId) => _write({'lastBillId': billId});
  @override
  Future<void> reject() async {
    final current = await load();
    await _write({'lastBillId': current.lastBillId});
  }
}

/// In-memory implementation for isolated widget tests and legacy compatibility.
class MemoryCheckoutRecoveryStore implements CheckoutRecoveryStore {
  CheckoutRecoveryState state = const CheckoutRecoveryState();
  @override
  Future<CheckoutRecoveryState> load() async => state;
  @override
  Future<void> save(PendingCheckout request) async => state =
      CheckoutRecoveryState(pending: request, lastBillId: state.lastBillId);
  @override
  Future<void> confirm(String billId) async =>
      state = CheckoutRecoveryState(lastBillId: billId);
  @override
  Future<void> reject() async =>
      state = CheckoutRecoveryState(lastBillId: state.lastBillId);
}
