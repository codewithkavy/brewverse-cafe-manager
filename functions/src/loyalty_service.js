const { createHash } = require('node:crypto');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const {
  CafeOperationError,
  requireActiveMembershipTx,
} = require('./membership_service');

const DEFAULT_LOYALTY_SETTINGS = Object.freeze({
  enabled: true,
  spendUnitMinor: 10000,
  pointsPerSpendUnit: 4,
  pointValueMinor: 100,
  maxRedemptionPercent: 100,
  bonusTiers: Object.freeze([
    Object.freeze({ minimumSpendMinor: 50000, points: 5 }),
    Object.freeze({ minimumSpendMinor: 100000, points: 10 }),
  ]),
  expiryMonths: 12,
  reverseEarnedOnRefund: true,
  restoreRedeemedOnRefund: true,
});

class LoyaltyPolicyError extends CafeOperationError {
  constructor(message) {
    super('invalid-argument', message);
    this.name = 'LoyaltyPolicyError';
  }
}

function normalizePhoneNumber(value) {
  if (typeof value !== 'string') {
    throw new LoyaltyPolicyError('Customer phone number is required.');
  }
  const phone = value.replace(/[\s()-]/g, '');
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) {
    throw new LoyaltyPolicyError(
      'Customer phone number must use international format, such as +919876543210.',
    );
  }
  return phone;
}

function customerIdForPhone({ cafeId, phoneNumber }) {
  const normalized = normalizePhoneNumber(phoneNumber);
  return createHash('sha256')
    .update(`${cafeId}\u0000${normalized}`)
    .digest('hex');
}

function addCalendarMonths(date, months) {
  const result = new Date(date.getTime());
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + months);
  const lastDay = new Date(Date.UTC(
    result.getUTCFullYear(), result.getUTCMonth() + 1, 0,
  )).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  result.setUTCHours(23, 59, 59, 999);
  return result;
}

function parsePointBuckets(value, now) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 4000) {
    throw new CafeOperationError('failed-precondition', 'Customer points data needs review.');
  }
  const nowMs = now.getTime();
  return value.flatMap((bucket) => {
    if (bucket == null || typeof bucket !== 'object' ||
        !Number.isSafeInteger(bucket.points) || bucket.points <= 0) {
      throw new CafeOperationError('failed-precondition', 'Customer points data needs review.');
    }
    if (bucket.expiresAt == null) {
      return [{ expiresAt: null, points: bucket.points }];
    }
    const expiration = bucket.expiresAt.toDate?.() ?? new Date(bucket.expiresAt);
    if (!Number.isFinite(expiration.getTime())) {
      throw new CafeOperationError('failed-precondition', 'Customer points expiry data is invalid.');
    }
    if (expiration.getTime() <= nowMs) return [];
    return [{ expiresAt: expiration, points: bucket.points }];
  });
}

async function prepareCheckoutLoyaltyTx({
  transaction,
  db,
  cafeId,
  billId,
  phoneNumber,
  redeemPoints,
  subtotalMinor,
  now = new Date(),
}) {
  if (phoneNumber == null || phoneNumber === '') {
    if (redeemPoints !== 0) {
      throw new LoyaltyPolicyError('A customer phone number is required to redeem points.');
    }
    return {
      subtotalMinor,
      discountMinor: 0,
      netPaidMinor: subtotalMinor,
      customerId: null,
      pointsEarned: 0,
      pointsRedeemed: 0,
      balanceAfter: null,
    };
  }

  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  const customerId = customerIdForPhone({ cafeId, phoneNumber: normalizedPhone });
  const cafeRef = db.collection('cafes').doc(cafeId);
  const customerRef = cafeRef.collection('loyaltyCustomers').doc(customerId);
  const [cafeSnapshot, customerSnapshot] = await Promise.all([
    transaction.get(cafeRef),
    transaction.get(customerRef),
  ]);
  const settings = resolveLoyaltySettings(cafeSnapshot.data()?.loyaltySettings ?? null);
  const current = customerSnapshot.data() ?? {};
  const buckets = parsePointBuckets(current.pointsBuckets, now);
  const storedDebt = current.pointsDebt ?? 0;
  if (!Number.isSafeInteger(storedDebt) || storedDebt < 0) {
    throw new CafeOperationError('failed-precondition', 'Customer points debt data is invalid.');
  }
  const balance = buckets.reduce((sum, bucket) => sum + bucket.points, 0) - storedDebt;
  if (!Number.isSafeInteger(balance)) {
    throw new CafeOperationError('failed-precondition', 'Customer points balance needs review.');
  }
  const redemption = calculateRedemption({
    requestedPoints: redeemPoints,
    balancePoints: Math.max(0, balance),
    billTotalMinor: subtotalMinor,
    settings,
  });
  let pointsRemainingToRedeem = redemption.points;
  const allocations = [];
  buckets.sort((left, right) => {
    if (left.expiresAt == null) return right.expiresAt == null ? 0 : 1;
    if (right.expiresAt == null) return -1;
    return left.expiresAt.getTime() - right.expiresAt.getTime();
  });
  for (const bucket of buckets) {
    if (pointsRemainingToRedeem === 0) break;
    const used = Math.min(bucket.points, pointsRemainingToRedeem);
    bucket.points -= used;
    pointsRemainingToRedeem -= used;
    allocations.push({
      points: used,
      expiresAt: bucket.expiresAt,
    });
  }
  if (pointsRemainingToRedeem !== 0) {
    throw new CafeOperationError('failed-precondition', 'Customer points balance changed. Retry checkout.');
  }
  const netPaidMinor = subtotalMinor - redemption.discountMinor;
  const pointsEarned = calculateEarnedPoints({ netPaidMinor, settings });
  let pointsDebt = storedDebt;
  const pointsAppliedToDebt = Math.min(pointsDebt, pointsEarned);
  pointsDebt -= pointsAppliedToDebt;
  const pointsAdded = pointsEarned - pointsAppliedToDebt;
  let expiration = null;
  if (pointsAdded > 0 && settings.expiryMonths != null) {
    expiration = addCalendarMonths(now, settings.expiryMonths);
  }
  if (pointsAdded > 0) {
    const existingBucket = buckets.find((bucket) =>
      (bucket.expiresAt == null && expiration == null) ||
      (bucket.expiresAt != null && expiration != null &&
        bucket.expiresAt.getTime() === expiration.getTime()));
    if (existingBucket) {
      existingBucket.points += pointsAdded;
    } else {
      buckets.push({ expiresAt: expiration, points: pointsAdded });
    }
  }
  const balanceAfter = buckets.reduce((sum, bucket) => sum + bucket.points, 0) - pointsDebt;
  const ledgerRef = cafeRef.collection('loyaltyTransactions').doc(`${billId}_checkout`);
  transaction.set(customerRef, {
    cafeId,
    customerId,
    phoneNumber: normalizedPhone,
    pointsBuckets: buckets.map((bucket) => ({
      expiresAt: bucket.expiresAt == null
        ? null
        : Timestamp.fromDate(bucket.expiresAt),
      points: bucket.points,
    })).filter((bucket) => bucket.points > 0),
    pointsDebt,
    pointsBalance: balanceAfter,
    updatedAt: FieldValue.serverTimestamp(),
    ...(customerSnapshot.exists ? {} : { createdAt: FieldValue.serverTimestamp() }),
  }, { merge: true });
  transaction.create(ledgerRef, {
    cafeId,
    customerId,
    billId,
    type: 'checkout',
    subtotalMinor,
    discountMinor: redemption.discountMinor,
    netPaidMinor,
    pointsEarned,
    pointsAppliedToDebt,
    pointsRedeemed: redemption.points,
    redeemedAllocations: allocations.map((allocation) => ({
      points: allocation.points,
      expiresAt: allocation.expiresAt == null
        ? null
        : Timestamp.fromDate(allocation.expiresAt),
    })),
    expiresAt: expiration == null ? null : Timestamp.fromDate(expiration),
    reverseEarnedOnRefund: settings.reverseEarnedOnRefund,
    restoreRedeemedOnRefund: settings.restoreRedeemedOnRefund,
    balanceAfter,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {
    subtotalMinor,
    discountMinor: redemption.discountMinor,
    netPaidMinor,
    customerId,
    pointsEarned,
    pointsRedeemed: redemption.points,
    balanceAfter,
  };
}

async function reverseCheckoutLoyaltyTx({
  transaction,
  db,
  cafeId,
  billId,
  adjustmentId,
  targetPointsReversed,
  targetPointsRestored,
  now = new Date(),
}) {
  const cafeRef = db.collection('cafes').doc(cafeId);
  const originalLedgerRef = cafeRef.collection('loyaltyTransactions')
    .doc(`${billId}_checkout`);
  const originalSnapshot = await transaction.get(originalLedgerRef);
  if (!originalSnapshot.exists) {
    throw new CafeOperationError('failed-precondition', 'Original loyalty transaction is missing.');
  }
  const original = originalSnapshot.data();
  const customerId = original.customerId;
  if (typeof customerId !== 'string' || !/^[a-f0-9]{64}$/.test(customerId)) {
    throw new CafeOperationError('failed-precondition', 'Original loyalty customer is invalid.');
  }
  const customerRef = cafeRef.collection('loyaltyCustomers').doc(customerId);
  const [customerSnapshot, cafeSnapshot] = await Promise.all([
    transaction.get(customerRef),
    transaction.get(cafeRef),
  ]);
  if (!customerSnapshot.exists) {
    throw new CafeOperationError('failed-precondition', 'Loyalty customer record is missing.');
  }
  const settings = resolveLoyaltySettings(cafeSnapshot.data()?.loyaltySettings ?? null);
  const reverseEarnedOnRefund = typeof original.reverseEarnedOnRefund === 'boolean'
    ? original.reverseEarnedOnRefund
    : settings.reverseEarnedOnRefund;
  const restoreRedeemedOnRefund = typeof original.restoreRedeemedOnRefund === 'boolean'
    ? original.restoreRedeemedOnRefund
    : settings.restoreRedeemedOnRefund;
  const customer = customerSnapshot.data();
  const buckets = parsePointBuckets(customer.pointsBuckets, now);
  let pointsDebt = customer.pointsDebt ?? 0;
  if (!Number.isSafeInteger(pointsDebt) || pointsDebt < 0) {
    throw new CafeOperationError('failed-precondition', 'Customer points debt data is invalid.');
  }

  const pointsReversed = reverseEarnedOnRefund
    ? Math.max(0, targetPointsReversed)
    : 0;
  let remainingToReverse = pointsReversed;
  buckets.sort((left, right) => {
    if (left.expiresAt == null) return right.expiresAt == null ? 0 : 1;
    if (right.expiresAt == null) return -1;
    return right.expiresAt.getTime() - left.expiresAt.getTime();
  });
  for (const bucket of buckets) {
    if (remainingToReverse === 0) break;
    const removed = Math.min(bucket.points, remainingToReverse);
    bucket.points -= removed;
    remainingToReverse -= removed;
  }
  pointsDebt += remainingToReverse;

  let pointsRestored = 0;
  if (restoreRedeemedOnRefund && targetPointsRestored > 0) {
    const allocations = Array.isArray(original.redeemedAllocations)
      ? original.redeemedAllocations
      : [];
    let toRestore = Math.min(
      targetPointsRestored,
      Number.isSafeInteger(original.pointsRedeemed) ? original.pointsRedeemed : 0,
    );
    for (const allocation of allocations) {
      if (toRestore <= 0) break;
      if (allocation == null || !Number.isSafeInteger(allocation.points) ||
          allocation.points <= 0) continue;
      const expiry = allocation.expiresAt == null
        ? null
        : (allocation.expiresAt.toDate?.() ?? new Date(allocation.expiresAt));
      if (expiry != null && (!Number.isFinite(expiry.getTime()) || expiry <= now)) {
        continue;
      }
      const restored = Math.min(toRestore, allocation.points);
      const appliedToDebt = Math.min(pointsDebt, restored);
      pointsDebt -= appliedToDebt;
      const remainder = restored - appliedToDebt;
      if (remainder > 0) {
        const existing = buckets.find((bucket) =>
          (bucket.expiresAt == null && expiry == null) ||
          (bucket.expiresAt != null && expiry != null &&
            bucket.expiresAt.getTime() === expiry.getTime()));
        if (existing) existing.points += remainder;
        else buckets.push({ expiresAt: expiry, points: remainder });
      }
      pointsRestored += restored;
      toRestore -= restored;
    }
  }
  const balanceAfter = buckets.reduce((sum, bucket) => sum + bucket.points, 0) - pointsDebt;
  const adjustmentRef = cafeRef.collection('loyaltyTransactions')
    .doc(`${adjustmentId}_refund`);
  transaction.set(customerRef, {
    pointsBuckets: buckets.filter((bucket) => bucket.points > 0).map((bucket) => ({
      expiresAt: bucket.expiresAt == null ? null : Timestamp.fromDate(bucket.expiresAt),
      points: bucket.points,
    })),
    pointsDebt,
    pointsBalance: balanceAfter,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  transaction.create(adjustmentRef, {
    cafeId,
    customerId,
    billId,
    adjustmentId,
    type: 'refund',
    pointsReversed,
    pointsRestored,
    pointsDebtAfter: pointsDebt,
    balanceAfter,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { customerId, pointsReversed, pointsRestored, balanceAfter };
}

function requiredText(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0 ||
      value.includes('/') || value.length > 1500) {
    throw new LoyaltyPolicyError(`${label} is invalid.`);
  }
  return value.trim();
}

function validateLoyaltySettings(input) {
  if (input == null || typeof input !== 'object' || Array.isArray(input)) {
    throw new LoyaltyPolicyError('Loyalty settings must be an object.');
  }
  const { enabled, spendUnitMinor, pointsPerSpendUnit, pointValueMinor,
    maxRedemptionPercent, expiryMonths } = input;
  const reverseEarnedOnRefund = input.reverseEarnedOnRefund ?? true;
  const restoreRedeemedOnRefund = input.restoreRedeemedOnRefund ?? true;
  if (typeof enabled !== 'boolean') {
    throw new LoyaltyPolicyError('Loyalty enabled must be true or false.');
  }
  if (typeof reverseEarnedOnRefund !== 'boolean' ||
      typeof restoreRedeemedOnRefund !== 'boolean') {
    throw new LoyaltyPolicyError('Refund point handling must use true or false.');
  }
  if (!Number.isSafeInteger(spendUnitMinor) || spendUnitMinor < 1 ||
      spendUnitMinor > 100000000) {
    throw new LoyaltyPolicyError('Spend unit must be a positive amount in paise.');
  }
  if (!Number.isSafeInteger(pointsPerSpendUnit) || pointsPerSpendUnit < 0 ||
      pointsPerSpendUnit > 100000) {
    throw new LoyaltyPolicyError('Earned points per spend unit are invalid.');
  }
  if (!Number.isSafeInteger(pointValueMinor) || pointValueMinor < 1 ||
      pointValueMinor > 100000000) {
    throw new LoyaltyPolicyError('Point redemption value must be positive paise.');
  }
  if (!Number.isSafeInteger(maxRedemptionPercent) ||
      maxRedemptionPercent < 0 || maxRedemptionPercent > 100) {
    throw new LoyaltyPolicyError('Redemption limit must be between 0 and 100 percent.');
  }
  if (expiryMonths !== null &&
      (!Number.isSafeInteger(expiryMonths) || expiryMonths < 1 || expiryMonths > 120)) {
    throw new LoyaltyPolicyError('Expiry must be disabled or between 1 and 120 months.');
  }
  if (!Array.isArray(input.bonusTiers) || input.bonusTiers.length > 10) {
    throw new LoyaltyPolicyError('Bonus tiers must be a list of at most 10 entries.');
  }
  const bonusTiers = input.bonusTiers.map((tier) => {
    if (tier == null || typeof tier !== 'object' || Array.isArray(tier) ||
        !Number.isSafeInteger(tier.minimumSpendMinor) ||
        tier.minimumSpendMinor < 1 ||
        !Number.isSafeInteger(tier.points) || tier.points < 0 || tier.points > 100000) {
      throw new LoyaltyPolicyError('A loyalty bonus tier is invalid.');
    }
    return {
      minimumSpendMinor: tier.minimumSpendMinor,
      points: tier.points,
    };
  }).sort((left, right) => left.minimumSpendMinor - right.minimumSpendMinor);
  for (let index = 1; index < bonusTiers.length; index += 1) {
    if (bonusTiers[index - 1].minimumSpendMinor === bonusTiers[index].minimumSpendMinor) {
      throw new LoyaltyPolicyError('Bonus tier spend thresholds must be unique.');
    }
  }
  return {
    enabled,
    spendUnitMinor,
    pointsPerSpendUnit,
    pointValueMinor,
    maxRedemptionPercent,
    bonusTiers,
    expiryMonths,
    reverseEarnedOnRefund,
    restoreRedeemedOnRefund,
  };
}

function resolveLoyaltySettings(savedSettings) {
  if (savedSettings == null) {
    return validateLoyaltySettings({
      ...DEFAULT_LOYALTY_SETTINGS,
      bonusTiers: DEFAULT_LOYALTY_SETTINGS.bonusTiers.map((tier) => ({ ...tier })),
    });
  }
  return validateLoyaltySettings(savedSettings);
}

function calculateEarnedPoints({ netPaidMinor, settings }) {
  settings = resolveLoyaltySettings(settings);
  if (!Number.isSafeInteger(netPaidMinor) || netPaidMinor < 0) {
    throw new LoyaltyPolicyError('Paid amount must be a non-negative amount in paise.');
  }
  if (!settings.enabled) return 0;
  const basePoints = Math.floor(netPaidMinor / settings.spendUnitMinor) *
    settings.pointsPerSpendUnit;
  const bonusPoints = settings.bonusTiers
    .filter((tier) => netPaidMinor >= tier.minimumSpendMinor)
    .reduce((highest, tier) => Math.max(highest, tier.points), 0);
  const total = basePoints + bonusPoints;
  if (!Number.isSafeInteger(total)) {
    throw new LoyaltyPolicyError('Earned points exceed the supported limit.');
  }
  return total;
}

function calculateRedemption({ requestedPoints, balancePoints, billTotalMinor, settings }) {
  settings = resolveLoyaltySettings(settings);
  if (!Number.isSafeInteger(requestedPoints) || requestedPoints < 0 ||
      !Number.isSafeInteger(balancePoints) || balancePoints < 0 ||
      !Number.isSafeInteger(billTotalMinor) || billTotalMinor < 0) {
    throw new LoyaltyPolicyError('Loyalty redemption values are invalid.');
  }
  if (!settings.enabled && requestedPoints > 0) {
    throw new LoyaltyPolicyError('Loyalty is disabled for this café.');
  }
  if (requestedPoints > balancePoints) {
    throw new LoyaltyPolicyError('Customer does not have enough points.');
  }
  const maximumDiscountMinor = Math.floor(
    billTotalMinor * settings.maxRedemptionPercent / 100,
  );
  const maximumPoints = Math.floor(maximumDiscountMinor / settings.pointValueMinor);
  if (requestedPoints > maximumPoints) {
    throw new LoyaltyPolicyError('Redemption exceeds this café’s bill limit.');
  }
  return {
    points: requestedPoints,
    discountMinor: requestedPoints * settings.pointValueMinor,
  };
}

async function getLoyaltySettings({ db, callerUid, cafeId }) {
  callerUid = requiredText(callerUid, 'Authenticated user ID');
  cafeId = requiredText(cafeId, 'Café ID');
  return db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
    });
    const cafeSnapshot = await transaction.get(db.collection('cafes').doc(cafeId));
    return resolveLoyaltySettings(cafeSnapshot.data()?.loyaltySettings ?? null);
  });
}

async function saveLoyaltySettings({ db, callerUid, cafeId, settings }) {
  callerUid = requiredText(callerUid, 'Authenticated user ID');
  cafeId = requiredText(cafeId, 'Café ID');
  settings = validateLoyaltySettings(settings);
  await db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: ['owner'],
    });
    await require('./subscription_service').requireCafeSubscriptionTx({transaction,db,cafeId});
    transaction.update(db.collection('cafes').doc(cafeId), {
      loyaltySettings: settings,
      loyaltySettingsUpdatedAt: FieldValue.serverTimestamp(),
    });
  });
  return settings;
}

async function lookupLoyaltyCustomer({ db, callerUid, cafeId, phoneNumber }) {
  callerUid = requiredText(callerUid, 'Authenticated user ID');
  cafeId = requiredText(cafeId, 'Café ID');
  const normalizedPhone = normalizePhoneNumber(phoneNumber);
  const customerId = customerIdForPhone({ cafeId, phoneNumber: normalizedPhone });
  const result = await db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: ['owner', 'manager', 'staff'],
    });
    const customerRef = db.collection('cafes').doc(cafeId)
      .collection('loyaltyCustomers').doc(customerId);
    const customerSnapshot = await transaction.get(customerRef);
    return customerSnapshot.exists ? customerSnapshot.data() : null;
  });
  if (result == null) {
    return { found: false, customerId, phoneNumber: normalizedPhone, pointsBalance: 0 };
  }
  const buckets = parsePointBuckets(result.pointsBuckets, new Date());
  const debt = result.pointsDebt ?? 0;
  if (!Number.isSafeInteger(debt) || debt < 0) {
    throw new CafeOperationError('failed-precondition', 'Customer points data needs review.');
  }
  const pointsBalance = Math.max(
    0,
    buckets.reduce((sum, bucket) => sum + bucket.points, 0) - debt,
  );
  return {
    found: true,
    customerId,
    phoneNumber: normalizedPhone,
    pointsBalance,
  };
}

module.exports = {
  DEFAULT_LOYALTY_SETTINGS,
  LoyaltyPolicyError,
  calculateEarnedPoints,
  calculateRedemption,
  customerIdForPhone,
  getLoyaltySettings,
  lookupLoyaltyCustomer,
  normalizePhoneNumber,
  prepareCheckoutLoyaltyTx,
  resolveLoyaltySettings,
  reverseCheckoutLoyaltyTx,
  saveLoyaltySettings,
  validateLoyaltySettings,
};

