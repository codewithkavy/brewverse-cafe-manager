// One-time, approved local recovery. Password input is stdin only; never log it.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const adminRequire = createRequire(path.join(__dirname, '../functions/package.json'));
const clientRequire = createRequire(path.join(__dirname, '../security-tests/package.json'));
const { initializeApp: adminApp, deleteApp: disposeAdmin } = adminRequire('firebase-admin/app');
const { getAuth: adminAuth } = adminRequire('firebase-admin/auth');
const { getFirestore: adminFirestore } = adminRequire('firebase-admin/firestore');
const { initializeApp, deleteApp } = clientRequire('firebase/app');
const { getAuth, connectAuthEmulator, signInWithEmailAndPassword, signOut } = clientRequire('firebase/auth');
const { getFirestore, connectFirestoreEmulator, collection, query, where, getDocs, doc, getDoc } = clientRequire('firebase/firestore');
const { getStorage, connectStorageEmulator, ref, uploadBytes, getBytes } = clientRequire('firebase/storage');

const projectId = 'brewverse-security-tests';
const expectedUid = 'P3OvJpZGoBRKEpElF4keS512MvEG';
const expectedCafe = 'SnEadZW3hynRmz4Gc0lC';
let stage = 'input';

async function records() {
  const result = {};
  for (const name of ['cafes', 'cafe_members', 'stock_items', 'product_recipes', 'bills', 'stock_movements']) {
    const rows = [];
    let pageToken;
    do {
      const url = new URL(`http://127.0.0.1:8085/v1/projects/${projectId}/databases/(default)/documents/${name}`);
      url.searchParams.set('pageSize', '1000');
      if (pageToken) url.searchParams.set('pageToken', pageToken);
      const response = await fetch(url, { headers: { Authorization: 'Bearer owner' }, signal: AbortSignal.timeout(10000) });
      assert.equal(response.ok, true);
      const data = await response.json();
      rows.push(...(data.documents || []));
      pageToken = data.nextPageToken;
    } while (pageToken);
    result[name] = rows.sort((a, b) => a.name.localeCompare(b.name));
  }
  return result;
}
function content(snapshot) {
  return Object.fromEntries(Object.entries(snapshot).map(([name, rows]) => [name,
    Object.fromEntries(rows.map((d) => [d.name, d.fields]))]));
}

(async () => {
  assert.equal(process.env.GCLOUD_PROJECT, projectId);
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9099');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8085');
  assert.equal(process.env.FIREBASE_STORAGE_EMULATOR_HOST, '127.0.0.1:9199');
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  const request = JSON.parse(input);
  input = '';
  assert.equal(request.uid, expectedUid);
  assert.equal(request.cafeId, expectedCafe);
  assert.equal(request.email, 'kannumehta3@gmail.com');
  const backup = path.resolve(request.backupPath);
  assert.ok(fs.existsSync(path.join(backup, 'firebase-export-metadata.json')));
  const before = JSON.parse(fs.readFileSync(path.join(backup, 'business-records-before.json'), 'utf8'));
  assert.deepEqual(content(await records()), content(before), 'Local data changed since backup; stop for review.');
  const admin = adminApp({ projectId }, 'approved-local-recovery');
  let client;
  try {
    stage = 'verify-original-identity';
    const db = adminFirestore(admin);
    const cafe = (await db.collection('cafes').doc(expectedCafe).get()).data();
    const membership = (await db.collection('cafe_members').doc(`${expectedUid}_${expectedCafe}`).get()).data();
    assert.equal(cafe.ownerUid, expectedUid);
    assert.equal(cafe.name.toLowerCase(), 'brewverse test cafe');
    assert.equal(membership.uid, expectedUid);
    assert.equal(membership.cafeId, expectedCafe);
    assert.equal(membership.role, 'owner');
    assert.equal(membership.status, 'active');
    const auth = adminAuth(admin);
    let identityMissing = false;
    // Resume the approved recovery after an emulator crash using the same
    // DPAPI-protected password. Never replace an existing identity.
    if (request.verifyOnly) {
      try {
        const existing = await auth.getUser(expectedUid);
        assert.equal(existing.email, request.email);
      } catch (error) {
        assert.equal(error.code, 'auth/user-not-found');
        identityMissing = true;
      }
    }
    if (!request.verifyOnly || identityMissing) {
      // Never overwrite an existing user or silently attach an email to another UID.
      for (const lookup of [() => auth.getUser(expectedUid), () => auth.getUserByEmail(request.email)]) {
        let exists = false;
        try { await lookup(); exists = true; } catch (e) { assert.equal(e.code, 'auth/user-not-found'); }
        assert.equal(exists, false, 'A matching Auth identity already exists; refusing overwrite.');
      }
      if (request.dryRun) {
        console.log(JSON.stringify({ verified: true, uid: expectedUid, cafeId: expectedCafe, mutation: false }));
        return;
      }
      assert.ok(typeof request.password === 'string' && request.password.length >= 24);
      stage = 'restore-same-auth-uid';
      const recovered = await auth.createUser({ uid: expectedUid, email: request.email, password: request.password });
      assert.equal(recovered.uid, expectedUid);
    }
    const users = await auth.listUsers();
    assert.equal(users.users.filter((u) => u.uid === expectedUid).length, 1);
    assert.equal(users.users.filter((u) => u.email === request.email).length, 1);

    stage = 'verify-password-login-and-existing-cafe';
    client = initializeApp({ projectId, apiKey: 'fake-api-key', appId: 'local-recovery-verification' }, 'local-recovery-verification');
    const clientAuth = getAuth(client);
    const clientDb = getFirestore(client);
    const storage = getStorage(client, 'gs://brewverse-593dc.firebasestorage.app');
    connectAuthEmulator(clientAuth, 'http://127.0.0.1:9099', { disableWarnings: true });
    connectFirestoreEmulator(clientDb, '127.0.0.1', 8085);
    connectStorageEmulator(storage, '127.0.0.1', 9199);
    storage.maxUploadRetryTime = 5000;
    storage.maxOperationRetryTime = 5000;
    const credential = await signInWithEmailAndPassword(clientAuth, request.email, request.password);
    request.password = '';
    assert.equal(credential.user.uid, expectedUid);
    assert.equal((await getDoc(doc(clientDb, 'cafes', expectedCafe))).data().ownerUid, expectedUid);
    assert.equal((await getDoc(doc(clientDb, 'cafe_members', `${expectedUid}_${expectedCafe}`))).data().role, 'owner');
    const counts = {};
    let bunId;
    for (const name of ['stock_items', 'product_recipes', 'bills']) {
      const data = await getDocs(query(collection(clientDb, name), where('cafeId', '==', expectedCafe)));
      counts[name] = data.size;
      const expected = before[name].filter((d) => d.fields.cafeId?.stringValue === expectedCafe).length;
      assert.equal(data.size, expected);
      if (name === 'stock_items') {
        const buns = data.docs.filter((d) => d.data().name.toLowerCase() === 'burger bun');
        assert.equal(buns.length, 1);
        assert.equal(buns[0].data().quantity, 94);
        bunId = buns[0].id;
      }
    }
    stage = 'verify-functions-read-access';
    const token = await credential.user.getIdToken();
    const response = await fetch(`http://127.0.0.1:5001/${projectId}/us-central1/listCafeMemberships`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify({ data: { cafeId: expectedCafe } }), signal: AbortSignal.timeout(60000),
    });
    assert.equal(response.ok, true);
    const team = (await response.json()).result.memberships;
    assert.ok(team.some((member) => member.uid === expectedUid && member.role === 'owner'));
    stage = 'verify-local-storage';
    const image = new Uint8Array(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6cX8AAAAASUVORK5CYII=', 'base64'));
    const probePath = `cafes/${expectedCafe}/products/${bunId}_${crypto.randomBytes(16).toString('hex')}.png`;
    const probe = ref(storage, probePath);
    await uploadBytes(probe, image, { contentType: 'image/png' });
    assert.deepEqual(new Uint8Array(await getBytes(probe)), image);
    stage = 'verify-no-business-data-changes';
    assert.deepEqual(content(await records()), content(before));
    const result = { recovered: true, uid: expectedUid, cafeId: expectedCafe, loginVerified: true,
      counts, burgerBunQuantity: 94, functionsVerified: true, storageVerified: true,
      businessDataUnchanged: true, storageProbeRetained: probePath };
    fs.writeFileSync(path.join(backup, 'recovery-verification.json'), JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result));
    await signOut(clientAuth);
  } finally {
    if (client) await deleteApp(client);
    await disposeAdmin(admin);
  }
})().catch((error) => {
  // Do not serialize requests, SDK responses, tokens, or passwords on failure.
  console.error(JSON.stringify({ ok: false, stage, code: error.code || 'verification-failed' }));
  process.exitCode = 1;
});
