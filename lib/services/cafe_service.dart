import '../firebase_runtime_config.dart';
import 'dart:convert';
import 'server_connection.dart';
import 'stock_operation_store.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stock_item.dart';
import 'cafe_functions_service.dart';
import 'tenant_cafe_data_service.dart';

class CafeService {
  static const int _maxSafeMinorUnits = 9007199254740991;
  // Each distinct stock record needs an update and a movement write, plus the
  // bill itself. Keep the transaction below Firestore's 500-write limit.
  static const int _maxCheckoutStockItems = 249;
  CafeService({
    FirebaseFirestore? firestore,
    String? cafeId,
    CafeFunctionsService? functionsService,
    Future<void> Function()? onlineCheck,
    StockOperationStore? stockOperationStore,
  })  : db = firestore ?? BrewVerseFirebaseConfig.firestore,
        cafeId = cafeId == null ? null : _validateCafeId(cafeId),
        _providedFunctionsService = functionsService,
        _onlineCheck = onlineCheck,
        _providedStockOperationStore = stockOperationStore,
        _requiresDefaultOnlineCheck = firestore == null;

  final FirebaseFirestore db;
  final String? cafeId;
  final CafeFunctionsService? _providedFunctionsService;
  final Future<void> Function()? _onlineCheck;
  final bool _requiresDefaultOnlineCheck;
  final StockOperationStore? _providedStockOperationStore;
  StockOperationStore? _stockOperationStore;
  StockOperationStore get _stockOperations =>
      _stockOperationStore ??= _providedStockOperationStore ??
          (_requiresDefaultOnlineCheck
              ? DeviceStockOperationStore(
                  uid: BrewVerseFirebaseConfig.auth.currentUser!.uid,
                  cafeId: cafeId!)
              : MemoryStockOperationStore());

  Future<void> _requireOnline() async {
    final injected = _onlineCheck;
    if (injected != null) {
      await injected();
      return;
    }
    if (!_requiresDefaultOnlineCheck) return;
    await requireServerConnection(() async {
      if (cafeId != null) {
        await db
            .collection('cafes')
            .doc(cafeId)
            .get(const GetOptions(source: Source.server));
      } else {
        await stock.limit(1).get(const GetOptions(source: Source.server));
      }
    });
  }

  late final TenantCafeDataService? _tenantData = cafeId == null
      ? null
      : TenantCafeDataService(cafeId: cafeId!, firestore: db);
  late final CafeFunctionsService _functionsService =
      _providedFunctionsService ?? CafeFunctionsService();

  CollectionReference<Map<String, dynamic>> get stock =>
      db.collection('stock_items');

  CollectionReference<Map<String, dynamic>> get recipes =>
      db.collection('product_recipes');

  CollectionReference<Map<String, dynamic>> get bills => db.collection('bills');

  CollectionReference<Map<String, dynamic>> get movements =>
      db.collection('stock_movements');

  // INVENTORY

  Stream<List<StockItem>> watchStock() {
    final tenantData = _tenantData;
    if (tenantData != null) return tenantData.watchStock();
    return stock
        .orderBy('name')
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      ServerConnection.instance.reportSnapshot(
          fromCache: snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites);
      return snapshot.docs.map(StockItem.fromDoc).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> watchRecentMovements({int limit = 100}) {
    final tenantData = _tenantData;
    if (tenantData != null) {
      return tenantData.watchRecentMovements(limit: limit);
    }
    if (limit < 1 || limit > 500) {
      throw ArgumentError('Movement limit must be between 1 and 500.');
    }
    return movements
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {...doc.data(), 'id': doc.id})
              .toList(growable: false),
        );
  }

  Future<String> addItem(StockItem item) async {
    await _requireOnline();
    validateNewItem(item);
    final tenantId = cafeId;
    if (tenantId != null) {
      return _functionsService.createStockItem(cafeId: tenantId, item: item);
    }
    final doc = stock.doc();
    final initialQuantity = item.quantity;

    await db.runTransaction((tx) async {
      tx.set(doc, {
        ...item.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (initialQuantity > 0) {
        final movementRef = movements.doc();
        tx.set(movementRef, {
          'stockItemId': doc.id,
          'stockItemName': item.name,
          'stockItemUnit': item.unit,
          'type': 'addition',
          'quantityChange': initialQuantity,
          'quantityAfter': initialQuantity,
          'reason': 'Opening stock',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
    return doc.id;
  }

  // NEW: Update item details without overwriting live stock.
  Future<void> updateItem(StockItem item) async {
    await _requireOnline();
    validateNewItem(item);
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
      if (cafeId != null && currentData['cafeId'] != cafeId) {
        throw StateError('This inventory item belongs to another café.');
      }
      final updatedData = item.toMap();

      // Keep stock and photos independent from the rest of the edit form.
      // An older open dialog must not undo a more recent photo update.
      updatedData['quantity'] = currentData['quantity'];
      updatedData['photoUrl'] = currentData['photoUrl'] ?? item.photoUrl;

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
    await _requireOnline();
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError(
        'Quantity must be finite and greater than zero.',
      );
    }

    final tenantId = cafeId;
    if (tenantId != null) {
      final payload = jsonEncode([itemId.trim(), quantity, reason.trim()]);
      final operationId = await _stockOperations.obtain(payload);
      await _functionsService.addStock(
        cafeId: tenantId,
        stockItemId: itemId,
        quantity: quantity,
        reason: reason,
        operationId: operationId,
      );
      await _stockOperations.complete(payload, operationId);
      return;
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
        'stockItemName': data['name'],
        'stockItemUnit': data['unit'],
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
  ) async {
    await _requireOnline();
    final itemRef = stock.doc(itemId);
    // A transaction must reach Firestore; unlike update(), it cannot silently
    // queue a stock metadata edit after a connection drops between checks.
    await db.runTransaction((transaction) async {
      final current = await transaction.get(itemRef);
      if (!current.exists ||
          (cafeId != null && current.data()?['cafeId'] != cafeId)) {
        throw StateError('Inventory item not found in this café.');
      }
      transaction.update(itemRef, {
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Compare-and-set the image link, so a stale form cannot silently
  /// overwrite another cashier's photo. Only use after the new object upload
  /// has succeeded; callers clean up that object when this transaction fails.
  Future<void> replacePhotoUrl({
    required String itemId,
    required String expectedUrl,
    required String newUrl,
  }) async {
    await _requireOnline();
    if (itemId.trim().isEmpty) {
      throw ArgumentError('Item ID cannot be empty.');
    }
    final doc = stock.doc(itemId);
    await db.runTransaction((tx) async {
      final snapshot = await tx.get(doc);
      if (!snapshot.exists) {
        throw StateError('Inventory item no longer exists.');
      }
      final data = snapshot.data()!;
      if (cafeId != null && data['cafeId'] != cafeId) {
        throw StateError('Inventory item belongs to another café.');
      }
      final existingUrl = data['photoUrl'] as String? ?? '';
      if (existingUrl != expectedUrl) {
        throw StateError('This photo changed elsewhere. Reopen the item.');
      }
      tx.update(doc, {
        'photoUrl': newUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // RECIPES

  Future<void> saveRecipe({
    required String productId,
    required List<Map<String, dynamic>> ingredients,
    List<Map<String, dynamic>> packaging = const [],
  }) async {
    await _requireOnline();
    validateRecipe(ingredients: ingredients, packaging: packaging);

    final tenantId = cafeId;
    if (tenantId != null) {
      await _functionsService.saveRecipe(
        cafeId: tenantId,
        productId: productId,
        ingredients: ingredients,
        packaging: packaging,
      );
      return;
    }

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
      final snapshots = <DocumentSnapshot<Map<String, dynamic>>>[];

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

  Future<Map<String, dynamic>?> loadRecipe(String productId) async {
    final tenantId = cafeId;
    if (tenantId != null) {
      // A missing document has no cafeId for the rules to authorize a direct
      // get. A cafe-constrained query authorizes the tenant even when there is
      // no saved recipe yet, while preserving permission/connection errors.
      final snapshot = await recipes
          .where('cafeId', isEqualTo: tenantId)
          .where('productId', isEqualTo: productId)
          .limit(1)
          .get();
      return snapshot.docs.isEmpty ? null : snapshot.docs.single.data();
    }
    final snapshot = await recipes.doc(productId).get();
    return snapshot.data();
  }

  Future<String?> loadCafeName() async {
    final tenantId = cafeId;
    if (tenantId == null) return null;

    final snapshot = await db.collection('cafes').doc(tenantId).get();
    final name = snapshot.data()?['name'];
    if (name is! String || name.trim().isEmpty) return null;
    return name.trim();
  }

  Future<Map<String, dynamic>?> loadBill(String billId) async {
    final tenantData = _tenantData;
    if (tenantData != null) return tenantData.getBill(billId);
    final snapshot = await bills.doc(billId).get();
    final data = snapshot.data();
    return data == null ? null : {...data, 'id': snapshot.id};
  }

  Future<Map<String, dynamic>> lookupLoyaltyCustomer({
    required String phoneNumber,
  }) async {
    final tenantId = cafeId;
    if (tenantId == null) {
      throw StateError('Loyalty lookup requires a selected café workspace.');
    }
    return _functionsService.lookupLoyaltyCustomer(
      cafeId: tenantId,
      phoneNumber: phoneNumber,
    );
  }

  Future<Map<String, dynamic>> getLoyaltySettings() async {
    final tenantId = cafeId;
    if (tenantId == null) {
      throw StateError('Loyalty settings require a selected café workspace.');
    }
    return _functionsService.getLoyaltySettings(cafeId: tenantId);
  }

  // TRANSACTIONAL CHECKOUT

  Future<String> checkout({
    required String checkoutId,
    required Map<String, int> cart,
    required String orderType,
    String? customerPhone,
    int redeemPoints = 0,
  }) async {
    await _requireOnline();
    if (checkoutId.trim().isEmpty) {
      throw ArgumentError('Checkout ID cannot be empty.');
    }

    if (cart.isEmpty || cart.length > 100) {
      throw ArgumentError('Cart must contain between 1 and 100 products.');
    }

    if (orderType != 'dineIn' && orderType != 'takeaway') {
      throw ArgumentError(
        'Order type must be dineIn or takeaway.',
      );
    }

    if (redeemPoints < 0) {
      throw ArgumentError('Redeemed points cannot be negative.');
    }

    for (final entry in cart.entries) {
      if (entry.key.trim().isEmpty || entry.value <= 0 || entry.value > 10000) {
        throw ArgumentError('Invalid product ID or quantity.');
      }
    }

    final tenantId = cafeId;
    if (tenantId != null) {
      return _functionsService.checkout(
        cafeId: tenantId,
        checkoutId: checkoutId,
        cart: cart,
        orderType: orderType,
        customerPhone: customerPhone,
        redeemPoints: redeemPoints,
      );
    }
    if ((customerPhone != null && customerPhone.trim().isNotEmpty) ||
        redeemPoints > 0) {
      throw StateError(
        'Loyalty checkout requires the trusted café checkout service.',
      );
    }

    final billRef = bills.doc(checkoutId);

    final sortedEntries = cart.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final requestKey = buildCheckoutRequestKey(
      orderType: orderType,
      cart: cart,
    );
    final legacyRequestKey = _buildLegacyCheckoutRequestKey(
      orderType: orderType,
      cart: cart,
    );

    return db.runTransaction<String>((tx) async {
      final existingBill = await tx.get(billRef);
      final existingCheckout = resolveExistingCheckout(
        existingBill: existingBill.data(),
        requestKey: requestKey,
        legacyRequestKey: legacyRequestKey,
        orderType: orderType,
        cart: cart,
        billId: billRef.id,
      );
      if (existingCheckout != null) return existingCheckout;

      final productIds = sortedEntries.map((e) => e.key).toList();

      final productSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};

      final recipeSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};

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

      final recipesForRequirements = <String, Map<String, dynamic>>{};
      final billItems = <Map<String, dynamic>>[];

      for (final entry in sortedEntries) {
        final productId = entry.key;
        final quantity = entry.value;
        final product = productSnaps[productId]!.data()!;
        final recipe = recipeSnaps[productId]!.data()!;

        final unitPricePaise = _currencyMinorUnits(
          product['sellingPrice'],
          'sellingPrice',
        );
        if (unitPricePaise > _maxSafeMinorUnits ~/ quantity) {
          throw StateError('Bill amount is too large.');
        }
        final lineTotalPaise = unitPricePaise * quantity;
        final price = unitPricePaise / 100;

        final ingredientLines =
            _recipeLines(recipe['ingredients'], 'ingredients');

        if (ingredientLines.isEmpty) {
          throw StateError(
            'Product ${product['name']} has an empty recipe.',
          );
        }

        if (orderType == 'takeaway') {
          _recipeLines(recipe['packaging'], 'packaging');
        }
        recipesForRequirements[productId] = recipe;

        billItems.add({
          'productId': productId,
          'name': product['name'] ?? 'Unnamed product',
          'quantity': quantity,
          'unitPrice': price,
          'lineTotal': lineTotalPaise / 100,
        });
      }

      final requiredStock = calculateRequiredStock(
        cart: cart,
        recipes: recipesForRequirements,
        includePackaging: orderType == 'takeaway',
      );

      final stockSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};

      final stockIds = requiredStock.keys.toList()..sort();

      if (stockIds.length > _maxCheckoutStockItems) {
        throw StateError(
          'This order references too many distinct stock items.',
        );
      }

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

      var totalPaise = 0;
      for (final item in billItems) {
        final linePaise = _currencyMinorUnits(item['lineTotal'], 'lineTotal');
        if (totalPaise > _maxSafeMinorUnits - linePaise) {
          throw StateError('Bill total is too large.');
        }
        totalPaise += linePaise;
      }
      final total = totalPaise / 100;

      for (final id in stockIds) {
        final required = requiredStock[id]!;
        final updated = updatedQuantities[id]!;
        final data = stockSnaps[id]!.data()!;

        tx.update(stock.doc(id), {
          'quantity': updated,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final movementRef = movements.doc();

        tx.set(movementRef, {
          'stockItemId': id,
          'stockItemName': data['name'],
          'stockItemUnit': data['unit'],
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

  static String _validateCafeId(String value) {
    if (value.trim().isEmpty || value.contains('/')) {
      throw ArgumentError.value(
          value, 'cafeId', 'Must be a non-empty café ID.');
    }
    return value.trim();
  }

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

  static int _currencyMinorUnits(dynamic value, String field) {
    final amount = _number(value, field);
    if (amount < 0) throw StateError('$field cannot be negative.');
    final scaled = amount * 100;
    if (!scaled.isFinite || scaled > _maxSafeMinorUnits) {
      throw StateError('$field is too large to represent in paise.');
    }
    return scaled.round();
  }

  static void validateRecipe({
    required List<Map<String, dynamic>> ingredients,
    List<Map<String, dynamic>> packaging = const [],
  }) {
    if (ingredients.isEmpty) {
      throw ArgumentError('A recipe must contain at least one ingredient.');
    }
    validateRecipeLines(ingredients, 'ingredients');
    validateRecipeLines(packaging, 'packaging');
  }

  static void validateNewItem(StockItem item) {
    if (item.name.trim().isEmpty) {
      throw ArgumentError('Item name cannot be empty.');
    }
    if (item.category != 'ingredient' && item.category != 'finished') {
      throw ArgumentError('Item category must be ingredient or finished.');
    }
    if (item.unit.trim().isEmpty) {
      throw ArgumentError('Item unit cannot be empty.');
    }
    if (!['recipe', 'direct'].contains(item.stockMode) ||
        (item.category != 'finished' && item.stockMode == 'direct')) {
      throw ArgumentError('Only finished products support direct stock sales.');
    }

    for (final entry in <String, double>{
      'quantity': item.quantity,
      'minimumQuantity': item.minimumQuantity,
      'purchasePricePerUnit': item.purchasePricePerUnit,
      'sellingPrice': item.sellingPrice,
    }.entries) {
      if (!entry.value.isFinite || entry.value < 0) {
        throw ArgumentError('${entry.key} must be finite and non-negative.');
      }
    }
  }

  static String buildCheckoutRequestKey({
    required String orderType,
    required Map<String, int> cart,
  }) {
    final sortedEntries = cart.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return jsonEncode([
      orderType,
      for (final entry in sortedEntries) [entry.key, entry.value],
    ]);
  }

  static String _buildLegacyCheckoutRequestKey({
    required String orderType,
    required Map<String, int> cart,
  }) {
    final sortedEntries = cart.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      orderType,
      for (final entry in sortedEntries) '${entry.key}:${entry.value}',
    ].join('|');
  }

  static String? resolveExistingCheckout({
    required Map<String, dynamic>? existingBill,
    required String requestKey,
    String? legacyRequestKey,
    String? orderType,
    Map<String, int>? cart,
    required String billId,
  }) {
    if (existingBill == null) return null;
    final savedRequestKey = existingBill['requestKey'];
    final legacyRetry = savedRequestKey == legacyRequestKey &&
        legacyRequestKey != null &&
        orderType != null &&
        cart != null &&
        _matchesLegacyBill(
          existingBill: existingBill,
          requestKey: requestKey,
          legacyRequestKey: legacyRequestKey,
        );
    if (savedRequestKey != requestKey && !legacyRetry) {
      throw StateError(
          'This checkout ID was already used for a different bill.');
    }
    return billId;
  }

  static bool _matchesLegacyBill({
    required Map<String, dynamic> existingBill,
    required String requestKey,
    required String legacyRequestKey,
  }) {
    final rawItems = existingBill['items'];
    final orderType = existingBill['orderType'];
    if (rawItems is! List ||
        (orderType != 'dineIn' && orderType != 'takeaway')) {
      return false;
    }
    final savedCart = <String, int>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) return false;
      final item = Map<String, dynamic>.from(rawItem);
      final productId = item['productId'];
      final quantity = item['quantity'];
      if (productId is! String ||
          productId.isEmpty ||
          quantity is! int ||
          quantity <= 0 ||
          savedCart.containsKey(productId)) {
        return false;
      }
      savedCart[productId] = quantity;
    }
    return savedCart.isNotEmpty &&
        buildCheckoutRequestKey(
              orderType: orderType as String,
              cart: savedCart,
            ) ==
            requestKey &&
        _buildLegacyCheckoutRequestKey(
              orderType: orderType,
              cart: savedCart,
            ) ==
            legacyRequestKey;
  }

  static Map<String, double> calculateRequiredStock({
    required Map<String, int> cart,
    required Map<String, Map<String, dynamic>> recipes,
    required bool includePackaging,
  }) {
    final requiredStock = <String, double>{};
    for (final entry in cart.entries) {
      final recipe = recipes[entry.key];
      if (recipe == null) {
        throw StateError('No recipe configured for ${entry.key}.');
      }

      final ingredientLines =
          _recipeLines(recipe['ingredients'], 'ingredients');
      if (ingredientLines.isEmpty) {
        throw StateError('Product ${entry.key} has an empty recipe.');
      }
      for (final line in ingredientLines) {
        _addRequirement(requiredStock, line, entry.value, 'ingredient');
      }

      if (includePackaging) {
        final packagingLines = _recipeLines(recipe['packaging'], 'packaging');
        for (final line in packagingLines) {
          _addRequirement(requiredStock, line, entry.value, 'packaging');
        }
      }
    }
    return requiredStock;
  }

  static void validateRecipeLines(
    List<Map<String, dynamic>> lines,
    String field,
  ) {
    for (final line in lines) {
      final id = line['stockItemId'];
      final quantity = line['quantity'];

      if (id is! String || id.trim().isEmpty) {
        throw ArgumentError('$field entries need a stockItemId.');
      }

      if (quantity is! num || !quantity.toDouble().isFinite || quantity <= 0) {
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
