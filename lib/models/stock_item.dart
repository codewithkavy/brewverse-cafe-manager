import 'package:cloud_firestore/cloud_firestore.dart';

class StockItem {
  const StockItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.minimumQuantity,
    required this.purchasePricePerUnit,
    required this.sellingPrice,
    this.photoUrl = '',
  });

  final String id;
  final String name;
  final String category; // ingredient or finished
  final String unit;
  final double quantity;
  final double minimumQuantity;
  final double purchasePricePerUnit;
  final double sellingPrice;
  final String photoUrl;

  bool get isLow =>
      category != 'finished' && quantity <= minimumQuantity;

  factory StockItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    double number(String key) => (d[key] as num?)?.toDouble() ?? 0;
    return StockItem(
      id: doc.id,
      name: d['name'] as String? ?? 'Unnamed item',
      category: d['category'] as String? ?? 'ingredient',
      unit: d['unit'] as String? ?? 'piece',
      quantity: number('quantity'),
      minimumQuantity: number('minimumQuantity'),
      purchasePricePerUnit: number('purchasePricePerUnit'),
      sellingPrice: number('sellingPrice'),
      photoUrl: d['photoUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'category': category,
    'unit': unit,
    'quantity': quantity,
    'minimumQuantity': minimumQuantity,
    'purchasePricePerUnit': purchasePricePerUnit,
    'sellingPrice': sellingPrice,
    'photoUrl': photoUrl,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
