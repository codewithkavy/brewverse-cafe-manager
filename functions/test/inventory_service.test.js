const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

const { CafeOperationError, createCafe, grantCafeMembership } = require('../src/membership_service');
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
