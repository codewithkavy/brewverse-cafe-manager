const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const {
  CafeOperationError,
  createCafe,
  grantCafeMembership,
  revokeCafeMembership,
} = require('../src/membership_service');
const {
  addStock,
  checkout,
  createStockItem,
  getSalesSummary,
  saveRecipe,
} = require('../src/inventory_service');
const { customerIdForPhone, lookupLoyaltyCustomer } = require('../src/loyalty_service');
const { refundBill, voidBill } = require('../src/billing_service');

const projectId = 'brewverse-security-tests';
let app;
let db;
let testRun;

before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('Refusing to run backend tests without Firestore Emulator.');
  }
  if (process.env.GCLOUD_PROJECT !== projectId) {
    throw new Error(`Refusing to run against project ${process.env.GCLOUD_PROJECT}.`);
  }
  testRun = `inventory-${Date.now()}`;
  app = initializeApp({ projectId }, testRun);
  db = getFirestore(app);
});

after(async () => {
  if (app) await deleteApp(app);
});

async function setupCafe() {
  const { cafeId } = await createCafe({
    db,
    uid: `${testRun}-owner`,
    name: 'Inventory Test Cafe',
  });
  await grantCafeMembership({
    db,
    callerUid: `${testRun}-owner`,
    cafeId,
    targetUid: `${testRun}-manager`,
    role: 'manager',
  });
  await grantCafeMembership({
    db,
    callerUid: `${testRun}-owner`,
    cafeId,
    targetUid: `${testRun}-staff`,
    role: 'staff',
  });
  return cafeId;
}

async function stock(cafeId, values = {}) {
  const ref = db.collection('stock_items').doc();
  await ref.set({
    cafeId,
    name: 'Espresso beans',
    category: 'ingredient',
    unit: 'g',
    quantity: 100,
    minimumQuantity: 0,
    purchasePricePerUnit: 0.1,
    sellingPrice: 0,
    ...values,
  });
  return ref.id;
}

async function movements(cafeId, stockItemId) {
  const snapshot = await db.collection('stock_movements')
    .where('cafeId', '==', cafeId)
    .where('stockItemId', '==', stockItemId)
    .get();
  return snapshot.docs.map((doc) => doc.data());
}

test('opening stock and replenishment each create a matching movement', async () => {
  const cafeId = await setupCafe();
  const created = await createStockItem({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    item: {
      name: 'Milk', category: 'ingredient', unit: 'ml', quantity: 20,
      minimumQuantity: 2, purchasePricePerUnit: 0.04, sellingPrice: 0,
    },
  });
  await addStock({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    stockItemId: created.stockItemId,
    quantity: 5,
    reason: 'Delivery',
  });

  const item = await db.collection('stock_items').doc(created.stockItemId).get();
  const records = await movements(cafeId, created.stockItemId);
  assert.equal(item.data().quantity, 25);
  assert.deepEqual(records.map(({ type, quantityChange, quantityAfter }) =>
    ({ type, quantityChange, quantityAfter }))
    .sort((left, right) => left.quantityChange - right.quantityChange), [
    { type: 'addition', quantityChange: 5, quantityAfter: 25 },
    { type: 'addition', quantityChange: 20, quantityAfter: 20 },
  ]);
});

test('stock item creation retries create one item and opening movement and retain the original request after edits', async () => {
  const cafeId = await setupCafe();
  const request = { db, callerUid: `${testRun}-manager`, cafeId,
    operationId: `${testRun}-item-once`, item: {
      name: 'Durable milk', category: 'ingredient', unit: 'ml', quantity: 20,
      minimumQuantity: 2, purchasePricePerUnit: 0.04, sellingPrice: 0,
    } };
  const results = await Promise.all(Array.from({ length: 4 }, () => createStockItem(request)));
  assert.equal(results.filter(result => !result.duplicate).length, 1);
  assert.equal(results.filter(result => result.duplicate).length, 3);
  assert.equal(new Set(results.map(result => result.stockItemId)).size, 1);
  const stockItemId = results[0].stockItemId;
  assert.equal((await movements(cafeId, stockItemId)).length, 1);
  await addStock({ db, callerUid: `${testRun}-owner`, cafeId, stockItemId,
    quantity: 5, reason: 'Later delivery', operationId: `${testRun}-later-delivery` });
  await db.collection('stock_items').doc(stockItemId).update({ name: 'Renamed milk' });
  const item = (await db.collection('stock_items').doc(stockItemId).get()).data();
  const priorMovements = await movements(cafeId, stockItemId);
  assert.equal((await createStockItem(request)).duplicate, true);
  assert.deepEqual((await db.collection('stock_items').doc(stockItemId).get()).data(), item);
  assert.deepEqual(await movements(cafeId, stockItemId), priorMovements);
  await assert.rejects(createStockItem({ ...request, item: { ...request.item, quantity: 30 } }), error =>
    error instanceof CafeOperationError && error.code === 'already-exists');
  await assert.rejects(createStockItem({ ...request, callerUid: `${testRun}-owner` }), error =>
    error instanceof CafeOperationError && error.code === 'already-exists');
  await revokeCafeMembership({ db, callerUid: `${testRun}-owner`, cafeId,
    targetUid: `${testRun}-manager` });
  await assert.rejects(createStockItem(request), error =>
    error instanceof CafeOperationError && error.code === 'permission-denied');
  assert.deepEqual((await db.collection('stock_items').doc(stockItemId).get()).data(), item);
  assert.deepEqual(await movements(cafeId, stockItemId), priorMovements);
});

test('stock addition operation IDs deduplicate concurrent calls and lost-response retries', async () => {
  const cafeId = await setupCafe();
  const stockItemId = await stock(cafeId, { quantity: 10 });
  const request = { db, callerUid: `${testRun}-manager`, cafeId, stockItemId,
    quantity: 5, reason: 'Delivery', operationId: `${testRun}-delivery-once` };
  const results = await Promise.all(Array.from({ length: 4 }, () => addStock(request)));
  assert.equal(results.filter(result => !result.duplicate).length, 1);
  assert.equal(results.filter(result => result.duplicate).length, 3);
  assert.equal(new Set(results.map(result => result.movementId)).size, 1);
  assert(results.every(result => result.quantityAfter === 15));
  const item = await db.collection('stock_items').doc(stockItemId).get();
  const beforeMovements = await movements(cafeId, stockItemId);
  assert.equal(item.data().quantity, 15);
  assert.equal(beforeMovements.length, 1);
  assert.equal((await addStock(request)).duplicate, true);
  assert.deepEqual((await db.collection('stock_items').doc(stockItemId).get()).data(), item.data());
  assert.deepEqual(await movements(cafeId, stockItemId), beforeMovements);
  for (const override of [{ quantity: 6 }, { reason: 'Another delivery' }]) {
    await assert.rejects(addStock({ ...request, ...override }), error =>
      error instanceof CafeOperationError && error.code === 'already-exists');
  }
  assert.deepEqual((await db.collection('stock_items').doc(stockItemId).get()).data(), item.data());
  assert.deepEqual(await movements(cafeId, stockItemId), beforeMovements);
});

test('stock addition deduplication does not bypass current authorization or cafe isolation', async () => {
  const cafeId = await setupCafe();
  const stockItemId = await stock(cafeId, { quantity: 10 });
  const request = { db, callerUid: `${testRun}-manager`, cafeId, stockItemId,
    quantity: 2, reason: 'Delivery', operationId: `${testRun}-authorized-delivery` };
  await addStock(request);
  await assert.rejects(addStock({ ...request, callerUid: `${testRun}-owner` }), error =>
    error instanceof CafeOperationError && error.code === 'already-exists');
  await revokeCafeMembership({ db, callerUid: `${testRun}-owner`, cafeId,
    targetUid: `${testRun}-manager` });
  await assert.rejects(addStock(request), error =>
    error instanceof CafeOperationError && error.code === 'permission-denied');
  const foreignCafe = await setupCafe();
  await assert.rejects(addStock({ ...request, callerUid: `${testRun}-owner`, cafeId: foreignCafe }), error =>
    error instanceof CafeOperationError && error.code === 'not-found');
  assert.equal((await db.collection('stock_items').doc(stockItemId).get()).data().quantity, 12);
  assert.equal((await movements(cafeId, stockItemId)).length, 1);
});

test('staff checkout deducts recipe stock once and retry returns the same bill', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 50 });
  const productId = await stock(cafeId, {
    name: 'Latte', category: 'finished', unit: 'cup', quantity: 0, sellingPrice: 6.5,
  });
  await saveRecipe({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 10 }],
    packaging: [{ stockItemId: ingredientId, quantity: 1 }],
  });
  const input = {
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    checkoutId: `${testRun}-checkout-success`,
    cart: { [productId]: 2 },
    orderType: 'takeaway',
  };

  const first = await checkout(input);
  const retry = await checkout(input);
  const item = await db.collection('stock_items').doc(ingredientId).get();
  const bills = await db.collection('bills').where('cafeId', '==', cafeId).get();
  const records = await movements(cafeId, ingredientId);
  assert.deepEqual(first, { billId: input.checkoutId, duplicate: false });
  assert.deepEqual(retry, { billId: input.checkoutId, duplicate: true });
  assert.equal(item.data().quantity, 28);
  assert.equal(bills.size, 1);
  assert.equal(records.length, 1);
  assert.equal(records[0].quantityChange, -22);
  assert.equal((await bills.docs[0].data().total), 13);
  assert.equal(bills.docs[0].data().cashierUid, input.callerUid);
});

test('inventory creation stores explicit direct mode and defaults existing input to recipes', async () => {
  const cafeId = await setupCafe();
  const item = {
    name: 'Bottled water', category: 'finished', unit: 'bottle', quantity: 5,
    minimumQuantity: 1, purchasePricePerUnit: 10, sellingPrice: 20,
  };
  const direct = await createStockItem({
    db, callerUid: `${testRun}-manager`, cafeId,
    item: { ...item, stockMode: 'direct' },
  });
  assert.equal((await db.collection('stock_items').doc(direct.stockItemId).get())
    .data().stockMode, 'direct');
  const recipe = await createStockItem({
    db, callerUid: `${testRun}-manager`, cafeId, item,
  });
  assert.equal((await db.collection('stock_items').doc(recipe.stockItemId).get())
    .data().stockMode, 'recipe');
  for (const invalid of [
    { ...item, stockMode: 'unknown' },
    { ...item, category: 'ingredient', stockMode: 'direct' },
  ]) {
    await assert.rejects(
      createStockItem({ db, callerUid: `${testRun}-manager`, cafeId, item: invalid }),
      (error) => error instanceof CafeOperationError && error.code === 'invalid-argument',
    );
  }
});

test('mixed checkout deducts direct products and aggregates shared recipe ingredients and packaging', async () => {
  const cafeId = await setupCafe();
  const beansId = await stock(cafeId, { quantity: 100 });
  const cupId = await stock(cafeId, { name: 'Cup', unit: 'piece', quantity: 10 });
  const firstProduct = await stock(cafeId, {
    name: 'Latte', category: 'finished', quantity: 0, sellingPrice: 50,
  });
  const secondProduct = await stock(cafeId, {
    name: 'Espresso', category: 'finished', quantity: 0, sellingPrice: 30,
  });
  const directProduct = await stock(cafeId, {
    name: 'Water', category: 'finished', stockMode: 'direct', unit: 'bottle',
    quantity: 5, sellingPrice: 20,
  });
  await saveRecipe({
    db, callerUid: `${testRun}-manager`, cafeId, productId: firstProduct,
    ingredients: [
      { stockItemId: beansId, quantity: 5 },
      { stockItemId: beansId, quantity: 2 },
    ],
    packaging: [{ stockItemId: cupId, quantity: 1 }],
  });
  await saveRecipe({
    db, callerUid: `${testRun}-manager`, cafeId, productId: secondProduct,
    ingredients: [{ stockItemId: beansId, quantity: 3 }],
    packaging: [{ stockItemId: cupId, quantity: 1 }],
  });
  const input = {
    db, callerUid: `${testRun}-staff`, cafeId,
    checkoutId: `${testRun}-mixed`,
    cart: { [firstProduct]: 2, [secondProduct]: 1, [directProduct]: 3 },
    orderType: 'takeaway',
  };
  await checkout(input);
  await checkout(input);
  assert.equal((await db.collection('stock_items').doc(beansId).get()).data().quantity, 83);
  assert.equal((await db.collection('stock_items').doc(cupId).get()).data().quantity, 7);
  assert.equal((await db.collection('stock_items').doc(directProduct).get()).data().quantity, 2);
  assert.equal((await db.collection('stock_items').doc(firstProduct).get()).data().quantity, 0);
  const bill = (await db.collection('bills').doc(input.checkoutId).get()).data();
  assert.equal(bill.items.length, 3);
  assert.equal(bill.total, 190);
  assert.equal((await movements(cafeId, beansId)).length, 1);
  assert.equal((await movements(cafeId, cupId)).length, 1);
  assert.equal((await movements(cafeId, directProduct)).length, 1);
  assert.equal((await movements(cafeId, directProduct))[0].quantityChange, -3);
});

for (const orderType of ['dineIn', 'takeaway']) {
  test(`${orderType} multiplies shared ingredients and deducts packaging only for takeaway`, async () => {
    const cafeId = await setupCafe();
    const ingredientId = await stock(cafeId, { quantity: 100 });
    const packageId = await stock(cafeId, {
      name: 'Takeaway box', unit: 'piece', quantity: orderType === 'takeaway' ? 10 : 0,
    });
    const products = [];
    for (const [name, ingredientQuantity, packageQuantity] of [
      ['Small latte', 2, 1], ['Large latte', 3, 2],
    ]) {
      const productId = await stock(cafeId, {
        name, category: 'finished', quantity: 0, sellingPrice: 20,
      });
      await saveRecipe({
        db, callerUid: `${testRun}-manager`, cafeId, productId,
        ingredients: [{ stockItemId: ingredientId, quantity: ingredientQuantity }],
        packaging: [{ stockItemId: packageId, quantity: packageQuantity }],
      });
      products.push(productId);
    }
    const billId = `${testRun}-${orderType}-packaging-policy`;
    await checkout({
      db, callerUid: `${testRun}-staff`, cafeId, checkoutId: billId,
      cart: { [products[0]]: 2, [products[1]]: 3 }, orderType,
    });
    const ingredientMoves = await movements(cafeId, ingredientId);
    assert.equal(ingredientMoves.length, 1);
    const move = ingredientMoves[0];
    assert.equal(move.billId, billId);
    assert.equal(move.cafeId, cafeId);
    assert.equal(move.stockItemId, ingredientId);
    assert.equal(move.type, 'sale');
    assert.equal(move.quantityChange, -13);
    assert.equal(move.quantityAfter, 87);
    assert.equal(move.reason, `Checkout ${billId} (${orderType})`);
    assert.ok(move.createdAt instanceof Timestamp);
    assert.equal((await db.collection('stock_items').doc(ingredientId).get()).data().quantity, 87);
    const packageMoves = await movements(cafeId, packageId);
    if (orderType === 'takeaway') {
      assert.equal(packageMoves.length, 1);
      assert.equal(packageMoves[0].billId, billId);
      assert.equal(packageMoves[0].quantityChange, -8);
      assert.equal(packageMoves[0].quantityAfter, 2);
      assert.equal((await db.collection('stock_items').doc(packageId).get()).data().quantity, 2);
    } else {
      assert.equal(packageMoves.length, 0);
      assert.equal((await db.collection('stock_items').doc(packageId).get()).data().quantity, 0);
    }
    const bill = (await db.collection('bills').doc(billId).get()).data();
    assert.equal(bill.items.length, 2);
    assert.equal(bill.total, 100);
  });
}

test('takeaway packaging shortage atomically preserves ingredients, direct stock, loyalty and bill', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 20 });
  const packageId = await stock(cafeId, { name: 'Box', quantity: 1 });
  const recipeProduct = await stock(cafeId, {
    name: 'Latte', category: 'finished', quantity: 0, sellingPrice: 100,
  });
  const directProduct = await stock(cafeId, {
    name: 'Water', category: 'finished', stockMode: 'direct', quantity: 10, sellingPrice: 20,
  });
  await saveRecipe({
    db, callerUid: `${testRun}-manager`, cafeId, productId: recipeProduct,
    ingredients: [{ stockItemId: ingredientId, quantity: 2 }],
    packaging: [{ stockItemId: packageId, quantity: 1 }],
  });
  const stockIds = [ingredientId, packageId, directProduct];
  const before = await Promise.all(stockIds.map(async id =>
    (await db.collection('stock_items').doc(id).get()).data()));
  const billId = `${testRun}-packaging-shortage`;
  await assert.rejects(checkout({
    db, callerUid: `${testRun}-staff`, cafeId, checkoutId: billId,
    cart: { [recipeProduct]: 2, [directProduct]: 3 }, orderType: 'takeaway',
    customerPhone: '+919876543210',
  }), error => error instanceof CafeOperationError && error.code === 'failed-precondition');
  assert.deepEqual(await Promise.all(stockIds.map(async id =>
    (await db.collection('stock_items').doc(id).get()).data())), before);
  assert.equal((await db.collection('bills').doc(billId).get()).exists, false);
  for (const stockId of stockIds) assert.equal((await movements(cafeId, stockId)).length, 0);
  for (const collection of ['loyaltyCustomers', 'loyaltyTransactions']) {
    assert.equal((await db.collection('cafes').doc(cafeId).collection(collection).get()).size, 0);
  }
});

test('concurrent takeaway orders cannot oversell the final packaging unit', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 20 });
  const packageId = await stock(cafeId, { name: 'Last box', quantity: 1 });
  const productId = await stock(cafeId, {
    name: 'Latte', category: 'finished', quantity: 0, sellingPrice: 100,
  });
  await saveRecipe({
    db, callerUid: `${testRun}-manager`, cafeId, productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 2 }],
    packaging: [{ stockItemId: packageId, quantity: 1 }],
  });
  const attempts = await Promise.allSettled(['staff', 'manager'].map(role => checkout({
    db, callerUid: `${testRun}-${role}`, cafeId,
    checkoutId: `${testRun}-last-package-${role}`, cart: { [productId]: 1 }, orderType: 'takeaway',
  })));
  assert.equal(attempts.filter(result => result.status === 'fulfilled').length, 1);
  const rejected = attempts.find(result => result.status === 'rejected').reason;
  assert.ok(rejected instanceof CafeOperationError);
  assert.equal(rejected.code, 'failed-precondition');
  assert.equal((await db.collection('stock_items').doc(ingredientId).get()).data().quantity, 18);
  assert.equal((await db.collection('stock_items').doc(packageId).get()).data().quantity, 0);
  assert.equal((await db.collection('bills').where('cafeId', '==', cafeId).get()).size, 1);
  for (const stockId of [ingredientId, packageId]) assert.equal((await movements(cafeId, stockId)).length, 1);
});

test('missing recipes never silently turn existing products into direct stock', async () => {
  const cafeId = await setupCafe();
  const productId = await stock(cafeId, {
    name: 'Unconfigured product', category: 'finished', quantity: 10, sellingPrice: 20,
  });
  const input = {
    db, callerUid: `${testRun}-staff`, cafeId,
    checkoutId: `${testRun}-missing-recipe`, cart: { [productId]: 1 }, orderType: 'dineIn',
  };
  await assert.rejects(checkout(input), (error) =>
    error instanceof CafeOperationError && error.code === 'failed-precondition' &&
    error.message.includes('recipe'));
  assert.equal((await db.collection('stock_items').doc(productId).get()).data().quantity, 10);
  assert.equal((await db.collection('bills').doc(input.checkoutId).get()).exists, false);
  assert.equal((await movements(cafeId, productId)).length, 0);
});

test('recipe stock cannot consume a direct finished product even when it is also in the cart', async () => {
  const cafeId = await setupCafe();
  const directProduct = await stock(cafeId, {
    name: 'Bottle', category: 'finished', stockMode: 'direct', quantity: 10, sellingPrice: 20,
  });
  const recipeProduct = await stock(cafeId, {
    name: 'Invalid recipe', category: 'finished', quantity: 0, sellingPrice: 30,
  });
  await assert.rejects(
    saveRecipe({
      db, callerUid: `${testRun}-manager`, cafeId, productId: directProduct,
      ingredients: [{ stockItemId: directProduct, quantity: 1 }],
    }),
    (error) => error instanceof CafeOperationError && error.code === 'failed-precondition',
  );
  // Simulate an invalid imported recipe; checkout must still validate it.
  await db.collection('product_recipes').doc(recipeProduct).set({
    cafeId, productId: recipeProduct,
    ingredients: [{ stockItemId: directProduct, quantity: 1 }], packaging: [],
  });
  const input = {
    db, callerUid: `${testRun}-staff`, cafeId,
    checkoutId: `${testRun}-invalid-direct-recipe`,
    cart: { [directProduct]: 1, [recipeProduct]: 1 }, orderType: 'dineIn',
  };
  await assert.rejects(checkout(input), (error) =>
    error instanceof CafeOperationError && error.code === 'failed-precondition');
  assert.equal((await db.collection('stock_items').doc(directProduct).get()).data().quantity, 10);
  assert.equal((await db.collection('bills').doc(input.checkoutId).get()).exists, false);
});

test('two cashiers competing for the last recipe ingredients cannot oversell', async () => {
  const cafeId = await setupCafe();
  const beansId = await stock(cafeId, { quantity: 10 });
  const productId = await stock(cafeId, {
    name: 'Last latte', category: 'finished', quantity: 0, sellingPrice: 50,
  });
  await saveRecipe({
    db, callerUid: `${testRun}-manager`, cafeId, productId,
    ingredients: [{ stockItemId: beansId, quantity: 10 }],
  });
  const input = {
    db, cafeId, cart: { [productId]: 1 }, orderType: 'dineIn',
  };
  const attempts = await Promise.allSettled([
    checkout({ ...input, callerUid: `${testRun}-staff`, checkoutId: `${testRun}-race-staff` }),
    checkout({ ...input, callerUid: `${testRun}-manager`, checkoutId: `${testRun}-race-manager` }),
  ]);
  assert.equal(attempts.filter(({ status }) => status === 'fulfilled').length, 1);
  const failure = attempts.find(({ status }) => status === 'rejected').reason;
  assert.ok(failure instanceof CafeOperationError);
  assert.equal(failure.code, 'failed-precondition');
  assert.equal((await db.collection('stock_items').doc(beansId).get()).data().quantity, 0);
  assert.equal((await db.collection('bills').where('cafeId', '==', cafeId).get()).size, 1);
  assert.equal((await movements(cafeId, beansId)).length, 1);
});

test('simultaneous retries of one checkout create one bill and one stock deduction', async () => {
  const cafeId = await setupCafe();
  const productId = await stock(cafeId, {
    name: 'Water', category: 'finished', stockMode: 'direct', quantity: 5, sellingPrice: 20,
  });
  const input = {
    db, callerUid: `${testRun}-staff`, cafeId,
    checkoutId: `${testRun}-concurrent-retry`, cart: { [productId]: 2 }, orderType: 'dineIn',
  };
  const results = await Promise.all(Array.from({ length: 4 }, () => checkout(input)));
  assert.equal(results.filter(({ duplicate }) => !duplicate).length, 1);
  assert.equal(results.filter(({ duplicate }) => duplicate).length, 3);
  assert.ok(results.every(({ billId }) => billId === input.checkoutId));
  assert.equal((await db.collection('stock_items').doc(productId).get()).data().quantity, 3);
  assert.equal((await db.collection('bills').where('cafeId', '==', cafeId).get()).size, 1);
  assert.equal((await movements(cafeId, productId)).length, 1);
});

test('insufficient ingredients roll back every stock item and the bill atomically', async () => {
  const cafeId = await setupCafe();
  const beansId = await stock(cafeId, { quantity: 10 });
  const milkId = await stock(cafeId, { name: 'Milk', quantity: 1 });
  const productId = await stock(cafeId, {
    name: 'Latte', category: 'finished', quantity: 0, sellingPrice: 50,
  });
  await saveRecipe({
    db, callerUid: `${testRun}-manager`, cafeId, productId,
    ingredients: [
      { stockItemId: beansId, quantity: 5 },
      { stockItemId: milkId, quantity: 2 },
    ],
  });
  const input = {
    db, callerUid: `${testRun}-staff`, cafeId,
    checkoutId: `${testRun}-atomic-shortage`, cart: { [productId]: 1 }, orderType: 'dineIn',
  };
  await assert.rejects(checkout(input), (error) =>
    error instanceof CafeOperationError && error.code === 'failed-precondition');
  assert.equal((await db.collection('stock_items').doc(beansId).get()).data().quantity, 10);
  assert.equal((await db.collection('stock_items').doc(milkId).get()).data().quantity, 1);
  assert.equal((await db.collection('bills').doc(input.checkoutId).get()).exists, false);
  assert.equal((await movements(cafeId, beansId)).length, 0);
  assert.equal((await movements(cafeId, milkId)).length, 0);
});

test('decimal ingredient arithmetic tolerates only floating-point rounding and never saves negative stock', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 0.3 });
  const productId = await stock(cafeId, {
    name: 'Fractional recipe', category: 'finished', quantity: 0, sellingPrice: 1,
  });
  await saveRecipe({
    db, callerUid: `${testRun}-manager`, cafeId, productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 0.1 }],
  });
  const input = {
    db, callerUid: `${testRun}-staff`, cafeId,
    checkoutId: `${testRun}-decimal-exact`, cart: { [productId]: 3 }, orderType: 'dineIn',
  };
  await checkout(input);
  assert.equal((await db.collection('stock_items').doc(ingredientId).get()).data().quantity, 0);
  for (const [label, available, required] of [
    ['real-shortage', 0.29999, 0.3],
    ['tiny-shortage', 1e-20, 2e-20],
    ['large-shortage', 1e15, 1e15 + 0.125],
  ]) {
    await db.collection('stock_items').doc(ingredientId).update({ quantity: available });
    await saveRecipe({
      db, callerUid: `${testRun}-manager`, cafeId, productId,
      ingredients: [{ stockItemId: ingredientId, quantity: required }],
    });
    const rejected = {
      ...input, checkoutId: `${testRun}-${label}`, cart: { [productId]: 1 },
    };
    await assert.rejects(checkout(rejected), (error) =>
      error instanceof CafeOperationError && error.code === 'failed-precondition');
    assert.equal((await db.collection('stock_items').doc(ingredientId).get()).data().quantity, available);
    assert.equal((await db.collection('bills').doc(rejected.checkoutId).get()).exists, false);
  }
});

test('checkout denies revoked or foreign cashiers, foreign products, and reuse by another cashier or café', async () => {
  const cafeId = await setupCafe();
  const otherCafeId = await setupCafe();
  const productId = await stock(cafeId, {
    name: 'Water', category: 'finished', stockMode: 'direct', quantity: 10, sellingPrice: 20,
  });
  const foreignProductId = await stock(otherCafeId, {
    name: 'Other water', category: 'finished', stockMode: 'direct', quantity: 10, sellingPrice: 20,
  });
  const input = {
    db, callerUid: `${testRun}-staff`, cafeId,
    checkoutId: `${testRun}-cashier-bound`, cart: { [productId]: 1 }, orderType: 'dineIn',
  };
  await checkout(input);
  await assert.rejects(
    checkout({ ...input, callerUid: `${testRun}-manager` }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  await assert.rejects(
    checkout({ ...input, cafeId: otherCafeId, cart: { [foreignProductId]: 1 } }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  await assert.rejects(
    checkout({ ...input, checkoutId: `${testRun}-foreign-product`, cart: { [foreignProductId]: 1 } }),
    (error) => error instanceof CafeOperationError && error.code === 'not-found',
  );
  await assert.rejects(
    checkout({ ...input, checkoutId: `${testRun}-foreign-cashier`, callerUid: `${testRun}-outsider` }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  await revokeCafeMembership({
    db, callerUid: `${testRun}-owner`, cafeId, targetUid: input.callerUid,
  });
  // Even a matching retry cannot bypass current membership revocation.
  await assert.rejects(checkout(input), (error) =>
    error instanceof CafeOperationError && error.code === 'permission-denied');
  await assert.rejects(
    checkout({ ...input, checkoutId: `${testRun}-revoked-new` }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  assert.equal((await db.collection('stock_items').doc(productId).get()).data().quantity, 9);
  assert.equal((await db.collection('stock_items').doc(foreignProductId).get()).data().quantity, 10);
  assert.equal((await db.collection('bills').where('cafeId', '==', cafeId).get()).size, 1);
});

test('matching retries of older bills without cashierUid remain read-only for active café cashiers', async () => {
  const cafeId = await setupCafe();
  const productId = await stock(cafeId, {
    name: 'Water', category: 'finished', stockMode: 'direct', quantity: 10, sellingPrice: 20,
  });
  const checkoutId = `${testRun}-pre-cashier-bill`;
  await db.collection('bills').doc(checkoutId).set({
    cafeId, billId: checkoutId, status: 'completed',
    requestKey: JSON.stringify(['dineIn', [[productId, 1]]]),
    items: [{ productId, name: 'Water', quantity: 1, unitPrice: 20, lineTotal: 20 }],
    total: 20,
  });
  const retry = await checkout({
    db, callerUid: `${testRun}-staff`, cafeId, checkoutId,
    cart: { [productId]: 1 }, orderType: 'dineIn',
  });
  assert.deepEqual(retry, { billId: checkoutId, duplicate: true });
  assert.equal((await db.collection('stock_items').doc(productId).get()).data().quantity, 10);
  assert.equal((await movements(cafeId, productId)).length, 0);
  assert.equal((await db.collection('bills').doc(checkoutId).get()).data().cashierUid, undefined);
});

test('checkout rejects cart keys that collide after document ID normalization', async () => {
  await assert.rejects(
    checkout({
      db, callerUid: `${testRun}-staff`, cafeId: 'unused',
      checkoutId: `${testRun}-duplicate-cart-key`,
      cart: { product: 1, ' product ': 1 }, orderType: 'dineIn',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'invalid-argument',
  );
});

test('loyalty checkout earns, redeems, expires and records points idempotently', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 100 });
  const productId = await stock(cafeId, {
    name: 'Loyalty Latte', category: 'finished', unit: 'cup', quantity: 0,
    sellingPrice: 120,
  });
  await saveRecipe({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 1 }],
  });
  const phoneNumber = '+919876543210';
  const firstCheckout = {
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    checkoutId: `${testRun}-loyalty-first`,
    cart: { [productId]: 1 },
    orderType: 'dineIn',
    customerPhone: phoneNumber,
  };
  const firstResult = await checkout(firstCheckout);
  const firstBill = await db.collection('bills').doc(firstResult.billId).get();
  assert.equal(firstResult.pointsEarned, 4);
  assert.equal(firstBill.data().subtotal, 120);
  assert.equal(firstBill.data().total, 120);
  assert.equal(firstBill.data().loyalty.pointsBalanceAfter, 4);
  assert.equal(firstBill.data().customerPhone, phoneNumber);

  const retry = await checkout(firstCheckout);
  assert.equal(retry.duplicate, true);
  assert.equal((await lookupLoyaltyCustomer({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    phoneNumber,
  })).pointsBalance, 4);

  const secondResult = await checkout({
    ...firstCheckout,
    checkoutId: `${testRun}-loyalty-redeem`,
    redeemPoints: 4,
  });
  const secondBill = await db.collection('bills').doc(secondResult.billId).get();
  assert.equal(secondBill.data().discount, 4);
  assert.equal(secondBill.data().total, 116);
  assert.equal(secondBill.data().loyalty.pointsRedeemed, 4);
  assert.equal(secondBill.data().loyalty.pointsEarned, 4);
  assert.equal(secondBill.data().loyalty.pointsBalanceAfter, 4);
  const customerId = customerIdForPhone({ cafeId, phoneNumber });
  const customer = await db.collection('cafes').doc(cafeId)
    .collection('loyaltyCustomers').doc(customerId).get();
  assert.equal(customer.data().pointsBalance, 4);
  assert.equal(customer.data().pointsBuckets.length, 1);
  const ledger = await db.collection('cafes').doc(cafeId)
    .collection('loyaltyTransactions').get();
  assert.equal(ledger.size, 2);
});

test('loyalty lookup excludes expired point buckets and isolates each café', async () => {
  const cafeA = await setupCafe();
  const cafeB = await createCafe({
    db,
    uid: `${testRun}-other-owner`,
    name: 'Separate Loyalty Café',
  }).then((result) => result.cafeId);
  const phoneNumber = '+919876543210';
  const customerIdA = customerIdForPhone({ cafeId: cafeA, phoneNumber });
  const customerIdB = customerIdForPhone({ cafeId: cafeB, phoneNumber });
  assert.notEqual(customerIdA, customerIdB);
  await db.collection('cafes').doc(cafeA).collection('loyaltyCustomers')
    .doc(customerIdA).set({
      cafeId: cafeA,
      customerId: customerIdA,
      phoneNumber,
      pointsDebt: 0,
      pointsBuckets: [
        { points: 7, expiresAt: Timestamp.fromDate(new Date(Date.now() - 1000)) },
      ],
    });
  const result = await lookupLoyaltyCustomer({
    db,
    callerUid: `${testRun}-staff`,
    cafeId: cafeA,
    phoneNumber,
  });
  assert.equal(result.found, true);
  assert.equal(result.pointsBalance, 0);
  const otherCafeResult = await lookupLoyaltyCustomer({
    db,
    callerUid: `${testRun}-other-owner`,
    cafeId: cafeB,
    phoneNumber,
  });
  assert.equal(otherCafeResult.found, false);
});

test('partial refunds reverse loyalty proportionally and retries are idempotent', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 100 });
  const productId = await stock(cafeId, {
    name: 'Refund Latte', category: 'finished', unit: 'cup', quantity: 0,
    sellingPrice: 120,
  });
  await saveRecipe({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 1 }],
  });
  const sale = await checkout({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    checkoutId: `${testRun}-partial-refund-bill`,
    cart: { [productId]: 1 },
    orderType: 'dineIn',
    customerPhone: '+919876543210',
  });
  const adjustment = {
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    billId: sale.billId,
    adjustmentId: `${testRun}-refund-half`,
    requestedAmountMinor: 6000,
    reason: 'Order returned',
  };
  const firstRefund = await refundBill(adjustment);
  const duplicateRefund = await refundBill(adjustment);
  assert.equal(firstRefund.status, 'partially_refunded');
  assert.equal(firstRefund.refundedMinor, 6000);
  assert.equal(firstRefund.pointsReversed, 2);
  assert.equal(duplicateRefund.duplicate, true);
  await assert.rejects(
    refundBill({ ...adjustment, requestedAmountMinor: 5000 }),
    (error) => error instanceof CafeOperationError && error.code === 'already-exists',
  );
  assert.equal((await db.collection('bills').doc(sale.billId).get())
    .data().refundedMinor, 6000);

  const finalRefund = await refundBill({
    ...adjustment,
    adjustmentId: `${testRun}-refund-rest`,
    requestedAmountMinor: 6000,
  });
  assert.equal(finalRefund.status, 'refunded');
  assert.equal(finalRefund.pointsReversed, 2);
  assert.equal(finalRefund.pointsBalance, 0);
  assert.equal((await db.collection('stock_items').doc(ingredientId).get())
    .data().quantity, 99);
});

test('void restores valid redeemed points once and does not restock consumed items', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 10 });
  const productId = await stock(cafeId, {
    name: 'Void Latte', category: 'finished', unit: 'cup', quantity: 0,
    sellingPrice: 120,
  });
  await saveRecipe({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 1 }],
  });
  const phoneNumber = '+919876543210';
  const earnBill = await checkout({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    checkoutId: `${testRun}-void-earn-bill`,
    cart: { [productId]: 1 },
    orderType: 'dineIn',
    customerPhone: phoneNumber,
  });
  const redeemedBill = await checkout({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    checkoutId: `${testRun}-void-redeem-bill`,
    cart: { [productId]: 1 },
    orderType: 'dineIn',
    customerPhone: phoneNumber,
    redeemPoints: 4,
  });
  const voidRequest = {
    db,
    callerUid: `${testRun}-owner`,
    cafeId,
    billId: redeemedBill.billId,
    adjustmentId: `${testRun}-void-once`,
    reason: 'Duplicate order',
  };
  const firstVoid = await voidBill(voidRequest);
  const duplicateVoid = await voidBill(voidRequest);
  assert.equal(firstVoid.status, 'void');
  assert.equal(firstVoid.refundedMinor, 11600);
  assert.equal(firstVoid.pointsReversed, 4);
  assert.equal(firstVoid.pointsRestored, 4);
  assert.equal(firstVoid.pointsBalance, 4);
  assert.equal(duplicateVoid.duplicate, true);
  assert.equal((await lookupLoyaltyCustomer({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    phoneNumber,
  })).pointsBalance, 4);
  assert.equal((await db.collection('stock_items').doc(ingredientId).get())
    .data().quantity, 8);
  assert.equal((await db.collection('bills').doc(earnBill.billId).get())
    .data().status, 'completed');
});

test('checkout rounds displayed prices and totals to whole paise', async () => {
  const cafeId = await setupCafe();
  const beansId = await stock(cafeId, { quantity: 10 });
  const productId = await stock(cafeId, {
    name: 'Espresso', category: 'finished', unit: 'cup', quantity: 0,
    sellingPrice: 0.1,
  });
  const roundingProductId = await stock(cafeId, {
    name: 'Rounding test', category: 'finished', unit: 'cup', quantity: 0,
    sellingPrice: 0.105,
  });
  await saveRecipe({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    productId,
    ingredients: [{ stockItemId: beansId, quantity: 1 }],
  });
  await saveRecipe({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    productId: roundingProductId,
    ingredients: [{ stockItemId: beansId, quantity: 1 }],
  });

  const checkoutResult = await checkout({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    checkoutId: `${testRun}-checkout-paise`,
    cart: { [productId]: 3, [roundingProductId]: 3 },
    orderType: 'dineIn',
  });
  const bill = await db.collection('bills').doc(checkoutResult.billId).get();
  const espressoLine = bill.data().items.find((line) => line.productId === productId);
  const roundedLine = bill.data().items.find((line) => line.productId === roundingProductId);
  assert.equal(espressoLine.unitPrice, 0.1);
  assert.equal(espressoLine.lineTotal, 0.3);
  assert.equal(roundedLine.unitPrice, 0.11);
  assert.equal(roundedLine.lineTotal, 0.33);
  assert.equal(bill.data().total, 0.63);
  const summary = await getSalesSummary({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    startAt: new Date(Date.now() - 60_000).toISOString(),
    endAt: new Date(Date.now() + 60_000).toISOString(),
  });
  assert.equal(summary.grossRevenue, 0.63);
  assert.equal(summary.bestSellingProducts.length, 2);
  assert.ok(summary.bestSellingProducts.every((product) => product.revenue === 0.3 || product.revenue === 0.33));
});

test('checkout rejects a reused ID with a different order and rolls back insufficient stock', async () => {
  const cafeId = await setupCafe();
  const ingredientId = await stock(cafeId, { quantity: 5 });
  const productId = await stock(cafeId, {
    name: 'Cappuccino', category: 'finished', unit: 'cup', quantity: 0, sellingPrice: 5,
  });
  await saveRecipe({
    db,
    callerUid: `${testRun}-manager`,
    cafeId,
    productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 4 }],
  });
  const input = {
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    checkoutId: `${testRun}-checkout-failure`,
    cart: { [productId]: 2 },
    orderType: 'dineIn',
  };
  await assert.rejects(checkout(input), (error) =>
    error instanceof CafeOperationError && error.code === 'failed-precondition');
  assert.equal((await db.collection('stock_items').doc(ingredientId).get()).data().quantity, 5);
  assert.equal((await db.collection('bills').doc(input.checkoutId).get()).exists, false);
  assert.equal((await movements(cafeId, ingredientId)).length, 0);

  await db.collection('stock_items').doc(ingredientId).update({ quantity: 10 });
  const completed = { ...input, cart: { [productId]: 1 } };
  await checkout(completed);
  await assert.rejects(
    checkout({ ...completed, cart: { [productId]: 2 } }),
    (error) => error instanceof CafeOperationError && error.code === 'already-exists',
  );
});

test('inventory roles and recipe references cannot cross café boundaries', async () => {
  const cafeA = await setupCafe();
  const cafeB = await createCafe({
    db,
    uid: `${testRun}-other-owner`,
    name: 'Other Test Cafe',
  }).then((x) => x.cafeId);
  const foreignItemId = await stock(cafeB);
  const productId = await stock(cafeA, {
    name: 'Mocha', category: 'finished', unit: 'cup', quantity: 0, sellingPrice: 7,
  });

  await assert.rejects(
    createStockItem({
      db, callerUid: `${testRun}-staff`, cafeId: cafeA,
      item: { name: 'Forbidden', category: 'ingredient', unit: 'g', quantity: 0,
        minimumQuantity: 0, purchasePricePerUnit: 1, sellingPrice: 0 },
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  await assert.rejects(
    saveRecipe({
      db, callerUid: `${testRun}-manager`, cafeId: cafeA, productId,
      ingredients: [{ stockItemId: foreignItemId, quantity: 1 }],
    }),
    (error) => error instanceof CafeOperationError && error.code === 'failed-precondition',
  );
});

test('sales summary uses only completed bills within the active café and date range', async () => {
  const cafeId = await setupCafe();
  const otherCafeId = await createCafe({
    db,
    uid: `${testRun}-analytics-owner`,
    name: 'Analytics Other Cafe',
  }).then((result) => result.cafeId);
  const inside = Timestamp.fromDate(new Date('2026-10-16T12:00:00.000Z'));
  const outside = Timestamp.fromDate(new Date('2026-10-17T00:00:00.000Z'));
  await db.collection('bills').doc(`${testRun}-analytics-one`).set({
    cafeId,
    status: 'completed',
    total: 13,
    createdAt: inside,
    items: [
      { productId: 'latte', name: 'Latte', quantity: 2, lineTotal: 10 },
      { productId: 'mocha', name: 'Mocha', quantity: 1, lineTotal: 3 },
    ],
  });
  await db.collection('bills').doc(`${testRun}-analytics-void`).set({
    cafeId,
    status: 'void',
    total: 100,
    createdAt: inside,
    items: [{ productId: 'latte', name: 'Latte', quantity: 20, lineTotal: 100 }],
  });
  await db.collection('bills').doc(`${testRun}-analytics-partial-refund`).set({
    cafeId,
    status: 'partially_refunded',
    total: 10,
    refundedMinor: 300,
    createdAt: inside,
    items: [{ productId: 'latte', name: 'Latte', quantity: 1, lineTotal: 10 }],
  });
  await db.collection('bills').doc(`${testRun}-analytics-other-cafe`).set({
    cafeId: otherCafeId,
    status: 'completed',
    total: 500,
    createdAt: inside,
    items: [{ productId: 'latte', name: 'Latte', quantity: 100, lineTotal: 500 }],
  });
  await db.collection('bills').doc(`${testRun}-analytics-outside`).set({
    cafeId,
    status: 'completed',
    total: 700,
    createdAt: outside,
    items: [{ productId: 'latte', name: 'Latte', quantity: 100, lineTotal: 700 }],
  });

  const report = await getSalesSummary({
    db,
    callerUid: `${testRun}-staff`,
    cafeId,
    startAt: '2026-10-16T00:00:00.000Z',
    endAt: '2026-10-17T00:00:00.000Z',
  });
  assert.equal(report.completedBillCount, 2);
  assert.equal(report.grossRevenue, 20);
  assert.equal(report.itemsSold, 4);
  assert.deepEqual(report.bestSellingProducts, [
    { productId: 'latte', name: 'Latte', quantitySold: 3, revenue: 17 },
    { productId: 'mocha', name: 'Mocha', quantitySold: 1, revenue: 3 },
  ]);
  await assert.rejects(
    getSalesSummary({
      db,
      callerUid: `${testRun}-stranger`,
      cafeId,
      startAt: '2026-10-16T00:00:00.000Z',
      endAt: '2026-10-17T00:00:00.000Z',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
});

test('sales summary rejects invalid, empty, and over-31-day date ranges', async () => {
  const cafeId = await setupCafe();
  const callerUid = `${testRun}-staff`;
  const startAt = '2026-10-01T00:00:00.000Z';
  const invalidRanges = [
    { startAt: 'not-a-date', endAt: '2026-10-02T00:00:00.000Z' },
    { startAt, endAt: startAt },
    { startAt, endAt: '2026-11-01T00:00:00.001Z' },
  ];

  for (const range of invalidRanges) {
    await assert.rejects(
      getSalesSummary({ db, callerUid, cafeId, ...range }),
      (error) => error instanceof CafeOperationError &&
        error.code === 'invalid-argument',
    );
  }

  const boundaryReport = await getSalesSummary({
    db,
    callerUid,
    cafeId,
    startAt,
    endAt: '2026-11-01T00:00:00.000Z',
  });
  assert.equal(boundaryReport.completedBillCount, 0);
  assert.equal(boundaryReport.grossRevenue, 0);
  assert.equal(boundaryReport.itemsSold, 0);
});
