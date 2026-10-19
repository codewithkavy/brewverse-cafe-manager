const { getApps, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { HttpsError, onCall } = require('firebase-functions/v2/https');

const {
  CafeOperationError,
  createCafe: createCafeRecord,
  grantCafeMembership: grantMembershipRecord,
  listCafeMemberships: listMembershipsRecord,
  revokeCafeMembership: revokeMembershipRecord,
  requireActiveMembershipTx,
} = require('./membership_service');
const {
  addStock,
  checkout: checkoutRecord,
  createStockItem,
  getSalesSummary,
  saveRecipe,
} = require('./inventory_service');
const {
  getLoyaltySettings,
  lookupLoyaltyCustomer,
  saveLoyaltySettings,
} = require('./loyalty_service');
const {
  refundBill: refundBillRecord,
  voidBill: voidBillRecord,
} = require('./billing_service');

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

function callable(operation) {
  return onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign in to continue.');
    }
    try {
      return await operation(uid, request.data ?? {});
    } catch (error) {
      if (error instanceof CafeOperationError) {
        throw new HttpsError(error.code, error.message);
      }
      console.error('Trusted café operation failed.', error);
      throw new HttpsError('internal', 'The café operation could not be completed.');
    }
  });
}

exports.createCafe = callable((uid, data) =>
  createCafeRecord({ db, uid, name: data.name }),
);

exports.grantCafeMembership = callable(async (uid, data) => {
  const cafeId = data.cafeId;
  await db.runTransaction((transaction) => requireActiveMembershipTx({
    transaction,
    db,
    uid,
    cafeId,
    roles: ['owner', 'manager'],
  }));

  const email = typeof data.email === 'string' ? data.email.trim() : '';
  if (!email || email.length > 254 || !email.includes('@')) {
    throw new CafeOperationError('invalid-argument', 'A valid account email is required.');
  }
  let target;
  try {
    target = await getAuth().getUserByEmail(email.toLowerCase());
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      throw new CafeOperationError('not-found', 'No BrewVerse account exists with that email.');
    }
    throw error;
  }
  return grantMembershipRecord({
    db,
    callerUid: uid,
    cafeId,
    targetUid: target.uid,
    role: data.role,
  });
});

exports.revokeCafeMembership = callable((uid, data) =>
  revokeMembershipRecord({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    targetUid: data.targetUid,
  }),
);

exports.listCafeMemberships = callable((uid, data) =>
  listMembershipsRecord({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    pageToken: data.pageToken,
  }),
);

exports.createStockItem = callable((uid, data) =>
  createStockItem({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    item: data.item,
  }),
);

exports.addStock = callable((uid, data) =>
  addStock({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    stockItemId: data.stockItemId,
    quantity: data.quantity,
    reason: data.reason,
  }),
);

exports.saveRecipe = callable((uid, data) =>
  saveRecipe({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    productId: data.productId,
    ingredients: data.ingredients,
    packaging: data.packaging,
  }),
);

exports.checkout = callable((uid, data) =>
  checkoutRecord({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    checkoutId: data.checkoutId,
    cart: data.cart,
    orderType: data.orderType,
    customerPhone: data.customerPhone,
    redeemPoints: data.redeemPoints,
  }),
);

exports.getSalesSummary = callable((uid, data) =>
  getSalesSummary({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    startAt: data.startAt,
    endAt: data.endAt,
  }),
);

exports.getLoyaltySettings = callable(async (uid, data) => ({
  settings: await getLoyaltySettings({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
  }),
}));

exports.saveLoyaltySettings = callable(async (uid, data) => ({
  settings: await saveLoyaltySettings({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    settings: data.settings,
  }),
}));

exports.lookupLoyaltyCustomer = callable(async (uid, data) => ({
  customer: await lookupLoyaltyCustomer({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    phoneNumber: data.phoneNumber,
  }),
}));

exports.refundBill = callable((uid, data) =>
  refundBillRecord({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    billId: data.billId,
    adjustmentId: data.adjustmentId,
    requestedAmountMinor: data.amountMinor,
    reason: data.reason,
  }),
);

exports.voidBill = callable((uid, data) =>
  voidBillRecord({
    db,
    callerUid: uid,
    cafeId: data.cafeId,
    billId: data.billId,
    adjustmentId: data.adjustmentId,
    reason: data.reason,
  }),
);
