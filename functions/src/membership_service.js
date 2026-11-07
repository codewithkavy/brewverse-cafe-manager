const { createHash } = require('node:crypto');
const { FieldPath, FieldValue } = require('firebase-admin/firestore');

const VALID_ROLES = new Set(['owner', 'manager', 'staff']);

class CafeOperationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'CafeOperationError';
    this.code = code;
  }
}

function requireText(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new CafeOperationError('invalid-argument', `${label} is required.`);
  }
  return value.trim();
}

function membershipRef(db, uid, cafeId) {
  return db.collection('cafe_members').doc(`${uid}_${cafeId}`);
}

function validateMembership(data, uid, cafeId) {
  return data != null &&
    data.uid === uid &&
    data.cafeId === cafeId &&
    data.status === 'active' &&
    VALID_ROLES.has(data.role);
}

async function requireActiveMembershipTx({
  transaction,
  db,
  uid,
  cafeId,
  roles,
}) {
  const memberId = membershipRef(db, uid, cafeId);
  const cafeRef = db.collection('cafes').doc(cafeId);
  const [membershipSnapshot, cafeSnapshot] = await Promise.all([
    transaction.get(memberId),
    transaction.get(cafeRef),
  ]);
  const membership = membershipSnapshot.data();
  if (!validateMembership(membership, uid, cafeId)) {
    throw new CafeOperationError(
      'permission-denied',
      'An active café membership is required.',
    );
  }
  if (!cafeSnapshot.exists) {
    throw new CafeOperationError('not-found', 'Café not found.');
  }
  if (roles != null && !roles.includes(membership.role)) {
    throw new CafeOperationError(
      'permission-denied',
      'Your café role cannot perform this operation.',
    );
  }
  return membership;
}

async function createCafe({ db, uid, name, operationId }) {
  uid = requireText(uid, 'Authenticated user ID');
  name = requireText(name, 'Café name');
  if (name.length < 2 || name.length > 80) {
    throw new CafeOperationError(
      'invalid-argument',
      'Café name must be between 2 and 80 characters.',
    );
  }

  if (operationId != null) {
    operationId = requireText(operationId, 'Operation ID');
    if (operationId.includes('/') || operationId.length > 1500) {
      throw new CafeOperationError('invalid-argument', 'Operation ID is invalid.');
    }
  }
  const cafeId = operationId == null ? undefined : 'cafe-create-' +
    createHash('sha256').update(JSON.stringify([uid, operationId])).digest('hex');
  const cafeRef = cafeId == null ? db.collection('cafes').doc() : db.collection('cafes').doc(cafeId);
  const ownerRef = membershipRef(db, uid, cafeRef.id);
  const duplicate = await db.runTransaction(async (transaction) => {
    if (operationId != null) {
      const prior = await transaction.get(cafeRef);
      if (prior.exists) {
        await requireActiveMembershipTx({ transaction, db, uid, cafeId: cafeRef.id, roles: ['owner'] });
        const saved = prior.data();
        if (saved.ownerUid !== uid || saved.creationOperationId !== operationId ||
            saved.creationRequestName !== name) {
          throw new CafeOperationError('already-exists', 'Operation ID was already used for another cafe creation.');
        }
        return true;
      }
    }
    transaction.create(cafeRef, {
      cafeId: cafeRef.id,
      name,
      ownerUid: uid,
      ...(operationId == null ? {} : { creationOperationId: operationId, creationRequestName: name }),
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.create(ownerRef, {
      uid,
      cafeId: cafeRef.id,
      role: 'owner',
      status: 'active',
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return false;
  });
  return { cafeId: cafeRef.id, membershipId: ownerRef.id, duplicate };
}

async function grantCafeMembership({
  db,
  callerUid,
  cafeId,
  targetUid,
  role,
}) {
  callerUid = requireText(callerUid, 'Authenticated user ID');
  cafeId = requireText(cafeId, 'Café ID');
  targetUid = requireText(targetUid, 'Target user ID');
  if (targetUid === callerUid) {
    throw new CafeOperationError(
      'invalid-argument',
      'Use the existing membership instead of inviting yourself.',
    );
  }
  if (role !== 'manager' && role !== 'staff') {
    throw new CafeOperationError(
      'invalid-argument',
      'Membership role must be manager or staff.',
    );
  }

  const callerRef = membershipRef(db, callerUid, cafeId);
  const targetRef = membershipRef(db, targetUid, cafeId);
  const cafeRef = db.collection('cafes').doc(cafeId);

  await db.runTransaction(async (transaction) => {
    const [callerSnapshot, targetSnapshot, cafeSnapshot] = await Promise.all([
      transaction.get(callerRef),
      transaction.get(targetRef),
      transaction.get(cafeRef),
    ]);
    const caller = callerSnapshot.data();
    if (!validateMembership(caller, callerUid, cafeId) ||
        !['owner', 'manager'].includes(caller.role)) {
      throw new CafeOperationError(
        'permission-denied',
        'An active café owner or manager is required.',
      );
    }
    if (!cafeSnapshot.exists) {
      throw new CafeOperationError('not-found', 'Café not found.');
    }
    if (caller.role === 'manager' && role !== 'staff') {
      throw new CafeOperationError(
        'permission-denied',
        'Managers can grant staff access only.',
      );
    }

    const previous = targetSnapshot.data();
    if (previous != null && previous.status === 'active') {
      throw new CafeOperationError(
        'already-exists',
        'This user already has active café access.',
      );
    }
    if (caller.role === 'manager' && previous != null && previous.role !== 'staff') {
      throw new CafeOperationError(
        'permission-denied',
        'Managers cannot restore or change a manager membership.',
      );
    }

    await require('./subscription_service').requireCafeSubscriptionTx({transaction,db,cafeId});
    transaction.set(targetRef, {
      uid: targetUid,
      cafeId,
      role,
      status: 'active',
      createdAt: previous?.createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { membershipId: targetRef.id, uid: targetUid, cafeId, role };
}

async function revokeCafeMembership({ db, callerUid, cafeId, targetUid }) {
  callerUid = requireText(callerUid, 'Authenticated user ID');
  cafeId = requireText(cafeId, 'Café ID');
  targetUid = requireText(targetUid, 'Target user ID');
  if (callerUid === targetUid) {
    throw new CafeOperationError(
      'failed-precondition',
      'The current user cannot revoke their own café membership.',
    );
  }

  const callerRef = membershipRef(db, callerUid, cafeId);
  const targetRef = membershipRef(db, targetUid, cafeId);
  const cafeRef = db.collection('cafes').doc(cafeId);

  await db.runTransaction(async (transaction) => {
    const [callerSnapshot, targetSnapshot, cafeSnapshot] = await Promise.all([
      transaction.get(callerRef),
      transaction.get(targetRef),
      transaction.get(cafeRef),
    ]);
    const caller = callerSnapshot.data();
    const target = targetSnapshot.data();
    if (!validateMembership(caller, callerUid, cafeId) ||
        !['owner', 'manager'].includes(caller.role)) {
      throw new CafeOperationError(
        'permission-denied',
        'An active café owner or manager is required.',
      );
    }
    if (!cafeSnapshot.exists) {
      throw new CafeOperationError('not-found', 'Café not found.');
    }
    if (!validateMembership(target, targetUid, cafeId)) {
      throw new CafeOperationError(
        'not-found',
        'An active target membership was not found.',
      );
    }
    if (target.role === 'owner') {
      throw new CafeOperationError(
        'failed-precondition',
        'Transfer café ownership before changing an owner membership.',
      );
    }
    if (caller.role === 'manager' && target.role !== 'staff') {
      throw new CafeOperationError(
        'permission-denied',
        'Managers can revoke staff access only.',
      );
    }

    transaction.update(targetRef, {
      status: 'revoked',
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { uid: targetUid, cafeId, status: 'revoked' };
}

async function listCafeMemberships({ db, callerUid, cafeId, pageToken }) {
  callerUid = requireText(callerUid, 'Authenticated user ID');
  cafeId = requireText(cafeId, 'Café ID');
  if (pageToken != null &&
      (typeof pageToken !== 'string' || pageToken.trim().length === 0 ||
       pageToken.includes('/') || pageToken.length > 1500)) {
    throw new CafeOperationError('invalid-argument', 'Membership page token is invalid.');
  }
  pageToken = pageToken?.trim() ?? null;
  const { caller, snapshot } = await db.runTransaction(async (transaction) => {
    const caller = await requireActiveMembershipTx({
      transaction,
      db,
      uid: callerUid,
      cafeId,
      roles: ['owner', 'manager'],
    });
    let query = db.collection('cafe_members')
      .where('cafeId', '==', cafeId)
      .orderBy(FieldPath.documentId())
      .limit(201);
    if (pageToken != null) query = query.startAfter(pageToken);
    // Keep the role check and privileged membership query on the same
    // Firestore snapshot so a concurrently revoked manager cannot read a page.
    const snapshot = await transaction.get(query);
    return { caller, snapshot };
  });
  const hasMore = snapshot.docs.length > 200;
  const pageDocs = snapshot.docs.slice(0, 200);
  const memberships = pageDocs.map((document) => {
    const data = document.data();
    if (data?.cafeId !== cafeId || typeof data?.uid !== 'string' ||
        data.uid.trim().length === 0 || !VALID_ROLES.has(data?.role) ||
        !['active', 'revoked'].includes(data?.status)) {
      throw new CafeOperationError('internal', 'Café membership data is invalid.');
    }
    if (document.id !== membershipRef(db, data.uid, cafeId).id) {
      throw new CafeOperationError('internal', 'Café membership identity is invalid.');
    }
    return {
      uid: data.uid,
      cafeId,
      role: data.role,
      status: data.status,
    };
  }).sort((left, right) => left.uid < right.uid ? -1 : left.uid > right.uid ? 1 : 0);
  return {
    memberships,
    hasMore,
    nextPageToken: hasMore ? pageDocs[pageDocs.length - 1].id : null,
    callerRole: caller.role,
  };
}

module.exports = {
  CafeOperationError,
  createCafe,
  grantCafeMembership,
  listCafeMemberships,
  membershipRef,
  requireActiveMembershipTx,
  revokeCafeMembership,
  validateMembership,
};
