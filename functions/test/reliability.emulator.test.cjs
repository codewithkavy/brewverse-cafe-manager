const {before,after,test}=require('node:test');
const assert=require('node:assert/strict');
const {createRequire}=require('node:module');
const client=createRequire(require('node:path').resolve(__dirname,'../../security-tests/package.json'));
const {initializeApp:clientApp,deleteApp:deleteClient}=client('firebase/app');
const {getAuth:clientAuth,connectAuthEmulator,signInWithEmailAndPassword,sendPasswordResetEmail,confirmPasswordReset,signOut}=client('firebase/auth');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {getAuth}=require('firebase-admin/auth');
const {createCafe,grantCafeMembership,listCafeMemberships}=require('../src/membership_service');
const {checkout,saveRecipe}=require('../src/inventory_service');
const {saveLoyaltySettings,DEFAULT_LOYALTY_SETTINGS}=require('../src/loyalty_service');
const project='brewverse-security-tests',run=`reliability-${Date.now()}`;
let app,db,auth,user,owner,cafeId,productId;
async function rest(path,body){const r=await fetch(`http://127.0.0.1:14198/${path}`,{method:body?'POST':'GET',headers:{'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});const data=await r.json();assert(r.ok,JSON.stringify(data));return data;}
const deny=(p,code)=>assert.rejects(p,e=>e.code===code);
before(async()=>{
 assert.equal(process.env.GCLOUD_PROJECT,project);
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:14185');
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,'127.0.0.1:14198');
 assert.equal(process.env.FIREBASE_STORAGE_EMULATOR_HOST,'127.0.0.1:14199');
 app=initializeApp({projectId:project},run);db=getFirestore(app);
 const c=clientApp({projectId:project,apiKey:'synthetic-only'},run);auth=clientAuth(c);connectAuthEmulator(auth,'http://127.0.0.1:14198',{disableWarnings:true});
 user=await getAuth(app).createUser({email:`${run}@example.test`,password:'original-password'});owner=user.uid;
 ({cafeId}=await createCafe({db,uid:owner,name:'Synthetic Reliability Cafe'}));
 productId=run+'-water';await db.collection('stock_items').doc(productId).set({cafeId,name:'Water',category:'finished',stockMode:'direct',unit:'piece',quantity:20,minimumQuantity:0,purchasePricePerUnit:10,sellingPrice:80});
});
after(async()=>{if(auth)await deleteClient(auth.app);if(app)await deleteApp(app);});
test('synthetic email/password, Firebase reset code, old-password rejection, sign-out',async()=>{
 await signInWithEmailAndPassword(auth,user.email,'original-password');assert.equal(auth.currentUser.uid,owner);
 await sendPasswordResetEmail(auth,user.email);
 const codes=await rest(`emulator/v1/projects/${project}/oobCodes`);
 const code=codes.oobCodes.find(c=>c.email===user.email&&c.requestType==='PASSWORD_RESET');assert(code);
 await confirmPasswordReset(auth,code.oobCode,'new-synthetic-password');await signOut(auth);assert.equal(auth.currentUser,null);
 await assert.rejects(signInWithEmailAndPassword(auth,user.email,'original-password'));
 await signInWithEmailAndPassword(auth,user.email,'new-synthetic-password');assert.equal(auth.currentUser.uid,owner);await signOut(auth);
});
test('synthetic phone verification rejects incorrect code and accepts emulator OTP',async()=>{
 const session=await rest('identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=synthetic-only',{phoneNumber:'+16505550137'});
 const codes=await rest(`emulator/v1/projects/${project}/verificationCodes`);const code=codes.verificationCodes.find(c=>c.sessionInfo===session.sessionInfo);assert(code);
 await assert.rejects(rest('identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=synthetic-only',{sessionInfo:session.sessionInfo,code:code.code==='000000'?'111111':'000000'}));
 const signedIn=await rest('identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=synthetic-only',{sessionInfo:session.sessionInfo,code:code.code});
 assert.equal(signedIn.phoneNumber,'+16505550137');assert(signedIn.idToken);
 assert.equal((await getAuth(app).getUser(signedIn.localId)).phoneNumber,'+16505550137');
});
test('subscription states gate checkout, membership grants and loyalty policy; preserve historical retry',async()=>{
 const args={db,callerUid:owner,cafeId,checkoutId:run+'-committed',cart:{[productId]:1},orderType:'dineIn'};
 const ref=db.collection('cafe_subscriptions').doc(cafeId);
 await ref.set({expiresAt:Timestamp.fromMillis(Date.now()+86400000),graceDays:0,suspended:false});await checkout(args);
 const before=(await db.collection('bills').doc(args.checkoutId).get()).data();
 for(const [name,state] of [['expired',{expiresAt:Timestamp.fromMillis(Date.now()-3*86400000),graceDays:1,suspended:false}],['suspended',{expiresAt:Timestamp.fromMillis(Date.now()+86400000),graceDays:0,suspended:true}]]) {
   await ref.set(state);
   await deny(checkout({...args,checkoutId:run+'-'+name}),'failed-precondition');
   await deny(grantCafeMembership({db,callerUid:owner,cafeId,targetUid:run+'-'+name,role:'staff'}),'failed-precondition');
   // Use the exact saved policy shape, not a client supplied role or status.
   await deny(saveLoyaltySettings({db,callerUid:owner,cafeId,settings:DEFAULT_LOYALTY_SETTINGS}),'failed-precondition');
   assert.equal((await checkout(args)).duplicate,true);
   assert.deepEqual((await db.collection('bills').doc(args.checkoutId).get()).data(),before);
   assert.equal((await db.collection('stock_items').doc(productId).get()).data().quantity,19);
 }
 await ref.set({expiresAt:Timestamp.fromMillis(Date.now()-86400000),graceDays:2,suspended:false});
 await checkout({...args,checkoutId:run+'-grace'});assert.equal((await db.collection('stock_items').doc(productId).get()).data().quantity,18);
});
test('pending offline request submitted after expiry is rejected with no queued sale',async()=>{
 const args={db,callerUid:owner,cafeId,checkoutId:run+'-offline-unconfirmed',cart:{[productId]:1},orderType:'dineIn'};
 await db.collection('cafe_subscriptions').doc(cafeId).set({expiresAt:Timestamp.fromMillis(Date.now()-1000),graceDays:0,suspended:false});
 await deny(checkout(args),'failed-precondition');assert.equal((await db.collection('bills').doc(args.checkoutId).get()).exists,false);
 assert.equal((await db.collection('stock_items').doc(productId).get()).data().quantity,18);
});
test('two independent owners and staff cannot access or contaminate the other cafe',async()=>{
 const fixtures=[];
 for(const label of ['A','B']) {
   const uid=run+'-owner-'+label,staff=run+'-staff-'+label;
   await getAuth(app).createUser({uid,email:`${uid}@example.test`,password:'synthetic-password'});
   await getAuth(app).createUser({uid:staff,email:`${staff}@example.test`,password:'synthetic-password'});
   const {cafeId:id}=await createCafe({db,uid,name:'Synthetic Cafe '+label});
   await grantCafeMembership({db,callerUid:uid,cafeId:id,targetUid:staff,role:'staff'});
   const ingredient=run+'-beans-'+label,product=run+'-coffee-'+label,bill=run+'-sale-'+label;
   await db.collection('stock_items').doc(ingredient).set({cafeId:id,name:'Beans '+label,category:'ingredient',unit:'g',quantity:100,minimumQuantity:0,purchasePricePerUnit:1,sellingPrice:0});
   await db.collection('stock_items').doc(product).set({cafeId:id,name:'Coffee '+label,category:'finished',unit:'cup',quantity:0,minimumQuantity:0,purchasePricePerUnit:0,sellingPrice:100});
   await saveRecipe({db,callerUid:uid,cafeId:id,productId:product,ingredients:[{stockItemId:ingredient,quantity:2}]});
   await checkout({db,callerUid:staff,cafeId:id,checkoutId:bill,cart:{[product]:1},orderType:'dineIn',customerPhone:'+16505550138'});
   await db.collection('cafe_subscriptions').doc(id).set({expiresAt:Timestamp.fromMillis(Date.now()+86400000),graceDays:0,suspended:false});
   fixtures.push({uid,staff,id,ingredient,product,bill});
 }
 const {getFirestore:clientDb,connectFirestoreEmulator,doc,getDocFromServer,updateDoc}=client('firebase/firestore');
 const {lookupLoyaltyCustomer}=require('../src/loyalty_service');
 for(const [own,foreign] of [[fixtures[0],fixtures[1]],[fixtures[1],fixtures[0]]]) {
   const c=clientApp({projectId:project,apiKey:'synthetic-only'},own.uid);const a=clientAuth(c);connectAuthEmulator(a,'http://127.0.0.1:14198',{disableWarnings:true});
   const d=clientDb(c);connectFirestoreEmulator(d,'127.0.0.1',14185);
   try {
     await signInWithEmailAndPassword(a,`${own.uid}@example.test`,'synthetic-password');
     for(const [collection,id,other] of [['stock_items',own.ingredient,foreign.ingredient],['product_recipes',own.product,foreign.product],['bills',own.bill,foreign.bill]]) {
       assert.equal((await getDocFromServer(doc(d,collection,id))).exists(),true);
       await assert.rejects(getDocFromServer(doc(d,collection,other)),e=>e.code==='permission-denied');
       await assert.rejects(updateDoc(doc(d,collection,other),{cafeId:own.id}),e=>e.code==='permission-denied');
     }
     assert((await listCafeMemberships({db,callerUid:own.uid,cafeId:own.id})).memberships.some(m=>m.uid===own.staff));
     await deny(listCafeMemberships({db,callerUid:own.uid,cafeId:foreign.id}),'permission-denied');
     await assert.rejects(getDocFromServer(doc(d,'cafe_members',foreign.staff+'_'+foreign.id)),e=>e.code==='permission-denied');
     await deny(lookupLoyaltyCustomer({db,callerUid:own.uid,cafeId:foreign.id,phoneNumber:'+16505550138'}),'permission-denied');
     assert.equal((await lookupLoyaltyCustomer({db,callerUid:own.uid,cafeId:own.id,phoneNumber:'+16505550138'})).found,true);
     await deny(checkout({db,callerUid:own.uid,cafeId:foreign.id,checkoutId:run+'-foreign-'+own.uid,cart:{[foreign.product]:1},orderType:'dineIn'}),'permission-denied');
     await deny(saveRecipe({db,callerUid:own.staff,cafeId:own.id,productId:own.product,ingredients:[{stockItemId:own.ingredient,quantity:3}]}),'permission-denied');
     await deny(saveRecipe({db,callerUid:own.uid,cafeId:own.id,productId:own.product,ingredients:[{stockItemId:foreign.ingredient,quantity:3}]}),'failed-precondition');
   } finally {await deleteClient(c);}
 }
 for(const own of fixtures) {
   assert.equal((await db.collection('stock_items').doc(own.ingredient).get()).data().quantity,98);
   assert.equal((await db.collection('bills').where('cafeId','==',own.id).get()).size,1);
 }
});
