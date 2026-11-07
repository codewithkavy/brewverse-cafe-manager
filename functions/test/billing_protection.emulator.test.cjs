const assert = require('node:assert/strict');
const { test } = require('node:test');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

test('isolated callable billing retries, races, authorization and tenant boundaries', async (t) => {
  assert.equal(process.env.GCLOUD_PROJECT, 'brewverse-security-tests');
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:13185');
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:13198');
  assert.equal(process.env.BREWVERSE_FUNCTIONS_TEST_URL, 'http://127.0.0.1:13101');
  const run = `billing-protection-${Date.now()}`;
  const app = initializeApp({projectId:'brewverse-security-tests'}, run);
  const db = getFirestore(app);
  async function user(suffix) {
    const r = await fetch('http://127.0.0.1:13198/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify({email:`${run}-${suffix}@example.test`,password:'local-only-password',returnSecureToken:true}),
    });
    assert(r.ok); return r.json();
  }
  const owner = await user('owner');
  async function call(name, data, token = owner.idToken) {
    const r = await fetch(`http://127.0.0.1:13101/brewverse-security-tests/us-central1/${name}`, {
      method:'POST', headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},
      body:JSON.stringify({data}), signal:AbortSignal.timeout(60000),
    });
    return r.json();
  }
  async function ok(name,data,token) {const r=await call(name,data,token);assert(!r.error,JSON.stringify(r));return r.result;}
  try {
    const {cafeId}=await ok('createCafe',{name:run});
    const {stockItemId}=await ok('createStockItem',{cafeId,item:{name:'Disposable product',category:'finished',stockMode:'direct',unit:'piece',quantity:100,minimumQuantity:0,purchasePricePerUnit:0,sellingPrice:200}});
    const cafe=db.collection('cafes').doc(cafeId);
    async function state() {
      const result={};
      for(const collection of ['bills','stock_items','stock_movements']) {
        const snap=await db.collection(collection).where('cafeId','==',cafeId).get();
        result[collection]=Object.fromEntries(snap.docs.map(d=>[d.id,d.data()]));
      }
      for(const collection of ['billAdjustments','loyaltyCustomers','loyaltyTransactions']) {
        const snap=await cafe.collection(collection).get();
        result[collection]=Object.fromEntries(snap.docs.map(d=>[d.id,d.data()]));
      }
      return result;
    }
    let sequence=0;
    async function sale() {
      const billId=`${run}-sale-${sequence++}`;
      const r=await ok('checkout',{cafeId,checkoutId:billId,cart:{[stockItemId]:1},orderType:'dineIn',customerPhone:'+919876543210'});
      assert(r.pointsEarned>0,'Exercise nonzero loyalty reversal');return billId;
    }
    for(const mode of ['refund','void']) {
      await t.test(`${mode}: same-key concurrent submissions and lost-response retry apply once`,async()=>{
        const billId=await sale(),before=await state();
        const data={cafeId,billId,adjustmentId:`${run}-${mode}-same`,amountMinor:20000,reason:'Disposable retry test'};
        const results=await Promise.all(Array.from({length:4},()=>call(`${mode}Bill`,data)));
        results.forEach(r=>assert(!r.error,JSON.stringify(r)));
        assert.equal(results.filter(r=>r.result.duplicate===false).length,1);
        assert.equal(results.filter(r=>r.result.duplicate===true).length,3);
        const after=await state();
        // Simulate a committed response lost on the network: resend identical request.
        assert.equal((await ok(`${mode}Bill`,data)).duplicate,true);
        assert.deepEqual(await state(),after);
        const audits=Object.values(after.billAdjustments).filter(a=>a.billId===billId);
        assert.equal(audits.length,1);assert.equal(audits[0].refundMinor,20000);
        assert(audits[0].pointsReversed>0);assert.equal(audits[0].mode,mode);
        assert.equal(after.bills[billId].status,mode==='void'?'void':'refunded');
        assert.deepEqual(after.stock_items,before.stock_items);
        assert.deepEqual(after.stock_movements,before.stock_movements);
        for(const endpoint of ['refundBill','voidBill']) {
          const r=await call(endpoint,{...data,adjustmentId:`${run}-${sequence++}-new`});
          assert.equal(r.error?.status,'FAILED_PRECONDITION');
        }
        const conflict=await call(mode==='void'?'refundBill':'voidBill',data);
        assert.equal(conflict.error?.status,'ALREADY_EXISTS');
        if(mode==='refund')assert.equal((await call('refundBill',{...data,amountMinor:1})).error?.status,'ALREADY_EXISTS');
        assert.deepEqual(await state(),after);
      });
      await t.test(`${mode}: different-key races cannot adjust a full bill twice`,async()=>{
        const billId=await sale(),before=await state();
        const results=await Promise.all([0,1].map(n=>call(`${mode}Bill`,{cafeId,billId,adjustmentId:`${run}-${mode}-race-${n}`,amountMinor:20000,reason:'Disposable race'})));
        assert.equal(results.filter(r=>r.result).length,1);
        assert.equal(results.filter(r=>r.error?.status==='FAILED_PRECONDITION').length,1);
        const after=await state();assert.equal(Object.values(after.billAdjustments).filter(a=>a.billId===billId).length,1);
        assert.deepEqual(after.stock_items,before.stock_items);assert.deepEqual(after.stock_movements,before.stock_movements);
        assert.equal(Object.keys(after.loyaltyTransactions).length,Object.keys(before.loyaltyTransactions).length+1);
      });
    }
    await t.test('refund versus void race serializes on the bill',async()=>{
      const billId=await sale();const results=await Promise.all(['refund','void'].map(mode=>call(`${mode}Bill`,{cafeId,billId,adjustmentId:`${run}-mixed-${mode}`,amountMinor:20000,reason:'Mixed race'})));
      assert.equal(results.filter(r=>r.result).length,1);assert.equal(results.filter(r=>r.error?.status==='FAILED_PRECONDITION').length,1);
      assert.equal(Object.values((await state()).billAdjustments).filter(a=>a.billId===billId).length,1);
    });
    await t.test('active managers can refund and void once; owners can replay permitted adjustments',async()=>{
      const manager=await user('active-manager');
      await ok('grantCafeMembership',{cafeId,email:manager.email,role:'manager'});
      for(const mode of ['refund','void']) {
        const billId=await sale();
        const data={cafeId,billId,adjustmentId:`${run}-manager-${mode}`,amountMinor:20000,reason:'Permitted manager operation'};
        const result=await ok(`${mode}Bill`,data,manager.idToken);
        assert.equal(result.duplicate,false);
        assert.equal(result.status,mode==='void'?'void':'refunded');
        const after=await state();
        assert.equal((await ok(`${mode}Bill`,data,manager.idToken)).duplicate,true);
        assert.equal((await ok(`${mode}Bill`,data)).duplicate,true);
        assert.deepEqual(await state(),after);
        assert.equal(Object.values(after.billAdjustments).filter(a=>a.billId===billId).length,1);
      }
    });
    await t.test('auth, role, revoked membership and cafe isolation reject without writes',async()=>{
      const billId=await sale(),staff=await user('staff'),outsider=await user('outsider');
      await ok('grantCafeMembership',{cafeId,email:staff.email,role:'staff'});
      const {cafeId:otherCafe}=await ok('createCafe',{name:`${run} other`});
      const before=await state();
      for(const endpoint of ['refundBill','voidBill']) {
        const data={cafeId,billId,adjustmentId:`${run}-forbidden-${endpoint}`,amountMinor:20000,reason:'Forbidden'};
        assert.equal((await call(endpoint,data,null)).error?.status,'UNAUTHENTICATED');
        for(const token of [staff.idToken,outsider.idToken])assert.equal((await call(endpoint,data,token)).error?.status,'PERMISSION_DENIED');
        assert.equal((await call(endpoint,{...data,cafeId:otherCafe})).error?.status,'NOT_FOUND');
      }
      const manager=await user('manager');
      await ok('grantCafeMembership',{cafeId,email:manager.email,role:'manager'});
      await ok('revokeCafeMembership',{cafeId,targetUid:manager.localId});
      for(const endpoint of ['refundBill','voidBill'])assert.equal((await call(endpoint,{cafeId,billId,adjustmentId:`${run}-revoked-${endpoint}`,amountMinor:20000,reason:'Revoked'},manager.idToken)).error?.status,'PERMISSION_DENIED');
      assert.deepEqual(await state(),before);
    });
  } finally { await deleteApp(app); }
});
