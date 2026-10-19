const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const {
  CafeOperationError,
  requireActiveMembershipTx,
} = require('./membership_service');
const {
  customerIdForPhone,
  normalizePhoneNumber,
  prepareCheckoutLoyaltyTx,
} = require('./loyalty_service');

const MANAGER_ROLES = ['owner', 'manager'];
const CHECKOUT_ROLES = ['owner', 'manager', 'staff'];

function requiredText(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new CafeOperationError('invalid-argument', `${label} is required.`);
  }
  return value.trim();
}

function requireDocumentId(value, label) {
  const id = requiredText(value, label);
  if (id.includes('/') || id.length > 1500) {
    throw new CafeOperationError('invalid-argument', `${label} is invalid.`);
  }
  return id;
}

function finiteNonNegative(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new CafeOperationError(
      'invalid-argument',
      `${label} must be a finite non-negative number.`,
    );
  }
  return value;
}

function finitePositive(value, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw new CafeOperationError(
      'invalid-argument',
      `${label} must be a finite number greater than zero.`,
    );
  }
  return value;
}

function currencyMinorUnits(value, label) {
  const amount = finiteNonNegative(value, label);
  const scaled = amount * 100;
  if (!Number.isFinite(scaled) || scaled > Number.MAX_SAFE_INTEGER) {
    throw new CafeOperationError(
      'invalid-argument',
      `${label} is too large to represent in paise.`,
    );
  }
  return Math.round(scaled);
}

function normalizeStockItem(input) {
  if (input == null || typeof input !== 'object' || Array.isArray(input)) {
    throw new CafeOperationError('invalid-argument', 'Stock item is required.');
  }
  const name = requiredText(input.name, 'Item name');
  const category = input.category;
  if (category !== 'ingredient' && category !== 'finished') {
    throw new CafeOperationError(
      'invalid-argument',
      'Item category must be ingredient or finished.',
    );
  }
  const unit = requiredText(input.unit, 'Unit');
  const quantity = finiteNonNegative(input.quantity, 'Quantity');
  const minimumQuantity = finiteNonNegative(
    input.minimumQuantity,
    'Minimum quantity',
  );
  const purchasePricePerUnit = finiteNonNegative(
    input.purchasePricePerUnit,
    'Purchase price',
  );
  const sellingPrice = finiteNonNegative(input.sellingPrice, 'Selling price');
  const photoUrl = typeof input.photoUrl === 'string' ? input.photoUrl : '';
  return {
    name,
    category,
    unit,
    quantity,
    minimumQuantity,
    purchasePricePerUnit,
    sellingPrice,
    photoUrl,
  };
}

function validateRecipeLines(lines, label, allowEmpty) {
  if (!Array.isArray(lines) || (!allowEmpty && lines.length === 0) || lines.length > 100) {
    throw new CafeOperationError(
      'invalid-argument',
      `${label} must be a list with a valid number of lines.`,
    );
  }
  return lines.map((line) => {
    if (line == null || typeof line !== 'object' || Array.isArray(line)) {
      throw new CafeOperationError('invalid-argument', `Invalid ${label} line.`);
    }
    return {
      stockItemId: requireDocumentId(line.stockItemId, 'Stock item ID'),
      quantity: finitePositive(line.quantity, `${label} quantity`),
    };
  });
}

async function createStockItem({ db, callerUid, cafeId, item }) {
  callerUid = requireDocumentId(callerUid, 'Authenticated user ID');
  cafeId = requireDocumentId(cafeId, 'Café ID');
  const normalized = normalizeStockItem(item);
  const stockRef = db.collection('stock_items').doc();

  await db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: MANAGER_ROLES,
    });

    transaction.create(stockRef, {
      ...normalized,
      cafeId,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (normalized.quantity > 0) {
      const movementRef = db.collection('stock_movements').doc();
      transaction.create(movementRef, {
        cafeId,
        stockItemId: stockRef.id,
        stockItemName: normalized.name,
        stockItemUnit: normalized.unit,
        type: 'addition',
        quantityChange: normalized.quantity,
        quantityAfter: normalized.quantity,
        reason: 'Opening stock',
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  });
  return { stockItemId: stockRef.id };
}

async function addStock({ db, callerUid, cafeId, stockItemId, quantity, reason }) {
  callerUid = requireDocumentId(callerUid, 'Authenticated user ID');
  cafeId = requireDocumentId(cafeId, 'Café ID');
  stockItemId = requireDocumentId(stockItemId, 'Stock item ID');
  quantity = finitePositive(quantity, 'Quantity');
  reason = typeof reason === 'string' && reason.trim().length > 0
    ? reason.trim().slice(0, 160)
    : 'Stock addition';
  const stockRef = db.collection('stock_items').doc(stockItemId);
  const movementRef = db.collection('stock_movements').doc();

  await db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: MANAGER_ROLES,
    });
    const itemSnapshot = await transaction.get(stockRef);
    const item = itemSnapshot.data();
    if (!itemSnapshot.exists || item.cafeId !== cafeId) {
      throw new CafeOperationError('not-found', 'Stock item not found.');
    }
    const currentQuantity = finiteNonNegative(item.quantity, 'Current quantity');
    const updatedQuantity = currentQuantity + quantity;
    if (!Number.isFinite(updatedQuantity)) {
      throw new CafeOperationError('invalid-argument', 'Stock quantity is too large.');
    }

    transaction.update(stockRef, {
      quantity: updatedQuantity,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.create(movementRef, {
      cafeId,
      stockItemId,
      stockItemName: item.name ?? 'Inventory item',
      stockItemUnit: item.unit ?? '',
      type: 'addition',
      quantityChange: quantity,
      quantityAfter: updatedQuantity,
      reason,
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { stockItemId, quantityAdded: quantity };
}

async function saveRecipe({
  db,
  callerUid,
  cafeId,
  productId,
  ingredients,
  packaging = [],
}) {
  callerUid = requireDocumentId(callerUid, 'Authenticated user ID');
  cafeId = requireDocumentId(cafeId, 'Café ID');
  productId = requireDocumentId(productId, 'Product ID');
  ingredients = validateRecipeLines(ingredients, 'Ingredients', false);
  packaging = validateRecipeLines(packaging, 'Packaging', true);
  const productRef = db.collection('stock_items').doc(productId);
  const recipeRef = db.collection('product_recipes').doc(productId);
  const lineIds = [...new Set([
    ...ingredients.map((line) => line.stockItemId),
    ...packaging.map((line) => line.stockItemId),
  ])].sort();

  await db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: MANAGER_ROLES,
    });
    const productSnapshot = await transaction.get(productRef);
    const product = productSnapshot.data();
    if (!productSnapshot.exists || product.cafeId !== cafeId) {
      throw new CafeOperationError('not-found', 'Finished product not found.');
    }
    if (product.category !== 'finished') {
      throw new CafeOperationError(
        'failed-precondition',
        'Recipes can only be assigned to finished products.',
      );
    }

    const ingredientSnapshots = await Promise.all(
      lineIds.map((id) => transaction.get(db.collection('stock_items').doc(id))),
    );
    for (const snapshot of ingredientSnapshots) {
      const stockItem = snapshot.data();
      if (!snapshot.exists || stockItem.cafeId !== cafeId) {
        throw new CafeOperationError(
          'failed-precondition',
          `Recipe references an unavailable stock item: ${snapshot.id}`,
        );
      }
      if (stockItem.category === 'finished') {
        throw new CafeOperationError(
          'failed-precondition',
          'Recipe ingredients and packaging must not be finished products.',
        );
      }
    }

    transaction.set(recipeRef, {
      cafeId,
      productId,
      ingredients,
      packaging,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { recipeId: productId };
}

function normalizeCart(cart) {
  if (cart == null || typeof cart !== 'object' || Array.isArray(cart)) {
    throw new CafeOperationError('invalid-argument', 'Cart is invalid.');
  }
  const entries = Object.entries(cart);
  if (entries.length === 0 || entries.length > 100) {
    throw new CafeOperationError(
      'invalid-argument',
      'Cart must contain between 1 and 100 product types.',
    );
  }
  const normalized = entries.map(([productId, quantity]) => {
    productId = requireDocumentId(productId, 'Product ID');
    if (!Number.isSafeInteger(quantity) || quantity <= 0 || quantity > 10000) {
      throw new CafeOperationError(
        'invalid-argument',
        'Product quantities must be positive whole numbers no greater than 10,000.',
      );
    }
    return { productId, quantity };
  });
  normalized.sort((left, right) => left.productId.localeCompare(right.productId));
  return normalized;
}

function requestKeyFor(orderType, entries) {
  return JSON.stringify([
    orderType,
    entries.map(({ productId, quantity }) => [productId, quantity]),
  ]);
}

function addRequirement(required, line, productQuantity) {
  const amount = line.quantity * productQuantity;
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new CafeOperationError('invalid-argument', 'Recipe quantity is invalid.');
  }
  const combined = (required.get(line.stockItemId) ?? 0) + amount;
  if (!Number.isFinite(combined)) {
    throw new CafeOperationError('invalid-argument', 'Required stock is too large.');
  }
  required.set(line.stockItemId, combined);
}

async function checkout({
  db,
  callerUid,
  cafeId,
  checkoutId,
  cart,
  orderType,
  customerPhone = null,
  redeemPoints = 0,
}) {
  callerUid = requireDocumentId(callerUid, 'Authenticated user ID');
  cafeId = requireDocumentId(cafeId, 'Café ID');
  checkoutId = requireDocumentId(checkoutId, 'Checkout ID');
  if (orderType !== 'dineIn' && orderType !== 'takeaway') {
    throw new CafeOperationError(
      'invalid-argument',
      'Order type must be dineIn or takeaway.',
    );
  }
  if (!Number.isSafeInteger(redeemPoints) || redeemPoints < 0) {
    throw new CafeOperationError(
      'invalid-argument',
      'Redeemed points must be a non-negative whole number.',
    );
  }
  if ((customerPhone == null || customerPhone === '') && redeemPoints > 0) {
    throw new CafeOperationError(
      'invalid-argument',
      'A customer phone number is required to redeem points.',
    );
  }
  const normalizedPhone = customerPhone == null || customerPhone === ''
    ? null
    : normalizePhoneNumber(customerPhone);
  const customerId = normalizedPhone == null
    ? null
    : customerIdForPhone({ cafeId, phoneNumber: normalizedPhone });
  const entries = normalizeCart(cart);
  const cartRequestKey = requestKeyFor(orderType, entries);
  const requestKey = customerId == null
    ? cartRequestKey
    : JSON.stringify([cartRequestKey, customerId, redeemPoints]);
  const billRef = db.collection('bills').doc(checkoutId);

  return db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: CHECKOUT_ROLES,
    });
    const existingBillSnapshot = await transaction.get(billRef);
    if (existingBillSnapshot.exists) {
      const existingBill = existingBillSnapshot.data();
      if (existingBill.cafeId !== cafeId) {
        throw new CafeOperationError(
          'permission-denied',
          'Checkout ID belongs to another café.',
        );
      }
      if (existingBill.requestKey !== requestKey) {
        throw new CafeOperationError(
          'already-exists',
          'Checkout ID was already used for a different order.',
        );
      }
      return { billId: billRef.id, duplicate: true };
    }

    const productSnapshots = new Map();
    const recipeSnapshots = new Map();
    for (const { productId } of entries) {
      const productRef = db.collection('stock_items').doc(productId);
      const recipeRef = db.collection('product_recipes').doc(productId);
      const [productSnapshot, recipeSnapshot] = await Promise.all([
        transaction.get(productRef),
        transaction.get(recipeRef),
      ]);
      const product = productSnapshot.data();
      const recipe = recipeSnapshot.data();
      if (!productSnapshot.exists || product.cafeId !== cafeId) {
        throw new CafeOperationError('not-found', 'Product not found in this café.');
      }
      if (product.category !== 'finished') {
        throw new CafeOperationError(
          'failed-precondition',
          'Only finished products can be sold.',
        );
      }
      if (!recipeSnapshot.exists || recipe.cafeId !== cafeId ||
          recipe.productId !== productId) {
        throw new CafeOperationError(
          'failed-precondition',
          `No valid recipe configured for ${product.name ?? productId}.`,
        );
      }
      productSnapshots.set(productId, product);
      recipeSnapshots.set(productId, recipe);
    }

    const requiredStock = new Map();
    const billItems = [];
    for (const { productId, quantity } of entries) {
      const product = productSnapshots.get(productId);
      const recipe = recipeSnapshots.get(productId);
      const unitPriceMinor = currencyMinorUnits(
        product.sellingPrice,
        'Selling price',
      );
      const lineTotalMinor = unitPriceMinor * quantity;
      if (!Number.isSafeInteger(lineTotalMinor)) {
        throw new CafeOperationError('invalid-argument', 'Bill amount is too large.');
      }
      const unitPrice = unitPriceMinor / 100;
      const lineTotal = lineTotalMinor / 100;
      const ingredients = validateRecipeLines(recipe.ingredients, 'Ingredients', false);
      const packaging = orderType === 'takeaway'
        ? validateRecipeLines(recipe.packaging ?? [], 'Packaging', true)
        : [];
      for (const line of ingredients) addRequirement(requiredStock, line, quantity);
      for (const line of packaging) addRequirement(requiredStock, line, quantity);
      billItems.push({
        productId,
        name: product.name ?? 'Unnamed product',
        quantity,
        unitPrice,
        lineTotal,
      });
    }

    const stockIds = [...requiredStock.keys()].sort();
    // Each distinct stock item creates one update and one movement, plus the bill.
    // Leave headroom below Firestore's 500-write transaction limit.
    if (stockIds.length > (customerId == null ? 249 : 248)) {
      throw new CafeOperationError(
        'invalid-argument',
        'This order references too many distinct stock items.',
      );
    }
    const stockSnapshots = new Map();
    const updatedQuantities = new Map();
    for (const stockItemId of stockIds) {
      const snapshot = await transaction.get(
        db.collection('stock_items').doc(stockItemId),
      );
      const stockItem = snapshot.data();
      if (!snapshot.exists || stockItem.cafeId !== cafeId) {
        throw new CafeOperationError(
          'failed-precondition',
          `Required stock item is unavailable: ${stockItemId}`,
        );
      }
      if (stockItem.category === 'finished') {
        throw new CafeOperationError(
          'failed-precondition',
          'A recipe cannot deduct another finished product.',
        );
      }
      const current = finiteNonNegative(stockItem.quantity, 'Current stock');
      const needed = requiredStock.get(stockItemId);
      if (current < needed) {
        throw new CafeOperationError(
          'failed-precondition',
          `Insufficient stock for ${stockItem.name ?? stockItemId}.`,
        );
      }
      stockSnapshots.set(stockItemId, stockItem);
      updatedQuantities.set(stockItemId, current - needed);
    }

    const totalMinor = billItems.reduce((sum, item) => {
      const lineMinor = currencyMinorUnits(item.lineTotal, 'Line total');
      const next = sum + lineMinor;
      if (!Number.isSafeInteger(next)) {
        throw new CafeOperationError('invalid-argument', 'Bill amount is too large.');
      }
      return next;
    }, 0);
    if (!Number.isSafeInteger(totalMinor)) {
      throw new CafeOperationError('invalid-argument', 'Bill total is too large.');
    }
    const checkoutLoyalty = await prepareCheckoutLoyaltyTx({
      transaction,
      db,
      cafeId,
      billId: billRef.id,
      phoneNumber: normalizedPhone,
      redeemPoints,
      subtotalMinor: totalMinor,
    });
    for (const stockItemId of stockIds) {
      const stockItem = stockSnapshots.get(stockItemId);
      const quantityChange = requiredStock.get(stockItemId);
      const quantityAfter = updatedQuantities.get(stockItemId);
      transaction.update(db.collection('stock_items').doc(stockItemId), {
        quantity: quantityAfter,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(db.collection('stock_movements').doc(), {
        cafeId,
        stockItemId,
        stockItemName: stockItem.name ?? 'Inventory item',
        stockItemUnit: stockItem.unit ?? '',
        type: 'sale',
        quantityChange: -quantityChange,
        quantityAfter,
        reason: `Checkout ${billRef.id} (${orderType})`,
        billId: billRef.id,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.create(billRef, {
      cafeId,
      billId: billRef.id,
      requestKey,
      orderType,
      items: billItems,
      subtotal: totalMinor / 100,
      total: checkoutLoyalty.netPaidMinor / 100,
      discount: checkoutLoyalty.discountMinor / 100,
      ...(checkoutLoyalty.customerId == null ? {} : {
        loyalty: {
          customerId: checkoutLoyalty.customerId,
          pointsEarned: checkoutLoyalty.pointsEarned,
          pointsRedeemed: checkoutLoyalty.pointsRedeemed,
          pointsBalanceAfter: checkoutLoyalty.balanceAfter,
        },
      }),
      status: 'completed',
      createdAt: FieldValue.serverTimestamp(),
    });
    return {
      billId: billRef.id,
      duplicate: false,
      ...(checkoutLoyalty.customerId == null ? {} : {
        pointsEarned: checkoutLoyalty.pointsEarned,
        pointsRedeemed: checkoutLoyalty.pointsRedeemed,
      }),
    };
  });
}

function parseReportDate(value, label) {
  if (typeof value !== 'string') {
    throw new CafeOperationError('invalid-argument', `${label} must be an ISO date.`);
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds)) {
    throw new CafeOperationError('invalid-argument', `${label} must be a valid date.`);
  }
  return new Date(milliseconds);
}

async function getSalesSummary({ db, callerUid, cafeId, startAt, endAt }) {
  callerUid = requireDocumentId(callerUid, 'Authenticated user ID');
  cafeId = requireDocumentId(cafeId, 'Café ID');
  const start = parseReportDate(startAt, 'Start date');
  const end = parseReportDate(endAt, 'End date');
  const rangeMs = end.getTime() - start.getTime();
  if (rangeMs <= 0 || rangeMs > 31 * 24 * 60 * 60 * 1000) {
    throw new CafeOperationError(
      'invalid-argument',
      'Sales reports must cover a positive range of no more than 31 days.',
    );
  }

  const billsQuery = db.collection('bills')
    .where('cafeId', '==', cafeId)
    .where('createdAt', '>=', Timestamp.fromDate(start))
    .where('createdAt', '<', Timestamp.fromDate(end))
    .limit(5001);
  const billsSnapshot = await db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: CHECKOUT_ROLES,
    });
    return transaction.get(billsQuery);
  });
  if (billsSnapshot.size > 5000) {
    throw new CafeOperationError(
      'resource-exhausted',
      'This report contains too many bills. Choose a shorter date range.',
    );
  }

  let grossRevenueMinor = 0;
  let completedBillCount = 0;
  let itemsSold = 0;
  const productTotals = new Map();
  for (const snapshot of billsSnapshot.docs) {
    const bill = snapshot.data();
    if (bill.status !== 'completed' && bill.status !== 'partially_refunded') continue;
    const totalMinor = currencyMinorUnits(bill.total, 'Saved bill total');
    const refundedMinor = bill.refundedMinor ?? 0;
    if (!Number.isSafeInteger(refundedMinor) || refundedMinor < 0 ||
        refundedMinor > totalMinor) {
      throw new CafeOperationError('failed-precondition', 'Saved bill refund total is invalid.');
    }
    const retainedMinor = totalMinor - refundedMinor;
    if (!Array.isArray(bill.items)) {
      throw new CafeOperationError(
        'failed-precondition',
        `Bill ${snapshot.id} has no valid saved items.`,
      );
    }
    grossRevenueMinor += retainedMinor;
    if (!Number.isSafeInteger(grossRevenueMinor)) {
      throw new CafeOperationError('failed-precondition', 'Sales total is invalid.');
    }
    completedBillCount += 1;
    for (const line of bill.items) {
      if (line == null || typeof line !== 'object' || Array.isArray(line) ||
          typeof line.productId !== 'string' || line.productId.length === 0 ||
          !Number.isSafeInteger(line.quantity) || line.quantity <= 0) {
        throw new CafeOperationError(
          'failed-precondition',
          `Bill ${snapshot.id} contains an invalid product line.`,
        );
      }
      const savedLineRevenueMinor = currencyMinorUnits(
        line.lineTotal,
        'Saved line total',
      );
      const lineRevenueMinor = totalMinor === 0
        ? 0
        : Math.round(savedLineRevenueMinor * retainedMinor / totalMinor);
      itemsSold += line.quantity;
      const previous = productTotals.get(line.productId) ?? {
        productId: line.productId,
        name: typeof line.name === 'string' ? line.name : 'Unnamed product',
        quantitySold: 0,
        revenueMinor: 0,
      };
      previous.quantitySold += line.quantity;
      previous.revenueMinor += lineRevenueMinor;
      if (!Number.isSafeInteger(previous.quantitySold) ||
          !Number.isSafeInteger(previous.revenueMinor)) {
        throw new CafeOperationError('failed-precondition', 'Product totals are invalid.');
      }
      productTotals.set(line.productId, previous);
    }
  }

  const bestSellingProducts = [...productTotals.values()]
    .sort((left, right) =>
      right.quantitySold - left.quantitySold ||
      right.revenueMinor - left.revenueMinor ||
      left.productId.localeCompare(right.productId))
    .slice(0, 10);
  return {
    startAt: start.toISOString(),
    endAt: end.toISOString(),
    completedBillCount,
    grossRevenue: grossRevenueMinor / 100,
    itemsSold,
    bestSellingProducts: bestSellingProducts.map(({ revenueMinor, ...product }) => ({
      ...product,
      revenue: revenueMinor / 100,
    })),
  };
}

module.exports = {
  addStock,
  checkout,
  createStockItem,
  getSalesSummary,
  saveRecipe,
};
