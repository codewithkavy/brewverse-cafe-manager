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
    this.stockMode = 'recipe',
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
  // Existing finished products use their recipe unless explicitly configured
  // as a packaged/direct-stock product.
  final String stockMode;

  bool get isRecipeProduct => category == 'finished' && stockMode != 'direct';

  bool get isDirectStock => !isRecipeProduct;

  bool get isLow => isDirectStock && quantity <= minimumQuantity;

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
      stockMode: d['stockMode'] as String? ?? 'recipe',
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
        'stockMode': stockMode,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
