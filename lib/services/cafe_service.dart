import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stock_item.dart';

class CafeService {
  CafeService({FirebaseFirestore? firestore})
      : db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore db;

  CollectionReference<Map<String, dynamic>> get stock =>
      db.collection('stock_items');

  CollectionReference<Map<String, dynamic>> get recipes =>
      db.collection('product_recipes');

  CollectionReference<Map<String, dynamic>> get bills =>
      db.collection('bills');

  CollectionReference<Map<String, dynamic>> get movements =>
      db.collection('stock_movements');

  // INVENTORY

  Stream<List<StockItem>> watchStock() {
    return stock.orderBy('name').snapshots().map(
          (snapshot) =>
          snapshot.docs.map(StockItem.fromDoc).toList(),
    );
  }

  Future<String> addItem(StockItem item) async {
    final doc = stock.doc();
    await doc.set(item.toMap());
    return doc.id;
  }

  // NEW: Update item details without overwriting live stock.
  Future<void> updateItem(StockItem item) async {
    if (item.id.trim().isEmpty) {
      throw ArgumentError('Item ID cannot be empty.');
    }

    final itemRef = stock.doc(item.id);

    await db.runTransaction((tx) async {
      final snapshot = await tx.get(itemRef);

      if (!snapshot.exists) {
        throw StateError('This inventory item no longer exists.');
      }

      final currentData = snapshot.data()!;
      final updatedData = item.toMap();

      // Keep the actual current stock quantity.
      updatedData['quantity'] = currentData['quantity'];

      // Do not let an edit overwrite the original creation time.
      updatedData.remove('createdAt');

      // Record when the item details were updated.
      updatedData['updatedAt'] = FieldValue.serverTimestamp();

      tx.update(itemRef, updatedData);
    });
  }

  Future<void> addStock({
    required String itemId,
    required double quantity,
    required String reason,
  }) async {
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError(
        'Quantity must be finite and greater than zero.',
      );
    }

    final itemRef = stock.doc(itemId);
    final movementRef = movements.doc();

    await db.runTransaction((tx) async {
      final snap = await tx.get(itemRef);

      if (!snap.exists) {
        throw StateError('Stock item not found.');
      }

      final data = snap.data()!;
      final current = _number(data['quantity'], 'quantity');
      final updated = current + quantity;

      tx.update(itemRef, {
        'quantity': updated,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.set(movementRef, {
        'stockItemId': itemId,
        'type': 'addition',
        'quantityChange': quantity,
        'quantityAfter': updated,
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> setPhotoUrl(
      String itemId,
      String photoUrl,
      ) {
    return stock.doc(itemId).update({
      'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // RECIPES

  Future<void> saveRecipe({
    required String productId,
    required List<Map<String, dynamic>> ingredients,
    List<Map<String, dynamic>> packaging = const [],
  }) async {
    if (ingredients.isEmpty) {
      throw ArgumentError(
        'A recipe must contain at least one ingredient.',
      );
    }

    _validateRecipeLines(ingredients, 'ingredients');
    _validateRecipeLines(packaging, 'packaging');

    final productRef = stock.doc(productId);
    final recipeRef = recipes.doc(productId);

    final ingredientIds = <String>{
      ...ingredients.map((line) => line['stockItemId'] as String),
      ...packaging.map((line) => line['stockItemId'] as String),
    };

    await db.runTransaction((tx) async {
      final productSnap = await tx.get(productRef);

      if (!productSnap.exists) {
        throw StateError('Finished product not found.');
      }

      if (productSnap.data()!['category'] != 'finished') {
        throw StateError(
          'Recipes can only be assigned to finished products.',
        );
      }

      final refs = ingredientIds.map((id) => stock.doc(id)).toList();
      final snapshots =
      <DocumentSnapshot<Map<String, dynamic>>>[];

      for (final ref in refs) {
        snapshots.add(await tx.get(ref));
      }

      for (final snapshot in snapshots) {
        if (!snapshot.exists) {
          throw StateError(
            'Recipe references missing stock item: ${snapshot.id}',
          );
        }

        if (snapshot.data()!['category'] == 'finished') {
          throw StateError(
            'Recipe ingredients and packaging must not be finished products.',
          );
        }
      }

      tx.set(recipeRef, {
        'productId': productId,
        'ingredients': ingredients,
        'packaging': packaging,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // TRANSACTIONAL CHECKOUT

  Future<String> checkout({
    required String checkoutId,
    required Map<String, int> cart,
    required String orderType,
  }) async {
    if (checkoutId.trim().isEmpty) {
      throw ArgumentError('Checkout ID cannot be empty.');
    }

    if (cart.isEmpty) {
      throw ArgumentError('Cannot checkout an empty cart.');
    }

    if (orderType != 'dineIn' && orderType != 'takeaway') {
      throw ArgumentError(
        'Order type must be dineIn or takeaway.',
      );
    }

    for (final entry in cart.entries) {
      if (entry.key.trim().isEmpty || entry.value <= 0) {
        throw ArgumentError('Invalid product ID or quantity.');
      }
    }

    final billRef = bills.doc(checkoutId);

    final sortedEntries = cart.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final requestKey = [
      orderType,
      for (final entry in sortedEntries)
        '${entry.key}:${entry.value}',
    ].join('|');

    return db.runTransaction<String>((tx) async {
      final existingBill = await tx.get(billRef);

      if (existingBill.exists) {
        final existingKey = existingBill.data()?['requestKey'];

        if (existingKey != requestKey) {
          throw StateError(
            'This checkout ID was already used for a different bill.',
          );
        }

        return billRef.id;
      }

      final productIds = sortedEntries.map((e) => e.key).toList();

      final productSnaps =
      <String, DocumentSnapshot<Map<String, dynamic>>>{};

      final recipeSnaps =
      <String, DocumentSnapshot<Map<String, dynamic>>>{};

      for (final productId in productIds) {
        final productRef = stock.doc(productId);
        final recipeRef = recipes.doc(productId);

        final productSnap = await tx.get(productRef);
        final recipeSnap = await tx.get(recipeRef);

        if (!productSnap.exists) {
          throw StateError('Product not found: $productId');
        }

        if (productSnap.data()!['category'] != 'finished') {
          throw StateError('Only finished products can be sold.');
        }

        if (!recipeSnap.exists) {
          throw StateError(
            'No recipe configured for '
                '${productSnap.data()!['name'] ?? productId}.',
          );
        }

        productSnaps[productId] = productSnap;
        recipeSnaps[productId] = recipeSnap;
      }

      final requiredStock = <String, double>{};
      final billItems = <Map<String, dynamic>>[];

      for (final entry in sortedEntries) {
        final productId = entry.key;
        final quantity = entry.value;
        final product = productSnaps[productId]!.data()!;
        final recipe = recipeSnaps[productId]!.data()!;

        final price = _number(product['sellingPrice'], 'sellingPrice');

        if (price < 0) {
          throw StateError('Product price cannot be negative.');
        }

        final ingredientLines =
        _recipeLines(recipe['ingredients'], 'ingredients');

        if (ingredientLines.isEmpty) {
          throw StateError(
            'Product ${product['name']} has an empty recipe.',
          );
        }

        for (final line in ingredientLines) {
          _addRequirement(
            requiredStock,
            line,
            quantity,
            'ingredient',
          );
        }

        if (orderType == 'takeaway') {
          final packagingLines =
          _recipeLines(recipe['packaging'], 'packaging');

          for (final line in packagingLines) {
            _addRequirement(
              requiredStock,
              line,
              quantity,
              'packaging',
            );
          }
        }

        billItems.add({
          'productId': productId,
          'name': product['name'] ?? 'Unnamed product',
          'quantity': quantity,
          'unitPrice': price,
          'lineTotal': price * quantity,
        });
      }

      final stockSnaps =
      <String, DocumentSnapshot<Map<String, dynamic>>>{};

      final stockIds = requiredStock.keys.toList()..sort();

      for (final id in stockIds) {
        final snap = await tx.get(stock.doc(id));

        if (!snap.exists) {
          throw StateError('Required stock item not found: $id');
        }

        final data = snap.data()!;

        if (data['category'] == 'finished') {
          throw StateError(
            'A recipe cannot deduct another finished product.',
          );
        }

        stockSnaps[id] = snap;
      }

      final updatedQuantities = <String, double>{};

      for (final id in stockIds) {
        final data = stockSnaps[id]!.data()!;
        final current = _number(data['quantity'], 'quantity');
        final required = requiredStock[id]!;

        if (current < required) {
          final name = data['name'] ?? id;

          throw StateError(
            'Insufficient stock for $name. '
                'Available: $current, required: $required.',
          );
        }

        updatedQuantities[id] = current - required;
      }

      final total = billItems.fold<double>(
        0,
            (runningTotal, item) =>
        runningTotal + (item['lineTotal'] as double),
      );

      for (final id in stockIds) {
        final required = requiredStock[id]!;
        final updated = updatedQuantities[id]!;

        tx.update(stock.doc(id), {
          'quantity': updated,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final movementRef = movements.doc();

        tx.set(movementRef, {
          'stockItemId': id,
          'type': 'sale',
          'quantityChange': -required,
          'quantityAfter': updated,
          'reason': 'Checkout ${billRef.id} ($orderType)',
          'billId': billRef.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      tx.set(billRef, {
        'billId': billRef.id,
        'requestKey': requestKey,
        'orderType': orderType,
        'items': billItems,
        'total': total,
        'status': 'completed',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return billRef.id;
    });
  }

  // VALIDATION HELPERS

  static double _number(dynamic value, String field) {
    if (value is! num) {
      throw StateError('Invalid numeric field: $field.');
    }

    final result = value.toDouble();

    if (!result.isFinite) {
      throw StateError('Non-finite numeric field: $field.');
    }

    return result;
  }

  static void _validateRecipeLines(
      List<Map<String, dynamic>> lines,
      String field,
      ) {
    for (final line in lines) {
      final id = line['stockItemId'];
      final quantity = line['quantity'];

      if (id is! String || id.trim().isEmpty) {
        throw ArgumentError('$field entries need a stockItemId.');
      }

      if (quantity is! num ||
          !quantity.toDouble().isFinite ||
          quantity <= 0) {
        throw ArgumentError(
          '$field quantities must be finite and greater than zero.',
        );
      }
    }
  }

  static List<Map<String, dynamic>> _recipeLines(
      dynamic value,
      String field,
      ) {
    if (value == null && field == 'packaging') {
      return [];
    }

    if (value is! List) {
      throw StateError('Recipe $field must be a list.');
    }

    final result = <Map<String, dynamic>>[];

    for (final entry in value) {
      if (entry is! Map) {
        throw StateError('Invalid recipe entry in $field.');
      }

      final line = Map<String, dynamic>.from(entry);
      final id = line['stockItemId'];
      final quantity = line['quantity'];

      if (id is! String ||
          id.trim().isEmpty ||
          quantity is! num ||
          !quantity.toDouble().isFinite ||
          quantity <= 0) {
        throw StateError('Invalid recipe entry in $field.');
      }

      result.add(line);
    }

    return result;
  }

  static void _addRequirement(
      Map<String, double> requiredStock,
      Map<String, dynamic> line,
      int productQuantity,
      String field,
      ) {
    final id = line['stockItemId'] as String;
    final perProduct = _number(line['quantity'], field);
    final amount = perProduct * productQuantity;

    if (!amount.isFinite || amount <= 0) {
      throw StateError('Invalid required quantity for $id.');
    }

    requiredStock[id] = (requiredStock[id] ?? 0) + amount;
  }
}