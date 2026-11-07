const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const {
  CafeOperationError,
  createCafe,
  grantCafeMembership,
  listCafeMemberships,
  revokeCafeMembership,
} = require('../src/membership_service');

const projectId = 'brewverse-security-tests';
let app;
let db;

before(() => {
  if (process.env.FIRESTORE_EMULATOR_HOST == null) {
    throw new Error('Refusing to run backend tests without Firestore Emulator.');
  }
  if (process.env.GCLOUD_PROJECT !== projectId) {
    throw new Error(`Refusing to run against project ${process.env.GCLOUD_PROJECT}.`);
  }
  app = initializeApp({ projectId }, `membership-tests-${Date.now()}`);
  db = getFirestore(app);
});

after(async () => {
  if (app) await deleteApp(app);
});

async function makeCafe(ownerUid, name = 'Test Cafe') {
  return createCafe({ db, uid: ownerUid, name });
}

async function membership(uid, cafeId) {
  const snapshot = await db.collection('cafe_members').doc(`${uid}_${cafeId}`).get();
  return snapshot.data();
}

test('cafe creation operation IDs survive concurrent submission and lost-response retry without duplicate owners', async () => {
  const uid = `creation-owner-${Date.now()}`;
  const request = { db, uid, name: 'Durable Cafe', operationId: 'create-once' };
  const results = await Promise.all(Array.from({ length: 4 }, () => createCafe(request)));
  assert.equal(results.filter(result => !result.duplicate).length, 1);
  assert.equal(results.filter(result => result.duplicate).length, 3);
  assert.equal(new Set(results.map(result => result.cafeId)).size, 1);
  const first = results[0];
  const cafe = (await db.collection('cafes').doc(first.cafeId).get()).data();
  const owner = await membership(uid, first.cafeId);
  assert.equal((await createCafe(request)).duplicate, true);
  assert.deepEqual((await db.collection('cafes').doc(first.cafeId).get()).data(), cafe);
  assert.deepEqual(await membership(uid, first.cafeId), owner);
  assert.equal((await db.collection('cafes').where('ownerUid', '==', uid).get()).size, 1);
  await assert.rejects(createCafe({ ...request, name: 'Different Cafe' }), error =>
    error instanceof CafeOperationError && error.code === 'already-exists');
  await db.collection('cafe_members').doc(first.membershipId).update({ status: 'revoked' });
  await assert.rejects(createCafe(request), error =>
    error instanceof CafeOperationError && error.code === 'permission-denied');
  assert.equal((await db.collection('cafes').where('ownerUid', '==', uid).get()).size, 1);
});

test('creates café and active owner membership atomically', async () => {
  const created = await makeCafe('owner-create', 'Morning Brew');
  const cafe = await db.collection('cafes').doc(created.cafeId).get();
  const owner = await membership('owner-create', created.cafeId);

  assert.equal(cafe.data().name, 'Morning Brew');
  assert.equal(cafe.data().ownerUid, 'owner-create');
  assert.deepEqual(
    { uid: owner.uid, cafeId: owner.cafeId, role: owner.role, status: owner.status },
    { uid: 'owner-create', cafeId: created.cafeId, role: 'owner', status: 'active' },
  );
});

test('enforces owner and manager role limits when granting access', async () => {
  const { cafeId } = await makeCafe('owner-grants');
  await grantCafeMembership({
    db,
    callerUid: 'owner-grants',
    cafeId,
    targetUid: 'manager-grants',
    role: 'manager',
  });
  await grantCafeMembership({
    db,
    callerUid: 'manager-grants',
    cafeId,
    targetUid: 'staff-grants',
    role: 'staff',
  });

  await assert.rejects(
    grantCafeMembership({
      db,
      callerUid: 'manager-grants',
      cafeId,
      targetUid: 'manager-escalation',
      role: 'manager',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  await assert.rejects(
    grantCafeMembership({
      db,
      callerUid: 'staff-grants',
      cafeId,
      targetUid: 'staff-escalation',
      role: 'staff',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  assert.equal((await membership('staff-grants', cafeId)).status, 'active');
});

test('revokes access by role and cannot remove an owner', async () => {
  const { cafeId } = await makeCafe('owner-revokes');
  await grantCafeMembership({
    db,
    callerUid: 'owner-revokes',
    cafeId,
    targetUid: 'manager-revokes',
    role: 'manager',
  });
  await grantCafeMembership({
    db,
    callerUid: 'owner-revokes',
    cafeId,
    targetUid: 'staff-revokes',
    role: 'staff',
  });

  await revokeCafeMembership({
    db,
    callerUid: 'manager-revokes',
    cafeId,
    targetUid: 'staff-revokes',
  });
  await assert.rejects(
    revokeCafeMembership({
      db,
      callerUid: 'manager-revokes',
      cafeId,
      targetUid: 'manager-revokes',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'failed-precondition',
  );
  await assert.rejects(
    revokeCafeMembership({
      db,
      callerUid: 'manager-revokes',
      cafeId,
      targetUid: 'owner-revokes',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'failed-precondition',
  );

  await revokeCafeMembership({
    db,
    callerUid: 'owner-revokes',
    cafeId,
    targetUid: 'manager-revokes',
  });
  assert.equal((await membership('staff-revokes', cafeId)).status, 'revoked');
  assert.equal((await membership('manager-revokes', cafeId)).status, 'revoked');
  assert.equal((await membership('owner-revokes', cafeId)).status, 'active');
});

test('membership grants cannot cross café boundaries', async () => {
  const firstCafe = await makeCafe('owner-first-cafe');
  const secondCafe = await makeCafe('owner-second-cafe');
  await grantCafeMembership({
    db,
    callerUid: 'owner-first-cafe',
    cafeId: firstCafe.cafeId,
    targetUid: 'manager-first-cafe',
    role: 'manager',
  });

  await assert.rejects(
    grantCafeMembership({
      db,
      callerUid: 'manager-first-cafe',
      cafeId: secondCafe.cafeId,
      targetUid: 'intruder-target',
      role: 'staff',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  assert.equal(await membership('intruder-target', secondCafe.cafeId), undefined);
});

test('trusted operations reject active memberships with unsupported roles', async () => {
  const { cafeId } = await makeCafe('owner-malformed-role');
  await db.collection('cafe_members')
    .doc(`owner-malformed-role_${cafeId}`)
    .update({ role: 'superuser' });

  await assert.rejects(
    grantCafeMembership({
      db,
      callerUid: 'owner-malformed-role',
      cafeId,
      targetUid: 'malformed-role-target',
      role: 'staff',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  assert.equal(await membership('malformed-role-target', cafeId), undefined);
});

test('team listing is limited to active owners and managers in one café', async () => {
  const firstCafe = await makeCafe('owner-list-first');
  const secondCafe = await makeCafe('owner-list-second');
  await grantCafeMembership({
    db,
    callerUid: 'owner-list-first',
    cafeId: firstCafe.cafeId,
    targetUid: 'manager-list-first',
    role: 'manager',
  });
  await grantCafeMembership({
    db,
    callerUid: 'manager-list-first',
    cafeId: firstCafe.cafeId,
    targetUid: 'staff-list-first',
    role: 'staff',
  });
  await grantCafeMembership({
    db,
    callerUid: 'owner-list-second',
    cafeId: secondCafe.cafeId,
    targetUid: 'staff-list-second',
    role: 'staff',
  });

  const listed = await listCafeMemberships({
    db,
    callerUid: 'manager-list-first',
    cafeId: firstCafe.cafeId,
  });
  assert.equal(listed.callerRole, 'manager');
  assert.equal(listed.hasMore, false);
  assert.equal(listed.nextPageToken, null);
  assert.deepEqual(
    listed.memberships.map(({ uid, role }) => ({ uid, role })),
    [
      { uid: 'manager-list-first', role: 'manager' },
      { uid: 'owner-list-first', role: 'owner' },
      { uid: 'staff-list-first', role: 'staff' },
    ],
  );
  assert.equal(listed.memberships.every((item) => item.cafeId === firstCafe.cafeId), true);
  await assert.rejects(
    listCafeMemberships({
      db,
      callerUid: 'staff-list-first',
      cafeId: firstCafe.cafeId,
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
  await assert.rejects(
    listCafeMemberships({
      db,
      callerUid: 'manager-list-first',
      cafeId: secondCafe.cafeId,
    }),
    (error) => error instanceof CafeOperationError && error.code === 'permission-denied',
  );
});

test('team listing pages through more than 200 café memberships without gaps', async () => {
  const { cafeId } = await makeCafe('owner-large-team');
  const batch = db.batch();
  const expectedUids = [];
  for (let index = 0; index < 204; index += 1) {
    const uid = `member-${String(index).padStart(3, '0')}`;
    expectedUids.push(uid);
    batch.create(db.collection('cafe_members').doc(`${uid}_${cafeId}`), {
      uid,
      cafeId,
      role: 'staff',
      status: 'active',
    });
  }
  await batch.commit();

  const firstPage = await listCafeMemberships({
    db,
    callerUid: 'owner-large-team',
    cafeId,
  });
  assert.equal(firstPage.memberships.length, 200);
  assert.equal(firstPage.hasMore, true);
  assert.equal(typeof firstPage.nextPageToken, 'string');

  const secondPage = await listCafeMemberships({
    db,
    callerUid: 'owner-large-team',
    cafeId,
    pageToken: firstPage.nextPageToken,
  });
  assert.equal(secondPage.memberships.length, 5);
  assert.equal(secondPage.hasMore, false);
  assert.equal(secondPage.nextPageToken, null);

  const allUids = [...firstPage.memberships, ...secondPage.memberships]
    .map(({ uid }) => uid)
    .sort();
  assert.equal(new Set(allUids).size, 205);
  assert.deepEqual(allUids, [...expectedUids, 'owner-large-team'].sort());
  assert.ok([...firstPage.memberships, ...secondPage.memberships]
    .every((membership) => membership.cafeId === cafeId));
});

test('rejects invalid café names and owner role grants', async () => {
  await assert.rejects(
    makeCafe('owner-invalid-name', ' '),
    (error) => error instanceof CafeOperationError && error.code === 'invalid-argument',
  );
  const { cafeId } = await makeCafe('owner-no-owner-grants');
  await assert.rejects(
    grantCafeMembership({
      db,
      callerUid: 'owner-no-owner-grants',
      cafeId,
      targetUid: 'second-owner',
      role: 'owner',
    }),
    (error) => error instanceof CafeOperationError && error.code === 'invalid-argument',
  );
});
