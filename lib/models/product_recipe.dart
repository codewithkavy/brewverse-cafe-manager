class RecipeIngredient {
  const RecipeIngredient({
    required this.stockItemId,
    required this.stockItemName,
    required this.quantity,
    required this.unit,
  });

  final String stockItemId;
  final String stockItemName;
  final double quantity;
  final String unit;

  Map<String, dynamic> toMap() => {
    'stockItemId': stockItemId,
    'stockItemName': stockItemName,
    'quantity': quantity,
    'unit': unit,
  };
}

class ProductRecipe {
  const ProductRecipe({
    required this.name,
    required this.sellingPrice,
    required this.ingredients,
  });

  final String name;
  final double sellingPrice;
  final List<RecipeIngredient> ingredients;

  Map<String, dynamic> toMap() => {
    'name': name,
    'sellingPrice': sellingPrice,
    'ingredients': ingredients.map((item) => item.toMap()).toList(),
  };
}