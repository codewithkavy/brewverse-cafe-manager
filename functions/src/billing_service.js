const { FieldValue } = require('firebase-admin/firestore');

const {
  CafeOperationError,
  requireActiveMembershipTx,
} = require('./membership_service');
const { reverseCheckoutLoyaltyTx } = require('./loyalty_service');

function requiredDocumentId(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0 ||
      value.includes('/') || value.length > 1500) {
    throw new CafeOperationError('invalid-argument', `${label} is invalid.`);
  }
  return value.trim();
}

function amountMinor(value) {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new CafeOperationError(
      'invalid-argument',
      'Refund amount must be a non-negative whole amount in paise.',
    );
  }
  return value;
}

async function adjustBill({
  db,
  callerUid,
  cafeId,
  billId,
  adjustmentId,
  requestedAmountMinor,
  reason,
  mode,
}) {
  callerUid = requiredDocumentId(callerUid, 'Authenticated user ID');
  cafeId = requiredDocumentId(cafeId, 'Café ID');
  billId = requiredDocumentId(billId, 'Bill ID');
  adjustmentId = requiredDocumentId(adjustmentId, 'Adjustment ID');
  if (mode !== 'refund' && mode !== 'void') {
    throw new CafeOperationError('invalid-argument', 'Bill adjustment type is invalid.');
  }
  if (mode === 'refund') requestedAmountMinor = amountMinor(requestedAmountMinor);
  const cleanReason = typeof reason === 'string' ? reason.trim().slice(0, 200) : '';
  const billRef = db.collection('bills').doc(billId);
  const cafeRef = db.collection('cafes').doc(cafeId);
  const adjustmentRef = cafeRef.collection('billAdjustments').doc(adjustmentId);

  return db.runTransaction(async (transaction) => {
    await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: ['owner', 'manager'],
    });
    const [billSnapshot, priorAdjustment] = await Promise.all([
      transaction.get(billRef),
      transaction.get(adjustmentRef),
    ]);
    if (priorAdjustment.exists) {
      const saved = priorAdjustment.data();
      if (saved.billId !== billId || saved.mode !== mode ||
          (mode === 'refund' && saved.refundMinor !== requestedAmountMinor)) {
        throw new CafeOperationError(
          'already-exists',
          'Adjustment ID was already used for another bill operation.',
        );
      }
      return {
        billId,
        adjustmentId,
        duplicate: true,
        status: saved.status,
        refundedMinor: saved.refundedMinor,
      };
    }
    const bill = billSnapshot.data();
    if (!billSnapshot.exists || bill.cafeId !== cafeId) {
      throw new CafeOperationError('not-found', 'Bill not found in this café.');
    }
    if (bill.status !== 'completed' && bill.status !== 'partially_refunded') {
      throw new CafeOperationError(
        'failed-precondition',
        'Only a completed or partially refunded bill can be adjusted.',
      );
    }
    const totalMinor = Math.round(Number(bill.total) * 100);
    if (!Number.isSafeInteger(totalMinor) || totalMinor < 0) {
      throw new CafeOperationError('failed-precondition', 'Saved bill total is invalid.');
    }
    const refundedBefore = bill.refundedMinor ?? 0;
    if (!Number.isSafeInteger(refundedBefore) || refundedBefore < 0 ||
        refundedBefore > totalMinor) {
      throw new CafeOperationError('failed-precondition', 'Saved refund total is invalid.');
    }
    const remainingMinor = totalMinor - refundedBefore;
    const refundMinor = mode === 'void' ? remainingMinor : requestedAmountMinor;
    if ((mode === 'refund' && refundMinor === 0) || refundMinor > remainingMinor) {
      throw new CafeOperationError(
        'failed-precondition',
        'Refund amount must be greater than zero and no more than the remaining bill total.',
      );
    }
    const refundedAfter = refundedBefore + refundMinor;
    const fullAdjustment = refundedAfter === totalMinor;
    const status = mode === 'void'
      ? 'void'
      : fullAdjustment ? 'refunded' : 'partially_refunded';

    let loyaltyAdjustment = {
      pointsReversed: 0,
      pointsRestored: 0,
      balanceAfter: null,
    };
    if (bill.loyalty?.customerId != null) {
      const earnedPoints = Number.isSafeInteger(bill.loyalty.pointsEarned)
        ? bill.loyalty.pointsEarned
        : 0;
      const redeemedPoints = Number.isSafeInteger(bill.loyalty.pointsRedeemed)
        ? bill.loyalty.pointsRedeemed
        : 0;
      const proportion = mode === 'void' || totalMinor === 0
        ? 1
        : refundedAfter / totalMinor;
      const totalPointsReversed = Math.floor(earnedPoints * proportion);
      const totalPointsRestored = Math.floor(redeemedPoints * proportion);
      const alreadyReversed = bill.refundPointsReversed ?? 0;
      const alreadyRestored = bill.refundPointsRestored ?? 0;
      if (!Number.isSafeInteger(alreadyReversed) || alreadyReversed < 0 ||
          !Number.isSafeInteger(alreadyRestored) || alreadyRestored < 0) {
        throw new CafeOperationError('failed-precondition', 'Saved loyalty refund data is invalid.');
      }
      const targetPointsReversed = Math.max(0, totalPointsReversed - alreadyReversed);
      const targetPointsRestored = Math.max(0, totalPointsRestored - alreadyRestored);
      loyaltyAdjustment = await reverseCheckoutLoyaltyTx({
        transaction,
        db,
        cafeId,
        billId,
        adjustmentId,
        targetPointsReversed,
        targetPointsRestored,
      });
    }

    transaction.create(adjustmentRef, {
      cafeId,
      billId,
      adjustmentId,
      mode,
      reason: cleanReason,
      refundMinor,
      refundedMinor: refundedAfter,
      status,
      ...loyaltyAdjustment,
      stockRestocked: false,
      createdBy: callerUid,
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(billRef, {
      status,
      refundedMinor: refundedAfter,
      refundPointsReversed: (bill.refundPointsReversed ?? 0) +
        loyaltyAdjustment.pointsReversed,
      refundPointsRestored: (bill.refundPointsRestored ?? 0) +
        loyaltyAdjustment.pointsRestored,
      lastAdjustmentId: adjustmentId,
      lastAdjustedBy: callerUid,
      lastAdjustedAt: FieldValue.serverTimestamp(),
    });
    return {
      billId,
      adjustmentId,
      duplicate: false,
      status,
      refundedMinor: refundedAfter,
      pointsReversed: loyaltyAdjustment.pointsReversed,
      pointsRestored: loyaltyAdjustment.pointsRestored,
      pointsBalance: loyaltyAdjustment.balanceAfter,
    };
  });
}

function refundBill(args) {
  return adjustBill({ ...args, mode: 'refund' });
}

function voidBill(args) {
  return adjustBill({
    ...args,
    mode: 'void',
    requestedAmountMinor: undefined,
  });
}

module.exports = { adjustBill, refundBill, voidBill };
