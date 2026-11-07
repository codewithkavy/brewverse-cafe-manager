const {before,after,test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID,randomBytes}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const service=require('../src/subscription_service');
const {checkout}=require('../src/inventory_service');
let app,db,uid,cafeId,otherId;const run=`admin-${Date.now()}`;
const future=()=>new Date(Date.now()+30*86400000).toISOString();
const operation=()=>randomUUID();
async function reject(promise,code){await assert.rejects(promise,e=>e.code===code);}
before(async()=>{
 assert.equal(process.env.GCLOUD_PROJECT,'brewverse-security-tests');assert(['127.0.0.1:13185','127.0.0.1:14185'].includes(process.env.FIRESTORE_EMULATOR_HOST));assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,process.env.FIRESTORE_EMULATOR_HOST.replace('185','198'));
 app=initializeApp({projectId:'brewverse-security-tests'},run);db=getFirestore(app);uid=run+'-root';cafeId=run+'-cafe';otherId=run+'-other';
 await db.collection('platform_admins').doc(uid).set({active:true,role:'super_admin'});
 for(const id of [cafeId,otherId]){await db.collection('cafes').doc(id).set({cafeId:id,name:id,ownerUid:run+'-owner'});await db.collection('cafe_members').doc(`${run}-owner_${id}`).set({uid:run+'-owner',cafeId:id,role:'owner',status:'active'});}
 await db.collection('stock_items').doc(run+'-product').set({cafeId,category:'finished',stockMode:'direct',name:'Test product',unit:'piece',quantity:10,sellingPrice:80});
});
after(async()=>{if(db)await db.collection('platform_config').doc('subscriptions').delete();if(app)await deleteApp(app);});
test('status expires at server time, bounds grace and prioritizes suspension',()=>{
 const now=new Date('2026-10-22T00:00:00Z');
 assert.equal(service.statusOf(null,now),'pending');assert.equal(service.statusOf({expiresAt:Timestamp.fromDate(new Date('2026-10-23'))},now),'active');
 assert.equal(service.statusOf({expiresAt:Timestamp.fromDate(now),graceDays:0},now),'expired');
 assert.equal(service.statusOf({expiresAt:Timestamp.fromDate(now),graceDays:1},now),'grace');
 assert.equal(service.statusOf({expiresAt:Timestamp.fromDate(now),graceDays:15},now),'expired');
 assert.equal(service.statusOf({expiresAt:Timestamp.fromDate(new Date('2026-10-23')),suspended:true},now),'suspended');
});
test('cafe ownership, arbitrary UID and inactive admin do not authorize platform access',async()=>{
 await reject(service.session({db,uid:run+'-owner'}),'permission-denied');
 await db.collection('platform_admins').doc(run+'-inactive').set({active:false,role:'super_admin'});
 await reject(service.overview({db,uid:run+'-inactive'}),'permission-denied');
 assert.equal((await service.session({db,uid})).role,'super_admin');
});
test('policy updates are audited, revision protected and idempotent',async()=>{
 const data={db,uid,monthlyPriceMinor:99900,graceDays:2,enforcementEnabled:true,expectedRevision:0,reason:'Test policy',operationId:operation()};
 await service.savePolicy(data);assert.equal((await service.savePolicy(data)).duplicate,true);
 await reject(service.savePolicy({...data,operationId:operation()}),'aborted');
 await reject(service.savePolicy({...data,graceDays:15,operationId:operation()}),'invalid-argument');
 assert.equal((await db.collection('platform_audit').doc(data.operationId).get()).data().actorUid,uid);
});
test('unmanaged cafes are blocked with enforcement enabled, no billing side effects',async()=>{
 const args={db,callerUid:run+'-owner',cafeId,checkoutId:run+'-denied',cart:{[run+'-product']:1},orderType:'dineIn'};
 await reject(checkout(args),'failed-precondition');assert.equal((await db.collection('bills').doc(args.checkoutId).get()).exists,false);
 assert.equal((await db.collection('stock_items').doc(run+'-product').get()).data().quantity,10);
});
test('activation, concurrent renewal, suspension and resume use original cafe without data deletion',async()=>{
 await service.updateSubscription({db,uid,cafeId,action:'activate',expiresAt:future(),expectedRevision:0,reason:'Verified bank transfer',operationId:operation()});
 const renew={db,uid,cafeId,action:'extend',expiresAt:new Date(Date.now()+60*86400000).toISOString(),expectedRevision:1,reason:'Renewal'};
 const results=await Promise.allSettled([service.updateSubscription({...renew,operationId:operation()}),service.updateSubscription({...renew,operationId:operation()})]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'aborted');
 await service.updateSubscription({db,uid,cafeId,action:'suspend',expectedRevision:2,reason:'Review',operationId:operation()});
 const args={db,callerUid:run+'-owner',cafeId,checkoutId:run+'-suspended',cart:{[run+'-product']:1},orderType:'dineIn'};
 await reject(checkout(args),'failed-precondition');
 await service.updateSubscription({db,uid,cafeId,action:'resume',expectedRevision:3,reason:'Reviewed',operationId:operation()});
 await checkout({...args,checkoutId:run+'-ok'});
 assert.equal((await db.collection('stock_items').doc(run+'-product').get()).data().quantity,9);
 assert.equal((await db.collection('cafes').doc(otherId).get()).data().name,otherId);
});
test('expiration blocks new checkout, but a matching saved checkout retry remains read-only',async()=>{
 await db.collection('cafe_subscriptions').doc(cafeId).update({expiresAt:Timestamp.fromMillis(Date.now()-4*86400000)});
 const args={db,callerUid:run+'-owner',cafeId,cart:{[run+'-product']:1},orderType:'dineIn'};
 await reject(checkout({...args,checkoutId:run+'-expired'}),'failed-precondition');
 assert.equal((await checkout({...args,checkoutId:run+'-ok'})).duplicate,true);
 await reject(service.updateSubscription({db,uid,cafeId,action:'resume',expectedRevision:4,reason:'Invalid resume',operationId:operation()}),'failed-precondition');
 await service.updateSubscription({db,uid,cafeId,action:'activate',expiresAt:future(),expectedRevision:4,reason:'Renewed',operationId:operation()});
 await checkout({...args,checkoutId:run+'-renewed'});
});
test('UPI records require explicit human confirmation and globally deduplicate references',async()=>{
 const data={db,uid,cafeId,amountMinor:99900,paidAt:new Date().toISOString(),reference:run.toUpperCase()+'-UPI',note:'Checked the receiving bank account',confirmedVerified:true};
 await reject(service.recordPayment({...data,confirmedVerified:false}),'failed-precondition');
 const results=await Promise.allSettled([service.recordPayment(data),service.recordPayment({...data,cafeId:otherId})]);
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'already-exists');
 await reject(service.recordPayment({...data,reference:data.reference.toLowerCase()}),'already-exists');
 assert.equal((await service.overview({db,uid})).counts.revenueMinor,99900);
});
test('details and paginated list are platform-only and contain payment and audit history',async()=>{
 const details=await service.details({db,uid,cafeId});assert(details.audits.length>=4);assert.equal(details.status,'active');
 await reject(service.details({db,uid:run+'-owner',cafeId}),'permission-denied');
 assert((await service.listCafes({db,uid})).cafes.some(c=>c.id===cafeId));
 await db.collection('platform_admins').doc(uid).update({active:false});await reject(service.session({db,uid}),'permission-denied');
 await db.collection('platform_admins').doc(uid).update({active:true});
});
test('real callable uses the authenticated UID and rejects client role or UID spoofing',async()=>{
 const auth=getAuth(app),password=randomBytes(24).toString('base64url');
 const user=await auth.createUser({email:`${run}@example.test`,password});
 const r=await fetch('http://'+process.env.FIREBASE_AUTH_EMULATOR_HOST+'/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:user.email,password,returnSecureToken:true})});const token=(await r.json()).idToken;assert(token);
 const call=()=>fetch(process.env.BREWVERSE_FUNCTIONS_TEST_URL+'/brewverse-security-tests/us-central1/adminOverview',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:JSON.stringify({data:{uid,role:'super_admin'}})});
 assert.equal((await call()).status,403);
 await db.collection('platform_admins').doc(user.uid).set({active:true,role:'super_admin'});
 assert.equal((await call()).status,200);
 await db.collection('platform_admins').doc(user.uid).update({active:false});assert.equal((await call()).status,403);
});

