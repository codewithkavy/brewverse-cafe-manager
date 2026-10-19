import 'package:cloud_functions/cloud_functions.dart';

import '../models/cafe_membership.dart';
import '../models/stock_item.dart';

typedef CafeCallableInvoker = Future<Map<String, dynamic>> Function(
  String name,
  Map<String, dynamic> data,
);

class CafeMembershipPage {
  const CafeMembershipPage({
    required this.memberships,
    required this.hasMore,
    required this.nextPageToken,
  });

  final List<CafeMembership> memberships;
  final bool hasMore;
  final String? nextPageToken;
}

/// Typed client for trusted tenant operations exposed by Firebase callables.
///
/// It does not provide authorization itself. Firebase Auth supplies the caller
/// identity and each callable verifies active café membership and role.
class CafeFunctionsService {
  CafeFunctionsService({
    FirebaseFunctions? functions,
    CafeCallableInvoker? invoker,
  })  : _functions = functions,
        _invoker = invoker;

  final FirebaseFunctions? _functions;
  final CafeCallableInvoker? _invoker;

  Future<String> createCafe({required String name}) async {
    final result = await _call('createCafe', {'name': name});
    return _requiredString(result, 'cafeId');
  }

  Future<void> grantCafeMembership({
    required String cafeId,
    required String targetEmail,
    required String role,
  }) async {
    await _call('grantCafeMembership', {
      'cafeId': cafeId,
      'email': targetEmail,
      'role': role,
    });
  }

  Future<void> revokeCafeMembership({
    required String cafeId,
    required String targetUid,
  }) async {
    await _call('revokeCafeMembership', {
      'cafeId': cafeId,
      'targetUid': targetUid,
    });
  }

  Future<CafeMembershipPage> listCafeMemberships({
    required String cafeId,
    String? pageToken,
  }) async {
    final result = await _call('listCafeMemberships', {
      'cafeId': cafeId,
      if (pageToken != null) 'pageToken': pageToken,
    });
    final rawMemberships = result['memberships'];
    if (rawMemberships is! List) {
      throw const FormatException(
        'Callable response is missing café memberships.',
      );
    }
    final memberships = rawMemberships.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Invalid café membership response.');
      }
      final membership = CafeMembership.fromMap(
        Map<String, dynamic>.from(raw),
      );
      if (membership.cafeId != cafeId) {
        throw const FormatException(
          'Membership response belongs to another café.',
        );
      }
      return membership;
    }).toList(growable: false);
    final hasMore = result['hasMore'];
    final nextPageToken = result['nextPageToken'];
    if (hasMore is! bool ||
        (nextPageToken != null &&
            (nextPageToken is! String || nextPageToken.trim().isEmpty)) ||
        hasMore != (nextPageToken != null)) {
      throw const FormatException('Invalid café membership page response.');
    }
    return CafeMembershipPage(
      memberships: memberships,
      hasMore: hasMore,
      nextPageToken: nextPageToken as String?,
    );
  }

  Future<String> createStockItem({
    required String cafeId,
    required StockItem item,
  }) async {
    final result = await _call('createStockItem', {
      'cafeId': cafeId,
      'item': {
        'name': item.name,
        'category': item.category,
        'unit': item.unit,
        'quantity': item.quantity,
        'minimumQuantity': item.minimumQuantity,
        'purchasePricePerUnit': item.purchasePricePerUnit,
        'sellingPrice': item.sellingPrice,
        'photoUrl': item.photoUrl,
      },
    });
    return _requiredString(result, 'stockItemId');
  }

  Future<void> addStock({
    required String cafeId,
    required String stockItemId,
    required double quantity,
    required String reason,
  }) async {
    await _call('addStock', {
      'cafeId': cafeId,
      'stockItemId': stockItemId,
      'quantity': quantity,
      'reason': reason,
    });
  }

  Future<void> saveRecipe({
    required String cafeId,
    required String productId,
    required List<Map<String, dynamic>> ingredients,
    List<Map<String, dynamic>> packaging = const [],
  }) async {
    await _call('saveRecipe', {
      'cafeId': cafeId,
      'productId': productId,
      'ingredients': ingredients,
      'packaging': packaging,
    });
  }

  Future<String> checkout({
    required String cafeId,
    required String checkoutId,
    required Map<String, int> cart,
    required String orderType,
    String? customerPhone,
    int redeemPoints = 0,
  }) async {
    final result = await _call('checkout', {
      'cafeId': cafeId,
      'checkoutId': checkoutId,
      'cart': cart,
      'orderType': orderType,
      if (customerPhone != null) 'customerPhone': customerPhone,
      'redeemPoints': redeemPoints,
    });
    return _requiredString(result, 'billId');
  }

  Future<Map<String, dynamic>> lookupLoyaltyCustomer({
    required String cafeId,
    required String phoneNumber,
  }) async {
    final result = await _call('lookupLoyaltyCustomer', {
      'cafeId': cafeId,
      'phoneNumber': phoneNumber,
    });
    final customer = result['customer'];
    if (customer is! Map || customer['pointsBalance'] is! int) {
      throw const FormatException(
          'Callable response contains invalid customer points.');
    }
    return Map<String, dynamic>.from(customer);
  }

  Future<Map<String, dynamic>> refundBill({
    required String cafeId,
    required String billId,
    required String adjustmentId,
    required int amountMinor,
    required String reason,
  }) =>
      _call('refundBill', {
        'cafeId': cafeId,
        'billId': billId,
        'adjustmentId': adjustmentId,
        'amountMinor': amountMinor,
        'reason': reason,
      });

  Future<Map<String, dynamic>> voidBill({
    required String cafeId,
    required String billId,
    required String adjustmentId,
    required String reason,
  }) =>
      _call('voidBill', {
        'cafeId': cafeId,
        'billId': billId,
        'adjustmentId': adjustmentId,
        'reason': reason,
      });

  Future<Map<String, dynamic>> getSalesSummary({
    required String cafeId,
    required DateTime startAt,
    required DateTime endAt,
  }) =>
      _call('getSalesSummary', {
        'cafeId': cafeId,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
      });

  Future<Map<String, dynamic>> getLoyaltySettings({
    required String cafeId,
  }) async {
    final result = await _call('getLoyaltySettings', {'cafeId': cafeId});
    final settings = result['settings'];
    if (settings is! Map) {
      throw const FormatException(
          'Callable response is missing loyalty settings.');
    }
    return Map<String, dynamic>.from(settings);
  }

  Future<Map<String, dynamic>> saveLoyaltySettings({
    required String cafeId,
    required Map<String, dynamic> settings,
  }) async {
    final result = await _call('saveLoyaltySettings', {
      'cafeId': cafeId,
      'settings': settings,
    });
    final saved = result['settings'];
    if (saved is! Map) {
      throw const FormatException(
          'Callable response is missing saved loyalty settings.');
    }
    return Map<String, dynamic>.from(saved);
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, data);
    final functions = _functions ?? FirebaseFunctions.instance;
    final response =
        await functions.httpsCallable(name).call<Map<String, dynamic>>(data);
    return response.data;
  }

  static String _requiredString(Map<String, dynamic> result, String key) {
    final value = result[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Callable response is missing $key.');
    }
    return value;
  }
}
