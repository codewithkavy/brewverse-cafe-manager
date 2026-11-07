import 'package:cloud_firestore/cloud_firestore.dart';

/// Historical values only: never substitute today's products, prices or policy.
class SavedBill {
  SavedBill(this.id, Map<String, dynamic> values, {this.isFromCache = false})
      : data = Map.unmodifiable(values);

  final String id;
  final bool isFromCache;
  final Map<String, dynamic> data;
  String? text(String key) => data[key] is String ? data[key] as String : null;
  num? amount(String key) {
    final value = data[key];
    return value is num && value.isFinite && value >= 0 ? value : null;
  }

  DateTime? get createdAt {
    final value = data['createdAt'];
    return value is Timestamp
        ? value.toDate()
        : value is DateTime
            ? value
            : null;
  }

  String? get customerPhone => text('customerPhone');
  String? get customerName => text('customerName');
  String get maskedPhone {
    final phone = customerPhone;
    if (phone == null || phone.isEmpty) return 'Phone not recorded';
    return phone.length <= 4
        ? '••••'
        : '•••• ${phone.substring(phone.length - 4)}';
  }

  String get orderLabel => switch (text('orderType')) {
        'dineIn' => 'Dine-in',
        'takeaway' => 'Takeaway',
        _ => 'Order type not recorded',
      };
  String get statusLabel => switch (text('status')) {
        'completed' => 'Completed',
        'partially_refunded' => 'Partially refunded',
        'refunded' => 'Refunded',
        'void' || 'voided' => 'Void',
        final String value => value,
        _ => 'Not recorded',
      };
  List<Map<String, dynamic>> get items => (data['items'] is List)
      ? (data['items'] as List)
          .whereType<Map>()
          .map((v) => Map<String, dynamic>.from(v))
          .toList()
      : const [];
  Map<String, dynamic>? get loyalty => data['loyalty'] is Map
      ? Map<String, dynamic>.from(data['loyalty'] as Map)
      : null;

  bool get hasReceiptFields =>
      items.isNotEmpty &&
      items.length == (data['items'] as List).length &&
      items.every((line) =>
          line['name'] is String &&
          (line['name'] as String).trim().isNotEmpty) &&
      amount('total') != null &&
      amount('discount') != null &&
      ['dineIn', 'takeaway'].contains(text('orderType'));
}

String billMoney(Object? value) => value is num && value.isFinite && value >= 0
    ? '₹${value.toStringAsFixed(2)}'
    : 'Not recorded';

String billDate(DateTime? value) {
  if (value == null) return 'Date not recorded';
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} · ${two(d.hour)}:${two(d.minute)}';
}
