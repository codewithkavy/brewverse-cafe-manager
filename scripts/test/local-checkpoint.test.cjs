const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const s=require('../local-emulator-state.cjs');
const c=require('../local-checkpoint.cjs');
const cafe='SnEadZW3hynRmz4Gc0lC',item='tQNQuUPwYjq6WyZ2Vrur';
const n=x=>({integerValue:String(x)}),str=x=>({stringValue:x});
function records(){return {
 ['stock_items/'+item]:{fields:{cafeId:str(cafe),quantity:n(30),photoUrl:str('')}},
 'stock_movements/open':{fields:{cafeId:str(cafe),stockItemId:str(item),type:str('addition'),quantityChange:n(100),quantityAfter:n(100),createdAt:{timestampValue:'2026-10-21T09:00:00Z'}}},
 'stock_movements/sale':{fields:{cafeId:str(cafe),stockItemId:str(item),type:str('sale'),billId:str('bill'),quantityChange:n(-70),quantityAfter:n(30),createdAt:{timestampValue:'2026-10-22T09:00:00Z'}}},
 'bills/bill':{fields:{cafeId:str(cafe),status:str('completed'),items:{arrayValue:{values:[{mapValue:{fields:{productId:str('ZuKk9x0wOFMn1kvP9Kd8')}}}]}}}}
};}
function fixture(){
 const parent=fs.mkdtempSync(path.join(os.tmpdir(),'brewverse-checkpoint-test-'));
 const dir=path.join(parent,'one'),exp=path.join(dir,'export');
 fs.mkdirSync(path.join(exp,'auth_export'),{recursive:true});fs.mkdirSync(path.join(exp,'storage_export'));fs.mkdirSync(path.join(exp,'firestore_export'));
 s.write(path.join(exp,'firebase-export-metadata.json'),{auth:{path:'auth_export'},storage:{path:'storage_export'},firestore:{path:'firestore_export',metadata_file:'firestore_export/all.metadata'}});
 s.write(path.join(exp,'auth_export/accounts.json'),{users:[{localId:'test-user',passwordHash:'fixture',validSince:'1'}]});
 s.write(path.join(exp,'auth_export/config.json'),{signIn:{allowDuplicateEmails:false}});
 s.write(path.join(exp,'storage_export/buckets.json'),{buckets:[]});
 fs.writeFileSync(path.join(exp,'firestore_export/all.metadata'),'fixture native export');
 fs.writeFileSync(path.join(exp,'firestore_export/output-0'),'fixture shard');
 s.write(path.join(dir,'records.json'),records());
 const manifest={version:1,project:s.project,complete:true,exportHashes:s.hashes(exp),recordsSha256:s.hash(fs.readFileSync(path.join(dir,'records.json'))),integrity:s.integrity(records(),s.exportState(exp))};
 s.write(path.join(dir,'manifest.json'),manifest);
 const pointer={version:1,project:s.project,directory:'one',manifestSha256:s.hash(fs.readFileSync(path.join(dir,'manifest.json')))};
 s.write(path.join(parent,'current.json'),pointer);s.write(path.join(parent,'session.json'),{status:'clean',checkpoint:'one'});
 return {parent,dir,exp,pointer};
}
test('validated explicit checkpoint resolves without using directory modification dates',()=>{const f=fixture();fs.mkdirSync(path.join(f.parent,'newer-but-invalid'));assert.equal(c.resolve(true,f.parent).directory,f.dir);});
test('missing pointer never falls back to a nearby export',()=>{const f=fixture();fs.renameSync(path.join(f.parent,'current.json'),path.join(f.parent,'retained-pointer.json'));assert.throws(()=>c.resolve(true,f.parent),/No validated checkpoint/);});
test('running, starting, stale and missing session markers block restart',()=>{const f=fixture();for(const status of ['running','starting']){s.write(path.join(f.parent,'session.json'),{status,checkpoint:'one'});assert.throws(()=>c.resolve(true,f.parent),/not safely checkpointed/);}s.write(path.join(f.parent,'session.json'),{status:'clean',checkpoint:'older'});assert.throws(()=>c.resolve(true,f.parent),/stale/);fs.renameSync(path.join(f.parent,'session.json'),path.join(f.parent,'old-session.json'));assert.throws(()=>c.resolve(true,f.parent),/marker is missing/);});
test('damaged exports, records, manifests and wrong projects are rejected',()=>{for(const kind of ['export','records','manifest','project']){const f=fixture();if(kind==='export')fs.appendFileSync(path.join(f.exp,'auth_export/accounts.json'),' ');if(kind==='records')fs.appendFileSync(path.join(f.dir,'records.json'),' ');if(kind==='manifest')fs.appendFileSync(path.join(f.dir,'manifest.json'),' ');if(kind==='project')f.pointer.project='production-project';assert.throws(()=>c.validate(f.pointer,f.parent));}});
test('checkpoint cannot escape its state root',()=>{const f=fixture();assert.throws(()=>c.validate({...f.pointer,directory:'../outside'},f.parent),/escaped/);});
test('partial exports cannot be promoted',()=>{const f=fixture();const meta=s.read(path.join(f.exp,'firebase-export-metadata.json'));delete meta.storage;s.write(path.join(f.exp,'firebase-export-metadata.json'),meta);assert.throws(()=>s.exportState(f.exp),/Incomplete export/);});
test('ledger detects quantity mismatches and missing completed-bill movements',()=>{const state={storage:{objects:[]}};const r=records();r['stock_items/'+item].fields.quantity=n(86);assert.throws(()=>s.integrity(r,state),/differs from ledger/);r['stock_items/'+item].fields.quantity=n(30);r['stock_movements/sale'].fields.quantityAfter=n(86);assert.throws(()=>s.integrity(r,state),/discontinuity/);r['stock_movements/sale'].fields.quantityAfter=n(30);r['bills/other']=structuredClone(r['bills/bill']);assert.throws(()=>s.integrity(r,state),/Missing movement/);});
test('photo URL requires matching exported object, empty photo stays valid',()=>{const r=records();s.integrity(r,{storage:{objects:[]}});r['stock_items/'+item].fields.photoUrl=str('http://127.0.0.1:9199/v0/b/local/o/missing.jpg?alt=media');assert.throws(()=>s.integrity(r,{storage:{objects:[]}}),/Missing photo object/);});
test('Storage export verification detects missing or corrupted photo bytes',()=>{const f=fixture();fs.mkdirSync(path.join(f.exp,'storage_export/metadata'));fs.mkdirSync(path.join(f.exp,'storage_export/blobs'));s.write(path.join(f.exp,'storage_export/metadata/photo.json'),{bucket:'local',name:'photo.jpg',size:3});assert.throws(()=>s.exportState(f.exp));fs.writeFileSync(path.join(f.exp,'storage_export/blobs/photo'),'xx');assert.throws(()=>s.exportState(f.exp),/size mismatch/);});
test('normal comparison retains Auth timing metadata; restart comparison only normalizes known import fields',()=>{const f=fixture();const a=s.exportState(f.exp);const users=s.read(path.join(f.exp,'auth_export/accounts.json'));users.users[0].validSince='2';s.write(path.join(f.exp,'auth_export/accounts.json'),users);assert.throws(()=>s.same(a,s.exportState(f.exp)));const expected=structuredClone(a);delete expected.auth.users[0].validSince;s.same(expected,s.exportState(f.exp,true));users.users[0].passwordHash='changed';s.write(path.join(f.exp,'auth_export/accounts.json'),users);assert.throws(()=>s.same(expected,s.exportState(f.exp,true)));});
test('network helper rejects nonloopback URLs before issuing a request',async()=>{await assert.rejects(()=>s.api('https://firestore.googleapis.com/'),/Only loopback/);});
