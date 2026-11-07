const assert = require('node:assert/strict');
const { test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signOut } = require('firebase/auth');
const { getFirestore, connectFirestoreEmulator, collection, doc, getDoc, getDocs, query, where } = require('firebase/firestore');

test('first burger recipe: authenticated load, save, reopen and transactional ingredient deduction', async () => {
  assert.equal(process.env.GCLOUD_PROJECT, 'brewverse-security-tests');
  const host = (name) => {
    const value = process.env[name] || '';
    assert.match(value, /^127\.0\.0\.1:\d+$/, `Local emulator required: ${name}`);
    return value.split(':');
  };
  const [authHost, authPort] = host('FIREBASE_AUTH_EMULATOR_HOST');
  const [firestoreHost, firestorePort] = host('FIRESTORE_EMULATOR_HOST');
  const functionsUrl = new URL(process.env.BREWVERSE_FUNCTIONS_TEST_URL);
  assert.equal(functionsUrl.hostname, '127.0.0.1');
  assert.equal(functionsUrl.protocol, 'http:');
  const runId = `recipe-${Date.now()}`;
  const app = initializeApp({ projectId: 'brewverse-security-tests', apiKey: 'fake-api-key', appId: runId }, runId);
  const auth = getAuth(app);
  const db = getFirestore(app);
  connectAuthEmulator(auth, `http://${authHost}:${authPort}`, { disableWarnings: true });
  connectFirestoreEmulator(db, firestoreHost, Number(firestorePort));
  try {
    const { user } = await createUserWithEmailAndPassword(auth, `${runId}@example.test`, 'local-test-password');
    const invoke = async (name, data) => {
      const response = await fetch(`${functionsUrl.origin}/brewverse-security-tests/us-central1/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await user.getIdToken()}` },
        body: JSON.stringify({ data }),
      });
      const result = await response.json();
      assert.equal(response.ok, true, JSON.stringify(result));
      return result.result;
    };
    const { cafeId } = await invoke('createCafe', { name: runId });
    const memberships = await getDocs(query(collection(db, 'cafe_members'), where('uid', '==', user.uid)));
    assert.ok(memberships.docs.some((member) => member.data().cafeId === cafeId && member.data().role === 'owner' && member.data().status === 'active'));
    const stock = async (name, category, quantity, sellingPrice) => (await invoke('createStockItem', { cafeId,
      item: { name, category, quantity, sellingPrice, unit: 'piece', minimumQuantity: 0, purchasePricePerUnit: 0, stockMode: 'recipe' },
    })).stockItemId;
    const bunId = await stock('burger bun', 'ingredient', 100, 0);
    const burgerId = await stock('veg burger', 'finished', 0, 80);
    const recipe = () => getDocs(query(collection(db, 'product_recipes'), where('cafeId', '==', cafeId), where('productId', '==', burgerId)));
    // Reproduce the original failing get with a real authenticated client.
    await assert.rejects(getDoc(doc(db, 'product_recipes', burgerId)), (error) => error.code === 'permission-denied');
    assert.equal((await recipe()).empty, true);
    const ingredients = await getDocs(query(collection(db, 'stock_items'), where('cafeId', '==', cafeId), where('category', '==', 'ingredient')));
    assert.equal(ingredients.docs[0].data().name, 'burger bun');
    await invoke('saveRecipe', { cafeId, productId: burgerId, ingredients: [{ stockItemId: bunId, quantity: 2 }], packaging: [] });
    const saved = (await recipe()).docs[0].data();
    assert.equal(saved.ingredients[0].stockItemId, bunId);
    assert.equal(saved.ingredients[0].quantity, 2);
    const order = { cafeId, checkoutId: `${runId}-sale`, cart: { [burgerId]: 3 }, orderType: 'dineIn' };
    const { billId } = await invoke('checkout', order);
    assert.equal((await getDoc(doc(db, 'stock_items', bunId))).data().quantity, 94);
    assert.equal((await getDoc(doc(db, 'bills', billId))).data().total, 240);
    assert.equal((await invoke('checkout', order)).billId, billId);
    assert.equal((await getDoc(doc(db, 'stock_items', bunId))).data().quantity, 94);
    // Insufficient stock must fail without changing the ingredient or saving a bill.
    const shortageId = `${runId}-shortage`;
    const shortage = await fetch(`${functionsUrl.origin}/brewverse-security-tests/us-central1/checkout`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await user.getIdToken()}` },
      body: JSON.stringify({ data: { ...order, checkoutId: shortageId, cart: { [burgerId]: 100 } } }),
    });
    assert.equal(shortage.ok, false);
    assert.equal((await shortage.json()).error.status, 'FAILED_PRECONDITION');
    assert.equal((await getDoc(doc(db, 'stock_items', bunId))).data().quantity, 94);
    const missingBill = await getDocs(query(collection(db, 'bills'), where('cafeId', '==', cafeId), where('billId', '==', shortageId)));
    assert.equal(missingBill.empty, true);
  } finally {
    await signOut(auth);
    await deleteApp(app); // Release the SDK only; synthetic records are retained.
  }
});
