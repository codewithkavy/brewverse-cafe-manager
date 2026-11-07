// Synthetic fixtures only. Never accepts or targets a production project.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {randomBytes,randomUUID}=require('node:crypto');
const {createRequire}=require('node:module');
const localRequire=createRequire(path.join(__dirname,'../functions/package.json'));
const {initializeApp,deleteApp}=localRequire('firebase-admin/app');
const {getAuth}=localRequire('firebase-admin/auth');
const {getFirestore,Timestamp}=localRequire('firebase-admin/firestore');
const service=require('../functions/src/subscription_service');
(async()=>{
 assert.equal(process.env.GCLOUD_PROJECT,'brewverse-security-tests');
 for(const [key,value]of Object.entries({FIRESTORE_EMULATOR_HOST:'127.0.0.1:13185',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:13198',FIREBASE_STORAGE_EMULATOR_HOST:'127.0.0.1:13199'}))assert.equal(process.env[key],value);
 const hub=await(await fetch('http://127.0.0.1:13120/emulators')).json();for(const [key,port]of Object.entries({auth:13198,firestore:13185,functions:13101,storage:13199}))assert.equal(hub[key].port,port);
 const app=initializeApp({projectId:'brewverse-security-tests'},'admin-demo-seed');const auth=getAuth(app),db=getFirestore(app);
 const email=`admin-${randomUUID().slice(0,8)}@brewverse.local.test`,password=randomBytes(24).toString('base64url');
 const user=await auth.createUser({email,password});
 await db.collection('platform_admins').doc(user.uid).create({role:'super_admin',active:true,fixture:true});
 const owner=await auth.createUser({email:`owner-${randomUUID().slice(0,8)}@brewverse.local.test`,password:randomBytes(24).toString('base64url')});
 const config=await db.collection('platform_config').doc('subscriptions').get();
 await service.savePolicy({db,uid:user.uid,monthlyPriceMinor:99900,graceDays:2,enforcementEnabled:true,expectedRevision:config.data()?.revision??0,reason:'Synthetic dashboard fixture policy',operationId:randomUUID()});
 for(const [key,name]of Object.entries({active:'Willow Coffee',expired:'Amber House',suspended:'Cedar & Bean',pending:'New Cafe Application'})){
  const cafeId='demo-'+key;
  assert(!(await db.collection('cafes').doc(cafeId).get()).exists,'Demo already exists; refusing overwrite');
  await db.collection('cafes').doc(cafeId).create({cafeId,name,ownerUid:owner.uid,createdAt:Timestamp.now(),fixture:true});
  await db.collection('cafe_members').doc(`${owner.uid}_${cafeId}`).create({uid:owner.uid,cafeId,role:'owner',status:'active'});
  if(key!=='pending')await db.collection('cafe_subscriptions').doc(cafeId).create({revision:1,expiresAt:Timestamp.fromMillis(Date.now()+(key==='expired'?-7:30)*86400000),graceDays:2,suspended:key==='suspended',fixture:true});
 }
 await service.recordPayment({db,uid:user.uid,cafeId:'demo-active',amountMinor:99900,paidAt:new Date().toISOString(),reference:'EMULATOR-'+randomUUID(),confirmedVerified:true,note:'Synthetic fixture; no real transfer or production data.'});
 const dir=path.join(__dirname,'../.firebase/admin-development');fs.mkdirSync(dir,{recursive:true});
 const file=path.join(dir,`dashboard-demo-login-${randomUUID()}.json`);
 fs.writeFileSync(file,JSON.stringify({email,password,project:'brewverse-security-tests',authPort:13198,web:'http://127.0.0.1:8767'},null,2),{flag:'wx'});
 fs.writeFileSync(path.join(dir,'dashboard-demo-login-path.txt'),file);
 console.log(`Synthetic demo created. Random local credentials saved privately at ${file}; credentials were not printed.`);
 await deleteApp(app);
})().catch(e=>{console.error(e.message);process.exitCode=1;});
