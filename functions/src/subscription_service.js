const { createHash } = require('node:crypto');
const { Timestamp, FieldValue, FieldPath } = require('firebase-admin/firestore');
const { CafeOperationError } = require('./membership_service');

const policyRef = db => db.collection('platform_config').doc('subscriptions');
const subscriptionRef = (db, id) => db.collection('cafe_subscriptions').doc(id);
function fail(code, message) { throw new CafeOperationError(code, message); }
function text(value, label, max = 200) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) fail('invalid-argument', `${label} is required (maximum ${max} characters).`);
  return value.trim();
}
function id(value) { value = text(value, 'Document ID', 128); if (value.includes('/')) fail('invalid-argument', 'Invalid document ID.'); return value; }
function integer(value, min, max, label) { if (!Number.isSafeInteger(value) || value < min || value > max) fail('invalid-argument', `${label} must be from ${min} to ${max}.`); return value; }
function instant(value) { const date = new Date(value); if (typeof value !== 'string' || !Number.isFinite(date.getTime())) fail('invalid-argument', 'A valid ISO date is required.'); return date; }
function millis(value) { return value?.toMillis?.() ?? (typeof value === 'string' ? Date.parse(value) : NaN); }
function statusOf(subscription, now = new Date()) {
  if (!subscription) return 'pending';
  if (subscription.suspended === true) return 'suspended';
  if (subscription.licenseType === 'permanent') return 'active';
  const expires = millis(subscription.expiresAt);
  if (!Number.isFinite(expires)) return 'pending';
  if (now.getTime() < expires) return 'active';
  const grace = Number.isInteger(subscription.graceDays) && subscription.graceDays >= 0 && subscription.graceDays <= 14 ? subscription.graceDays : 0;
  return now.getTime() < expires + grace * 86400000 ? 'grace' : 'expired';
}
async function requireAdminTx(transaction, db, uid) {
  const admin = await transaction.get(db.collection('platform_admins').doc(id(uid)));
  if (admin.data()?.active !== true || admin.data()?.role !== 'super_admin') fail('permission-denied', 'Super Admin authorization is required.');
}
async function requireCafeSubscriptionTx({transaction, db, cafeId, now = new Date()}) {
  const [sub, config] = await Promise.all([transaction.get(subscriptionRef(db, cafeId)), transaction.get(policyRef(db))]);
  // Only local development permits unchanged, unmanaged legacy fixtures.
  // Production defaults fail-closed; no client can set this rollout policy.
  const local = process.env.FUNCTIONS_EMULATOR === 'true' || !!process.env.FIRESTORE_EMULATOR_HOST;
  const enforced = !local || config.data()?.enforcementEnabled === true;
  if (!sub.exists && !enforced) return;
  if (!['active', 'grace'].includes(statusOf(sub.data(), now))) fail('failed-precondition', 'Cafe subscription is pending, expired or suspended. Existing records remain available; contact your administrator.');
}
function serialize(value) {
  if (value?.toDate) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, serialize(item)]));
  return value;
}
async function session({db, uid}) {
  return db.runTransaction(async tx => {
    await requireAdminTx(tx, db, uid);
    tx.create(db.collection('platform_audit').doc(),{actorUid:uid,action:'admin_sign_in',createdAt:FieldValue.serverTimestamp()});
    return {uid, role:'super_admin'};
  });
}
async function overview({db, uid}) {
  return db.runTransaction(async tx => {
    await requireAdminTx(tx, db, uid);
    const [cafes, subscriptions, payments, config] = await Promise.all([
      tx.get(db.collection('cafes').limit(5001)), tx.get(db.collection('cafe_subscriptions').limit(5001)),
      tx.get(db.collection('subscription_payments').limit(10001)), tx.get(policyRef(db)),
    ]);
    if (cafes.size > 5000 || subscriptions.size > 5000 || payments.size > 10000) fail('resource-exhausted', 'Overview needs aggregate scaling before showing more records.');
    const counts = {total:cafes.size, active:0, grace:0, expired:0, suspended:0, pending:0, revenueMinor:0};
    const subs = new Map(subscriptions.docs.map(d => [d.id, d.data()]));
    for (const cafe of cafes.docs) counts[statusOf(subs.get(cafe.id))]++;
    for (const payment of payments.docs) if (payment.data().verificationStatus === 'verified') counts.revenueMinor += payment.data().amountMinor;
    tx.create(db.collection('platform_audit').doc(),{actorUid:uid,action:'view_overview',createdAt:FieldValue.serverTimestamp()});
    return {counts, settings:serialize(config.data() ?? {monthlyPriceMinor:99900, graceDays:0, enforcementEnabled:!(process.env.FUNCTIONS_EMULATOR==='true'||process.env.FIRESTORE_EMULATOR_HOST), revision:0}), serverTime:new Date().toISOString()};
  });
}
async function listCafes({db, uid, cursor}) {
  return db.runTransaction(async tx => {
    await requireAdminTx(tx, db, uid);
    let query = db.collection('cafes').orderBy(FieldPath.documentId()).limit(51);
    if (cursor) query = query.startAfter(id(cursor));
    const page = await tx.get(query);
    const docs = page.docs.slice(0, 50);
    const subscriptions = await Promise.all(docs.map(doc => tx.get(subscriptionRef(db, doc.id))));
    tx.create(db.collection('platform_audit').doc(),{actorUid:uid,action:'list_cafes',createdAt:FieldValue.serverTimestamp()});
    return {cafes:docs.map((doc, index) => ({id:doc.id, name:doc.data().name ?? doc.id, ownerUid:doc.data().ownerUid ?? '', subscription:serialize(subscriptions[index].data() ?? {revision:0}), status:statusOf(subscriptions[index].data())})), nextCursor:page.size > 50 ? docs.at(-1).id : null};
  });
}
async function details({db, uid, cafeId}) {
  cafeId = id(cafeId);
  return db.runTransaction(async tx => {
    await requireAdminTx(tx, db, uid);
    const [cafe, sub, payments, audits] = await Promise.all([
      tx.get(db.collection('cafes').doc(cafeId)), tx.get(subscriptionRef(db,cafeId)),
      tx.get(db.collection('subscription_payments').where('cafeId','==',cafeId).limit(501)),
      tx.get(db.collection('platform_audit').where('cafeId','==',cafeId).limit(501)),
    ]);
    if (!cafe.exists) fail('not-found','Cafe not found.');
    tx.create(db.collection('platform_audit').doc(),{actorUid:uid,cafeId,action:'view_cafe',createdAt:FieldValue.serverTimestamp()});
    return {cafe:serialize(cafe.data()), subscription:serialize(sub.data() ?? {revision:0}), status:statusOf(sub.data()),
      payments:payments.docs.slice(0,500).map(d=>({id:d.id,...serialize(d.data())})), audits:audits.docs.slice(0,500).map(d=>({id:d.id,...serialize(d.data())})),
      historyTruncated:payments.size>500||audits.size>500};
  });
}
async function updateSubscription({db, uid, cafeId, action, expiresAt, expectedRevision, reason, operationId}) {
  cafeId=id(cafeId); operationId=id(operationId); reason=text(reason,'Reason');
  if (!['activate','activatePermanent','extend','suspend','resume'].includes(action)) fail('invalid-argument','Unknown subscription action.');
  integer(expectedRevision,0,Number.MAX_SAFE_INTEGER,'Revision');
  const requested = ['activate','extend'].includes(action) ? instant(expiresAt) : null;
  if (requested && (requested <= new Date() || requested.getTime() > Date.now()+3660*86400000)) fail('invalid-argument','Expiry must be in the future and within ten years.');
  return db.runTransaction(async tx => {
    await requireAdminTx(tx,db,uid);
    const ref=subscriptionRef(db,cafeId), audit=db.collection('platform_audit').doc(operationId);
    const [cafe, previous, config, prior] = await Promise.all([tx.get(db.collection('cafes').doc(cafeId)),tx.get(ref),tx.get(policyRef(db)),tx.get(audit)]);
    if (!cafe.exists) fail('not-found','Cafe not found.');
    const fingerprint=JSON.stringify({uid,cafeId,action,expiresAt:requested?.toISOString()??null,expectedRevision,reason});
    if(prior.exists) {if(prior.data().fingerprint!==fingerprint)fail('already-exists','Operation ID was reused.');return {duplicate:true};}
    const before=previous.data() ?? {revision:0};
    if ((before.revision??0)!==expectedRevision) fail('aborted','Subscription changed. Refresh before saving.');
    if (before.licenseType === 'permanent' && ['activate','extend'].includes(action)) fail('failed-precondition','Permanent access cannot be replaced with a timed subscription.');
    if(action==='activate' && Number.isFinite(millis(before.expiresAt)) && requested.getTime()<millis(before.expiresAt)) fail('invalid-argument','Renewal cannot shorten the saved expiry.');
    if(action==='extend' && !Number.isFinite(millis(before.expiresAt))) fail('failed-precondition','Activate the subscription before extending it.');
    if(action==='extend' && requested.getTime()<=millis(before.expiresAt)) fail('invalid-argument','Extension must move the expiry forward.');
    if(action==='resume' && !['active','grace'].includes(statusOf({...before,suspended:false}))) fail('failed-precondition','Renew the expiry before restoring this cafe.');
    const after={...before,revision:expectedRevision+1,updatedAt:FieldValue.serverTimestamp(),updatedBy:uid};
    if(action==='activatePermanent'){after.licenseType='permanent';after.suspended=false;}
    else if(requested){after.expiresAt=Timestamp.fromDate(requested);after.graceDays=config.data()?.graceDays??0;after.suspended=false;}
    else after.suspended=action==='suspend';
    tx.set(ref,after);
    tx.create(audit,{actorUid:uid,cafeId,action,reason,fingerprint,before,after,createdAt:FieldValue.serverTimestamp()});
    return {revision:after.revision};
  });
}
async function savePolicy({db,uid,monthlyPriceMinor,graceDays,enforcementEnabled,expectedRevision,reason,operationId}) {
  integer(monthlyPriceMinor,1,100000000,'Monthly price (paise)');integer(graceDays,0,14,'Grace days');integer(expectedRevision,0,Number.MAX_SAFE_INTEGER,'Revision');
  if(typeof enforcementEnabled!=='boolean')fail('invalid-argument','Enforcement must be a boolean.');
  reason=text(reason,'Reason');operationId=id(operationId);
  return db.runTransaction(async tx=>{
    await requireAdminTx(tx,db,uid);const ref=policyRef(db),audit=db.collection('platform_audit').doc(operationId);
    const [prior,logged]=await Promise.all([tx.get(ref),tx.get(audit)]);
    const fingerprint=JSON.stringify({uid,monthlyPriceMinor,graceDays,enforcementEnabled,expectedRevision,reason});
    if(logged.exists){if(logged.data().fingerprint!==fingerprint)fail('already-exists','Operation ID was reused.');return {duplicate:true};}
    const before=prior.data()??{revision:0};if((before.revision??0)!==expectedRevision)fail('aborted','Policy changed. Refresh before saving.');
    const after={monthlyPriceMinor,graceDays,enforcementEnabled,revision:expectedRevision+1,updatedAt:FieldValue.serverTimestamp(),updatedBy:uid};
    tx.set(ref,after);tx.create(audit,{actorUid:uid,action:'policy',reason,fingerprint,before,after,createdAt:FieldValue.serverTimestamp()});return {revision:after.revision};
  });
}
async function recordPayment({db,uid,cafeId,amountMinor,paidAt,reference,confirmedVerified,note}) {
  cafeId=id(cafeId);integer(amountMinor,1,100000000,'Payment amount (paise)');
  reference=text(reference,'UPI reference',100).toUpperCase();
  if(!/^[A-Z0-9][A-Z0-9-]{5,99}$/.test(reference))fail('invalid-argument','Use the complete UPI reference without spaces.');
  const date=instant(paidAt);if(date.getTime()>Date.now()+300000)fail('invalid-argument','Payment date cannot be in the future.');
  if(confirmedVerified!==true)fail('failed-precondition','Explicitly confirm that you verified the payment outside BrewVerse.');
  note=text(note,'Verification note',500);
  const paymentId=createHash('sha256').update(reference).digest('hex');
  return db.runTransaction(async tx=>{
    await requireAdminTx(tx,db,uid);const ref=db.collection('subscription_payments').doc(paymentId);
    const [cafe,prior]=await Promise.all([tx.get(db.collection('cafes').doc(cafeId)),tx.get(ref)]);
    if(!cafe.exists)fail('not-found','Cafe not found.');
    if(prior.exists)fail('already-exists','This UPI reference has already been recorded.');
    const data={cafeId,amountMinor,paidAt:Timestamp.fromDate(date),reference,verificationStatus:'verified',verifiedBy:uid,verificationNote:note,recordedAt:FieldValue.serverTimestamp()};
    tx.create(ref,data);tx.create(db.collection('platform_audit').doc(),{actorUid:uid,cafeId,action:'record_verified_payment',paymentId,amountMinor,reason:note,createdAt:FieldValue.serverTimestamp()});
    return {paymentId};
  });
}
module.exports={statusOf,requireCafeSubscriptionTx,session,overview,listCafes,details,updateSubscription,savePolicy,recordPayment};
