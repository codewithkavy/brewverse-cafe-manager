const assert = require('node:assert/strict');
const { test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase/app');
const { getAuth, connectAuthEmulator, createUserWithEmailAndPassword, signOut } = require('firebase/auth');
const { getFirestore, connectFirestoreEmulator, doc, getDoc, runTransaction, serverTimestamp } = require('firebase/firestore');
const { getStorage, connectStorageEmulator, ref, uploadBytesResumable, getBytes, getDownloadURL, getMetadata } = require('firebase/storage');

test('local product photo uploads, downloads, saves its pointer and enforces manager permissions', async () => {
  assert.equal(process.env.GCLOUD_PROJECT, 'brewverse-security-tests');
  const endpoint = (name) => {
    assert.match(process.env[name] || '', /^127\.0\.0\.1:\d+$/, `Missing local endpoint: ${name}`);
    return process.env[name].split(':');
  };
  const [authHost, authPort] = endpoint('FIREBASE_AUTH_EMULATOR_HOST');
  const [dbHost, dbPort] = endpoint('FIRESTORE_EMULATOR_HOST');
  const [storageHost, storagePort] = endpoint('FIREBASE_STORAGE_EMULATOR_HOST');
  const functions = new URL(process.env.BREWVERSE_FUNCTIONS_TEST_URL);
  assert.equal(functions.hostname, '127.0.0.1');
  assert.equal(functions.protocol, 'http:');
  const runId = `photo-${Date.now()}`;
  const clients = [];
  const client = async (suffix) => {
    const app = initializeApp({ projectId: 'brewverse-security-tests', apiKey: 'fake-api-key', appId: runId }, `${runId}-${suffix}`);
    const auth = getAuth(app);
    const db = getFirestore(app);
    // Match the Android registration's bucket name while keeping all traffic
    // on the isolated Storage emulator. No production bucket is contacted.
    const storage = getStorage(app, 'gs://brewverse-593dc.firebasestorage.app');
    connectAuthEmulator(auth, `http://${authHost}:${authPort}`, { disableWarnings: true });
    connectFirestoreEmulator(db, dbHost, Number(dbPort));
    connectStorageEmulator(storage, storageHost, Number(storagePort));
    storage.maxUploadRetryTime = 3000;
    storage.maxOperationRetryTime = 3000;
    const result = { app, auth, db, storage };
    clients.push(result);
    result.email = `${runId}-${suffix}@example.test`;
    result.user = (await createUserWithEmailAndPassword(auth, result.email, 'local-test-password')).user;
    return result;
  };
  try {
    const owner = await client('owner');
    const invoke = async (name, data) => {
      const response = await fetch(`${functions.origin}/brewverse-security-tests/us-central1/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await owner.user.getIdToken()}` },
        body: JSON.stringify({ data }),
      });
      const result = await response.json();
      assert.equal(response.ok, true, JSON.stringify(result));
      return result.result;
    };
    const { cafeId } = await invoke('createCafe', { name: runId });
    const { stockItemId } = await invoke('createStockItem', { cafeId, item: {
      name: 'Photo regression product', category: 'finished', stockMode: 'direct',
      unit: 'piece', quantity: 5, minimumQuantity: 0, purchasePricePerUnit: 5, sellingPrice: 10,
    } });
    const image = new Uint8Array(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6cX8AAAAASUVORK5CYII=', 'base64'));
    const path = `cafes/${cafeId}/products/${stockItemId}_0123456789abcdef0123456789abcdef.png`;
    const object = ref(owner.storage, path);
    await uploadBytesResumable(object, image, { contentType: 'image/png' });
    const url = await getDownloadURL(object);
    assert.equal(new URL(url).hostname, storageHost);
    assert.equal(new URL(url).port, storagePort);
    assert.equal((await getMetadata(object)).contentType, 'image/png');
    assert.deepEqual(new Uint8Array(await getBytes(object)), image);
    const item = doc(owner.db, 'stock_items', stockItemId);
    await runTransaction(owner.db, async (tx) => {
      const previous = await tx.get(item);
      assert.equal(previous.data().photoUrl, '');
      tx.update(item, { photoUrl: url, updatedAt: serverTimestamp() });
    });
    assert.equal((await getDoc(item)).data().photoUrl, url);
    assert.equal((await getDoc(item)).data().quantity, 5);
    const staff = await client('staff');
    await invoke('grantCafeMembership', { cafeId, email: staff.email, role: 'staff' });
    await assert.rejects(uploadBytesResumable(ref(staff.storage, `${path}.denied.png`), image, { contentType: 'image/png' }), (error) => error.code === 'storage/unauthorized');
    assert.deepEqual(new Uint8Array(await getBytes(ref(staff.storage, path))), image);
    await signOut(staff.auth);
    await assert.rejects(uploadBytesResumable(ref(staff.storage, `${path}.anonymous.png`), image, { contentType: 'image/png' }), (error) => error.code === 'storage/unauthorized');
    // Denied uploads must leave the successful owner image and link intact.
    assert.equal((await getDoc(item)).data().photoUrl, url);
    assert.deepEqual(new Uint8Array(await getBytes(object)), image);
  } finally {
    for (const client of clients) {
      await signOut(client.auth);
      await deleteApp(client.app); // SDK disposal only; no records/images deleted.
    }
  }
});
