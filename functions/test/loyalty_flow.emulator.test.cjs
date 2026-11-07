const assert = require('node:assert/strict');
const { test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// Dedicated disposable ports: never use the phone's data or security fixtures.
test('loyalty enrollment, earning and redemption through real authenticated callables', async (t) => {
  assert.equal(process.env.GCLOUD_PROJECT, 'brewverse-security-tests');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:12185');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:12198');
  assert.equal(process.env.BREWVERSE_FUNCTIONS_TEST_URL, 'http://127.0.0.1:12101');
  const projectId = 'brewverse-security-tests';
  const run = `loyalty-${Date.now()}`;
  const app = initializeApp({ projectId }, run);
  const db = getFirestore(app);
  try {
    const authResponse = await fetch('http://127.0.0.1:12198/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: `${run}@example.test`, password: 'local-only-password', returnSecureToken: true }),
    });
    assert.equal(authResponse.ok, true);
    const { idToken } = await authResponse.json();
    async function call(name, data, token = idToken) {
      const response = await fetch(`http://127.0.0.1:12101/${projectId}/us-central1/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ data }), signal: AbortSignal.timeout(60000),
      });
      return response.json();
    }
    async function success(name, data) {
      const result = await call(name, data);
      assert.equal(result.error, undefined, JSON.stringify(result.error));
      return result.result;
    }
    const { cafeId } = await success('createCafe', { name: run });
    const customers = db.collection('cafes').doc(cafeId).collection('loyaltyCustomers');
    const ledger = db.collection('cafes').doc(cafeId).collection('loyaltyTransactions');
    const { stockItemId } = await success('createStockItem', { cafeId, item: {
      name: 'Isolated loyalty product', category: 'finished', stockMode: 'direct',
      unit: 'piece', quantity: 100, minimumQuantity: 0, purchasePricePerUnit: 0, sellingPrice: 80,
    } });
    const phoneNumber = '+919876543210';
    const lookup = () => success('lookupLoyaltyCustomer', { cafeId, phoneNumber });
    const order = (id, quantity = 1, redeemPoints = 0) => ({
      cafeId, checkoutId: `${run}-${id}`, cart: { [stockItemId]: quantity },
      orderType: 'dineIn', customerPhone: phoneNumber, redeemPoints,
    });
    await t.test('lookup and rejected checkout do not register a customer or write a ledger', async () => {
      assert.equal((await lookup()).customer.found, false);
      assert.equal((await customers.get()).size, 0);
      assert.equal((await call('checkout', order('insufficient', 101))).error.status, 'FAILED_PRECONDITION');
      assert.equal((await customers.get()).size, 0);
      assert.equal((await ledger.get()).size, 0);
      assert.equal((await db.collection('stock_items').doc(stockItemId).get()).data().quantity, 100);
    });
    await t.test('successful below-threshold checkout registers once with zero earned points', async () => {
      const result = await success('checkout', order('first'));
      assert.equal(result.pointsEarned, 0);
      assert.equal((await lookup()).customer.found, true);
      assert.equal((await lookup()).customer.pointsBalance, 0);
      assert.equal((await customers.get()).size, 1);
      assert.equal((await ledger.get()).size, 1);
    });
    await t.test('earning uses full spend units and retries do not award or deduct twice', async () => {
      assert.equal((await success('checkout', order('earn', 5))).pointsEarned, 16);
      assert.equal((await success('checkout', order('earn', 5))).duplicate, true);
      assert.equal((await lookup()).customer.pointsBalance, 16);
      assert.equal((await ledger.get()).size, 2);
      assert.equal((await db.collection('stock_items').doc(stockItemId).get()).data().quantity, 94);
    });
    await t.test('redemption discounts the bill and earns only on net paid amount', async () => {
      await success('checkout', order('redeem', 1, 4));
      const bill = (await db.collection('bills').doc(`${run}-redeem`).get()).data();
      assert.equal(bill.subtotal, 80);
      assert.equal(bill.discount, 4);
      assert.equal(bill.total, 76);
      assert.equal(bill.loyalty.pointsEarned, 0);
      assert.equal((await lookup()).customer.pointsBalance, 12);
    });
    await t.test('invalid redemption changes neither stock, customer nor ledger', async () => {
      const before = (await customers.get()).docs[0].data();
      assert.equal((await call('checkout', order('too-many-points', 1, 13))).error.status, 'INVALID_ARGUMENT');
      assert.deepEqual((await customers.get()).docs[0].data(), before);
      assert.equal((await ledger.get()).size, 3);
      assert.equal((await db.collection('stock_items').doc(stockItemId).get()).data().quantity, 93);
    });
    await t.test('concurrent redemptions cannot spend the same balance twice', async () => {
      const results = await Promise.all(['race-a', 'race-b'].map((id) => call('checkout', order(id, 1, 12))));
      assert.equal(results.filter((result) => result.result).length, 1);
      assert.equal(results.filter((result) => result.error?.status === 'INVALID_ARGUMENT').length, 1);
      assert.equal((await lookup()).customer.pointsBalance, 0);
      assert.equal((await ledger.get()).size, 4);
      assert.equal((await db.collection('stock_items').doc(stockItemId).get()).data().quantity, 92);
    });
    await t.test('lookup requires authentication and international phone format', async () => {
      assert.equal((await call('lookupLoyaltyCustomer', { cafeId, phoneNumber }, null)).error.status, 'UNAUTHENTICATED');
      assert.equal((await call('lookupLoyaltyCustomer', { cafeId, phoneNumber: '9876543210' })).error.status, 'INVALID_ARGUMENT');
    });
  } finally {
    await deleteApp(app);
  }
});
