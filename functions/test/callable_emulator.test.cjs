const assert = require('node:assert/strict');
const { after, before, test } = require('node:test');
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const projectId = 'brewverse-security-tests';
const functionsHost = 'http://127.0.0.1:5001';
let app;
let db;
let authToken;
let uid;
let cafeId;
let runId;

before(async () => {
  if (process.env.GCLOUD_PROJECT !== projectId ||
      !process.env.FIRESTORE_EMULATOR_HOST ||
      !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error(
      'Refusing to run callable integration tests outside the isolated Auth, '
      + 'Firestore, and Functions emulators.',
    );
  }
  runId = `callable-${Date.now()}`;
  app = initializeApp({ projectId }, runId);
  db = getFirestore(app);

  const authHost = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
  const authResponse = await fetch(
    `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: `${runId}@example.test`,
        password: 'local-only-password',
        returnSecureToken: true,
      }),
    },
  );
  const authResult = await authResponse.json();
  assert.equal(authResponse.ok, true, JSON.stringify(authResult));
  authToken = authResult.idToken;
  uid = authResult.localId;
});

after(async () => {
  if (app) await deleteApp(app);
});

async function callable(name, data, token = authToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(
    `${functionsHost}/${projectId}/us-central1/${name}`,
    {
      method: 'POST',
      headers,
      body: JSON.stringify({ data }),
    },
  );
  const result = await response.json();
  return { response, result };
}

async function createEmulatorUser(email) {
  const authHost = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
  const response = await fetch(
    `${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'local-only-password', returnSecureToken: true }),
    },
  );
  const result = await response.json();
  assert.equal(response.ok, true, JSON.stringify(result));
  return result;
}

test('authenticated app calls create a tenant and complete idempotent checkout', async () => {
  const cafeResult = await callable('createCafe', { name: 'Callable Test Café' });
  assert.equal(cafeResult.response.ok, true, JSON.stringify(cafeResult.result));
  cafeId = cafeResult.result.result.cafeId;
  assert.ok(cafeId);

  const ingredientResult = await callable('createStockItem', {
    cafeId,
    item: {
      name: 'Test beans',
      category: 'ingredient',
      unit: 'g',
      quantity: 10,
      minimumQuantity: 1,
      purchasePricePerUnit: 0.1,
      sellingPrice: 0,
    },
  });
  assert.equal(ingredientResult.response.ok, true, JSON.stringify(ingredientResult.result));
  const ingredientId = ingredientResult.result.result.stockItemId;

  const productResult = await callable('createStockItem', {
    cafeId,
    item: {
      name: 'Test espresso',
      category: 'finished',
      unit: 'cup',
      quantity: 0,
      minimumQuantity: 0,
      purchasePricePerUnit: 0,
      sellingPrice: 0.1,
    },
  });
  assert.equal(productResult.response.ok, true, JSON.stringify(productResult.result));
  const productId = productResult.result.result.stockItemId;

  const recipeResult = await callable('saveRecipe', {
    cafeId,
    productId,
    ingredients: [{ stockItemId: ingredientId, quantity: 2 }],
    packaging: [],
  });
  assert.equal(recipeResult.response.ok, true, JSON.stringify(recipeResult.result));

  const checkout = {
    cafeId,
    checkoutId: `${runId}-bill`,
    cart: { [productId]: 3 },
    orderType: 'dineIn',
    customerPhone: '+919876543210',
  };
  const firstBill = await callable('checkout', checkout);
  const retryBill = await callable('checkout', checkout);
  assert.equal(firstBill.response.ok, true, JSON.stringify(firstBill.result));
  assert.equal(firstBill.result.result.duplicate, false);
  assert.equal(retryBill.response.ok, true, JSON.stringify(retryBill.result));
  assert.equal(retryBill.result.result.duplicate, true);

  const beans = await db.collection('stock_items').doc(ingredientId).get();
  const bill = await db.collection('bills').doc(checkout.checkoutId).get();
  const movements = await db.collection('stock_movements')
    .where('cafeId', '==', cafeId)
    .where('stockItemId', '==', ingredientId)
    .get();
  assert.equal(beans.data().quantity, 4);
  assert.equal(bill.data().items[0].unitPrice, 0.1);
  assert.equal(bill.data().items[0].lineTotal, 0.3);
  assert.equal(bill.data().total, 0.3);
  assert.equal(bill.data().loyalty.pointsEarned, 0);
  const loyaltyCustomer = await callable('lookupLoyaltyCustomer', {
    cafeId,
    phoneNumber: '+91 98765-43210',
  });
  assert.equal(loyaltyCustomer.response.ok, true, JSON.stringify(loyaltyCustomer.result));
  assert.equal(loyaltyCustomer.result.result.customer.found, true);
  assert.equal(loyaltyCustomer.result.result.customer.pointsBalance, 0);
  assert.equal(movements.size, 2);

  const startAt = new Date(Date.now() - 60_000).toISOString();
  const endAt = new Date(Date.now() + 60_000).toISOString();
  const summary = await callable('getSalesSummary', { cafeId, startAt, endAt });
  assert.equal(summary.response.ok, true, JSON.stringify(summary.result));
  assert.equal(summary.result.result.completedBillCount, 1);
  assert.equal(summary.result.result.grossRevenue, 0.3);
  assert.equal(summary.result.result.bestSellingProducts[0].quantitySold, 3);

  const refund = await callable('refundBill', {
    cafeId,
    billId: checkout.checkoutId,
    adjustmentId: `${runId}-refund`,
    amountMinor: 30,
    reason: 'Test refund',
  });
  assert.equal(refund.response.ok, true, JSON.stringify(refund.result));
  assert.equal(refund.result.result.status, 'refunded');
  const duplicateRefund = await callable('refundBill', {
    cafeId,
    billId: checkout.checkoutId,
    adjustmentId: `${runId}-refund`,
    amountMinor: 30,
    reason: 'Test refund',
  });
  assert.equal(duplicateRefund.response.ok, true, JSON.stringify(duplicateRefund.result));
  assert.equal(duplicateRefund.result.result.duplicate, true);

  const secondSale = await callable('checkout', {
    cafeId,
    checkoutId: `${runId}-void-bill`,
    cart: { [productId]: 1 },
    orderType: 'dineIn',
  });
  assert.equal(secondSale.response.ok, true, JSON.stringify(secondSale.result));
  const voidResult = await callable('voidBill', {
    cafeId,
    billId: `${runId}-void-bill`,
    adjustmentId: `${runId}-void`,
    reason: 'Duplicate order',
  });
  assert.equal(voidResult.response.ok, true, JSON.stringify(voidResult.result));
  assert.equal(voidResult.result.result.status, 'void');
});

test('unauthenticated calls are rejected by the callable boundary', async () => {
  const result = await callable('createCafe', { name: 'Must Not Exist' }, null);
  assert.equal(result.response.ok, false);
  assert.equal(result.result.error?.status, 'UNAUTHENTICATED');
});

test('café owners can manage loyalty policy and managers cannot edit it', async () => {
  const cafe = await callable('createCafe', { name: 'Loyalty Policy Café' });
  assert.equal(cafe.response.ok, true, JSON.stringify(cafe.result));
  const loyaltyCafeId = cafe.result.result.cafeId;
  const settings = {
    enabled: true,
    spendUnitMinor: 10000,
    pointsPerSpendUnit: 4,
    pointValueMinor: 100,
    maxRedemptionPercent: 75,
    bonusTiers: [
      { minimumSpendMinor: 50000, points: 5 },
      { minimumSpendMinor: 100000, points: 10 },
    ],
    expiryMonths: 12,
    reverseEarnedOnRefund: true,
    restoreRedeemedOnRefund: true,
  };
  const saved = await callable('saveLoyaltySettings', {
    cafeId: loyaltyCafeId,
    settings,
  });
  assert.equal(saved.response.ok, true, JSON.stringify(saved.result));
  assert.deepEqual(saved.result.result.settings, settings);

  const loaded = await callable('getLoyaltySettings', {
    cafeId: loyaltyCafeId,
  });
  assert.equal(loaded.response.ok, true, JSON.stringify(loaded.result));
  assert.deepEqual(loaded.result.result.settings, settings);

  const invalidPolicy = await callable('saveLoyaltySettings', {
    cafeId: loyaltyCafeId,
    settings: { ...settings, maxRedemptionPercent: 101 },
  });
  assert.equal(invalidPolicy.response.ok, false);
  assert.equal(invalidPolicy.result.error?.status, 'INVALID_ARGUMENT');
  assert.equal(
    (await db.collection('cafes').doc(loyaltyCafeId).get())
      .data().loyaltySettings.maxRedemptionPercent,
    75,
  );

  const manager = await createEmulatorUser(`${runId}-loyalty-manager@example.test`);
  const grant = await callable('grantCafeMembership', {
    cafeId: loyaltyCafeId,
    email: manager.email,
    role: 'manager',
  });
  assert.equal(grant.response.ok, true, JSON.stringify(grant.result));
  const denied = await callable('saveLoyaltySettings', {
    cafeId: loyaltyCafeId,
    settings: { ...settings, pointsPerSpendUnit: 100 },
  }, manager.idToken);
  assert.equal(denied.response.ok, false);
  assert.equal(denied.result.error?.status, 'PERMISSION_DENIED');
  const unchanged = await db.collection('cafes').doc(loyaltyCafeId).get();
  assert.equal(unchanged.data().loyaltySettings.pointsPerSpendUnit, 4);
});

test('membership callables enforce role limits and revoked access', async () => {
  const ownerCafe = await callable('createCafe', { name: 'Role Test Café' });
  assert.equal(ownerCafe.response.ok, true, JSON.stringify(ownerCafe.result));
  const roleCafeId = ownerCafe.result.result.cafeId;

  const managerUser = await createEmulatorUser(`${runId}-manager@example.test`);
  const staffUser = await createEmulatorUser(`${runId}-staff@example.test`);
  const escalatedManagerUser = await createEmulatorUser(
    `${runId}-extra-manager@example.test`,
  );
  const grantManager = await callable('grantCafeMembership', {
    cafeId: roleCafeId,
    email: managerUser.email,
    role: 'manager',
  });
  assert.equal(grantManager.response.ok, true, JSON.stringify(grantManager.result));

  const managerEscalation = await callable('grantCafeMembership', {
    cafeId: roleCafeId,
    email: escalatedManagerUser.email,
    role: 'manager',
  }, managerUser.idToken);
  assert.equal(managerEscalation.response.ok, false);
  assert.equal(managerEscalation.result.error?.status, 'PERMISSION_DENIED');

  const grantStaff = await callable('grantCafeMembership', {
    cafeId: roleCafeId,
    email: staffUser.email,
    role: 'staff',
  });
  assert.equal(grantStaff.response.ok, true, JSON.stringify(grantStaff.result));

  const missingAccount = await callable('grantCafeMembership', {
    cafeId: roleCafeId,
    email: `${runId}-missing@example.test`,
    role: 'staff',
  });
  assert.equal(missingAccount.response.ok, false);
  assert.equal(missingAccount.result.error?.status, 'NOT_FOUND');

  const teamList = await callable('listCafeMemberships', {
    cafeId: roleCafeId,
  }, managerUser.idToken);
  assert.equal(teamList.response.ok, true, JSON.stringify(teamList.result));
  const listedMembers = teamList.result.result.memberships;
  assert.equal(listedMembers.length, 3);
  assert.equal(listedMembers.every((member) => member.cafeId === roleCafeId), true);
  assert.equal(listedMembers.find((member) => member.uid === uid)?.role, 'owner');
  assert.equal(
    listedMembers.find((member) => member.uid === managerUser.localId)?.role,
    'manager',
  );
  assert.equal(
    listedMembers.find((member) => member.uid === staffUser.localId)?.role,
    'staff',
  );

  const teamBatch = db.batch();
  for (let index = 0; index < 201; index += 1) {
    const memberUid = `${runId}-team-${String(index).padStart(3, '0')}`;
    teamBatch.create(db.collection('cafe_members').doc(`${memberUid}_${roleCafeId}`), {
      uid: memberUid,
      cafeId: roleCafeId,
      role: 'staff',
      status: 'active',
    });
  }
  await teamBatch.commit();

  const firstTeamPage = await callable('listCafeMemberships', {
    cafeId: roleCafeId,
  }, managerUser.idToken);
  assert.equal(firstTeamPage.response.ok, true, JSON.stringify(firstTeamPage.result));
  assert.equal(firstTeamPage.result.result.memberships.length, 200);
  assert.equal(firstTeamPage.result.result.hasMore, true);
  assert.equal(typeof firstTeamPage.result.result.nextPageToken, 'string');

  const secondTeamPage = await callable('listCafeMemberships', {
    cafeId: roleCafeId,
    pageToken: firstTeamPage.result.result.nextPageToken,
  }, managerUser.idToken);
  assert.equal(secondTeamPage.response.ok, true, JSON.stringify(secondTeamPage.result));
  assert.equal(secondTeamPage.result.result.memberships.length, 4);
  assert.equal(secondTeamPage.result.result.hasMore, false);
  assert.equal(secondTeamPage.result.result.nextPageToken, null);
  const allPageUids = [
    ...firstTeamPage.result.result.memberships,
    ...secondTeamPage.result.result.memberships,
  ].map((member) => member.uid);
  assert.equal(new Set(allPageUids).size, 204);
  assert.equal(allPageUids.every((memberUid) =>
    memberUid === uid || memberUid === managerUser.localId ||
    memberUid === staffUser.localId || memberUid.startsWith(`${runId}-team-`)), true);

  const invalidTeamCursor = await callable('listCafeMemberships', {
    cafeId: roleCafeId,
    pageToken: 'invalid/cursor',
  }, managerUser.idToken);
  assert.equal(invalidTeamCursor.response.ok, false);
  assert.equal(invalidTeamCursor.result.error?.status, 'INVALID_ARGUMENT');

  const staffList = await callable('listCafeMemberships', {
    cafeId: roleCafeId,
  }, staffUser.idToken);
  assert.equal(staffList.response.ok, false);
  assert.equal(staffList.result.error?.status, 'PERMISSION_DENIED');

  const staffCreate = await callable('createStockItem', {
    cafeId: roleCafeId,
    item: {
      name: 'Forbidden beans',
      category: 'ingredient',
      unit: 'g',
      quantity: 10,
      minimumQuantity: 1,
      purchasePricePerUnit: 0.1,
      sellingPrice: 0,
    },
  }, staffUser.idToken);
  assert.equal(staffCreate.response.ok, false);
  assert.equal(staffCreate.result.error?.status, 'PERMISSION_DENIED');

  const revokeStaff = await callable('revokeCafeMembership', {
    cafeId: roleCafeId,
    targetUid: staffUser.localId,
  });
  assert.equal(revokeStaff.response.ok, true, JSON.stringify(revokeStaff.result));
  const revokedStaffCreate = await callable('createStockItem', {
    cafeId: roleCafeId,
    item: {
      name: 'Revoked beans',
      category: 'ingredient',
      unit: 'g',
      quantity: 10,
      minimumQuantity: 1,
      purchasePricePerUnit: 0.1,
      sellingPrice: 0,
    },
  }, staffUser.idToken);
  assert.equal(revokedStaffCreate.response.ok, false);
  assert.equal(revokedStaffCreate.result.error?.status, 'PERMISSION_DENIED');
});
