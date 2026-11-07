const assert = require('node:assert/strict');
const { test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// These assertions run before an Admin client or any network request is created.
// This suite creates unique synthetic cafes and never clears shared collections.
test('Step 53 loyalty atomicity, isolation and adjustment policies', async (t) => {
  const projectId = 'brewverse-security-tests';
  assert.equal(process.env.GCLOUD_PROJECT, projectId);
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:13185');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:13198');
  assert.equal(process.env.FIREBASE_STORAGE_EMULATOR_HOST, '127.0.0.1:13199');
  assert.equal(process.env.BREWVERSE_FUNCTIONS_TEST_URL, 'http://127.0.0.1:13101');
  const run = `step53-loyalty-${Date.now()}`;
  const app = initializeApp({ projectId }, run);
  const db = getFirestore(app);
  const phoneNumber = '+919876543210';
  let sequence = 0;
  async function user(label) {
    const response = await fetch('http://127.0.0.1:13198/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: `${run}-${label}@example.test`, password: 'local-only-password', returnSecureToken: true }),
      signal: AbortSignal.timeout(60000),
    });
    const result = await response.json();
    assert.equal(response.ok, true, JSON.stringify(result));
    return result;
  }
  const owner = await user('owner');
  async function call(name, data, token = owner.idToken) {
    const response = await fetch(`http://127.0.0.1:13101/${projectId}/us-central1/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify({ data }), signal: AbortSignal.timeout(60000),
    });
    return response.json();
  }
  async function success(name, data, token) {
    const result = await call(name, data, token);
    assert.equal(result.error, undefined, JSON.stringify(result));
    return result.result;
  }
  async function fixture(label) {
    const { cafeId } = await success('createCafe', { name: `${run}-${label}` });
    const { stockItemId } = await success('createStockItem', { cafeId, item: {
      name: 'Disposable loyalty product', category: 'finished', stockMode: 'direct',
      unit: 'piece', quantity: 100, minimumQuantity: 0, purchasePricePerUnit: 0, sellingPrice: 200,
    } });
    const cafe = db.collection('cafes').doc(cafeId);
    const order = (label, quantity = 1, redeemPoints = 0, phone = phoneNumber) => ({
      cafeId, checkoutId: `${run}-${label}-${sequence++}`, cart: { [stockItemId]: quantity },
      orderType: 'dineIn', customerPhone: phone, redeemPoints,
    });
    async function snapshot() {
      const result = { cafe: (await cafe.get()).data() };
      for (const collection of ['bills', 'stock_items', 'stock_movements']) {
        const docs = await db.collection(collection).where('cafeId', '==', cafeId).get();
        result[collection] = Object.fromEntries(docs.docs.map(doc => [doc.id, doc.data()]));
      }
      for (const collection of ['loyaltyCustomers', 'loyaltyTransactions', 'billAdjustments']) {
        const docs = await cafe.collection(collection).get();
        result[collection] = Object.fromEntries(docs.docs.map(doc => [doc.id, doc.data()]));
      }
      return result;
    }
    const lookup = (phone = phoneNumber) => success('lookupLoyaltyCustomer', { cafeId, phoneNumber: phone });
    return { cafeId, stockItemId, cafe, order, snapshot, lookup };
  }
  try {
    await t.test('earn thresholds and bonus use paid amount; concurrent same-key checkout earns once', async () => {
      const f = await fixture('earning');
      const request = f.order('earn', 5); // Rs1000: 40 base points + highest bonus 10.
      const results = await Promise.all([0, 1, 2].map(() => success('checkout', request)));
      assert.equal(results.filter(result => result.duplicate === false).length, 1);
      assert.equal(results.filter(result => result.duplicate === true).length, 2);
      assert.equal(results.find(result => result.duplicate === false).pointsEarned, 50);
      assert.equal((await f.lookup()).customer.pointsBalance, 50);
      const after = await f.snapshot();
      assert.equal(Object.keys(after.bills).length, 1);
      assert.equal(Object.keys(after.loyaltyCustomers).length, 1);
      assert.equal(Object.keys(after.loyaltyTransactions).length, 1);
      assert.equal(after.stock_items[f.stockItemId].quantity, 95);
      assert.equal((await success('checkout', request)).duplicate, true);
      assert.deepEqual(await f.snapshot(), after);
      const redemption = f.order('redeem', 1, 20);
      const result = await success('checkout', redemption);
      assert.equal(result.pointsEarned, 4); // Net paid Rs180, not gross Rs200.
      const bill = (await db.collection('bills').doc(redemption.checkoutId).get()).data();
      assert.equal(bill.subtotal, 200);
      assert.equal(bill.discount, 20);
      assert.equal(bill.total, 180);
      assert.equal(bill.loyalty.pointsRedeemed, 20);
      assert.equal((await f.lookup()).customer.pointsBalance, 34);
      const redeemed = await f.snapshot();
      assert.equal((await success('checkout', redemption)).duplicate, true);
      assert.deepEqual(await f.snapshot(), redeemed);
    });
    await t.test('insufficient points and stock leave all financial, stock and loyalty records unchanged', async () => {
      const f = await fixture('failure');
      const before = await f.snapshot();
      assert.equal((await call('checkout', f.order('points-fail', 1, 1))).error?.status, 'INVALID_ARGUMENT');
      assert.deepEqual(await f.snapshot(), before);
      assert.equal((await call('checkout', f.order('stock-fail', 101))).error?.status, 'FAILED_PRECONDITION');
      assert.deepEqual(await f.snapshot(), before);
      assert.equal((await f.lookup()).customer.found, false);
    });
    await t.test('concurrent different checkouts cannot redeem the same points twice', async () => {
      const f = await fixture('redemption-race');
      await success('checkout', f.order('seed-points', 5));
      const before = await f.snapshot();
      const results = await Promise.all([0, 1].map(index => call('checkout', f.order(`race-${index}`, 1, 50))));
      assert.equal(results.filter(result => result.result).length, 1);
      assert.equal(results.filter(result => result.error?.status === 'INVALID_ARGUMENT').length, 1);
      const after = await f.snapshot();
      assert.equal(after.stock_items[f.stockItemId].quantity, before.stock_items[f.stockItemId].quantity - 1);
      assert.equal(Object.keys(after.bills).length, Object.keys(before.bills).length + 1);
      assert.equal(Object.keys(after.loyaltyTransactions).length, Object.keys(before.loyaltyTransactions).length + 1);
      assert.equal((await f.lookup()).customer.pointsBalance, 4); // 50 redeemed; Rs150 earns 4.
    });
    await t.test('customer balances and identity are isolated by phone and cafe; foreign members cannot read or redeem', async () => {
      const a = await fixture('isolation-a');
      const b = await fixture('isolation-b');
      await success('checkout', a.order('seed-points', 5));
      const beforeA = await a.snapshot(), beforeB = await b.snapshot();
      assert.equal((await a.lookup('+919876543211')).customer.found, false);
      const lookupA = await a.lookup(), lookupB = await b.lookup();
      assert.notEqual(lookupA.customer.customerId, lookupB.customer.customerId);
      assert.equal(lookupA.customer.pointsBalance, 50);
      assert.equal(lookupB.customer.found, false);
      assert.equal((await call('checkout', a.order('foreign-phone', 1, 1, '+919876543211'))).error?.status, 'INVALID_ARGUMENT');
      assert.equal((await call('checkout', b.order('foreign-cafe', 1, 1))).error?.status, 'INVALID_ARGUMENT');
      const outsider = await user('outsider');
      for (const token of [null, outsider.idToken]) {
        const expected = token === null ? 'UNAUTHENTICATED' : 'PERMISSION_DENIED';
        assert.equal((await call('lookupLoyaltyCustomer', { cafeId: a.cafeId, phoneNumber }, token)).error?.status, expected);
        assert.equal((await call('checkout', a.order('unauthorized', 1, 1), token)).error?.status, expected);
      }
      assert.deepEqual(await a.snapshot(), beforeA);
      assert.deepEqual(await b.snapshot(), beforeB);
    });
    for (const mode of ['refund', 'void']) {
      await t.test(`${mode} reverses earned points and restores redeemed points exactly once without restocking`, async () => {
        const f = await fixture(`${mode}-reversal`);
        await success('checkout', f.order('seed-points', 5));
        const order = f.order('redeemed-sale', 1, 20);
        await success('checkout', order);
        assert.equal((await f.lookup()).customer.pointsBalance, 34);
        const before = await f.snapshot();
        const request = { cafeId: f.cafeId, billId: order.checkoutId,
          adjustmentId: `${run}-${mode}-reversal`, amountMinor: 18000, reason: 'Disposable loyalty reversal' };
        const results = await Promise.all([0, 1].map(() => success(`${mode}Bill`, request)));
        assert.equal(results.filter(result => result.duplicate === false).length, 1);
        assert.equal(results.filter(result => result.duplicate === true).length, 1);
        const fresh = results.find(result => result.duplicate === false);
        assert.equal(fresh.pointsReversed, 4);
        assert.equal(fresh.pointsRestored, 20);
        assert.equal(fresh.status, mode === 'void' ? 'void' : 'refunded');
        assert.equal((await f.lookup()).customer.pointsBalance, 50);
        const after = await f.snapshot();
        assert.deepEqual(after.stock_items, before.stock_items);
        assert.deepEqual(after.stock_movements, before.stock_movements);
        assert.equal(Object.keys(after.billAdjustments).length, 1);
        assert.equal(Object.values(after.billAdjustments)[0].stockRestocked, false);
        assert.equal(Object.keys(after.loyaltyTransactions).length, Object.keys(before.loyaltyTransactions).length + 1);
        const reversal = after.loyaltyTransactions[`${request.adjustmentId}_refund`];
        assert.equal(reversal.billId, order.checkoutId);
        assert.equal(reversal.adjustmentId, request.adjustmentId);
        assert.equal(reversal.pointsReversed, 4);
        assert.equal(reversal.pointsRestored, 20);
        assert.equal((await success(`${mode}Bill`, request)).duplicate, true);
        assert.deepEqual(await f.snapshot(), after);
      });
    }
    await t.test('partial refunds reverse and restore only the incremental proportional points', async () => {
      const f = await fixture('partial-refund');
      await success('checkout', f.order('seed-points', 5));
      const order = f.order('redeemed-sale', 1, 20);
      await success('checkout', order);
      for (let index = 0; index < 2; index++) {
        const result = await success('refundBill', { cafeId: f.cafeId, billId: order.checkoutId,
          adjustmentId: `${run}-partial-${index}`, amountMinor: 9000, reason: 'Disposable half refund' });
        assert.equal(result.pointsReversed, 2);
        assert.equal(result.pointsRestored, 10);
        assert.equal(result.status, index === 0 ? 'partially_refunded' : 'refunded');
        assert.equal((await f.lookup()).customer.pointsBalance, index === 0 ? 42 : 50);
      }
      const after = await f.snapshot();
      const bill = after.bills[order.checkoutId];
      assert.equal(bill.refundPointsReversed, 4);
      assert.equal(bill.refundPointsRestored, 20);
      assert.equal(bill.refundedMinor, 18000);
      assert.equal(Object.keys(after.billAdjustments).length, 2);
      assert.equal(after.stock_items[f.stockItemId].quantity, 94);
    });
    await t.test('refund policy uses checkout snapshot even when disposable cafe settings later change', async () => {
      const f = await fixture('policy-snapshot');
      await success('checkout', f.order('seed-points', 5));
      const order = f.order('redeemed-sale', 1, 20);
      await success('checkout', order);
      const { settings } = await success('getLoyaltySettings', { cafeId: f.cafeId });
      await success('saveLoyaltySettings', { cafeId: f.cafeId,
        settings: { ...settings, reverseEarnedOnRefund: false, restoreRedeemedOnRefund: false } });
      const result = await success('refundBill', { cafeId: f.cafeId, billId: order.checkoutId,
        adjustmentId: `${run}-snapshot-refund`, amountMinor: 18000, reason: 'Original policy snapshot' });
      assert.equal(result.pointsReversed, 4);
      assert.equal(result.pointsRestored, 20);
      assert.equal((await f.lookup()).customer.pointsBalance, 50);
    });
  } finally {
    await deleteApp(app);
  }
});
