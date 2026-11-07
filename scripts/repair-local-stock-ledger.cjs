const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const s=require('./local-emulator-state.cjs');
const run=fs.readFileSync(path.join(s.root,'.firebase/ledger-recovery/current-path.txt'),'utf8').trim();
const cafe='SnEadZW3hynRmz4Gc0lC', item='tQNQuUPwYjq6WyZ2Vrur';
const ids=['4vKLDgs2KyPm9fAuseZC','Efw8gJSFuIv9GbapPKpa','NcywHJq6tSzHsvV9XTan','yJS92KnBnRd1zMenLEaM'];
const corrections=[
 {id:'ZTi6p7Sze73mxcBt8IRa',before:88,after:32,change:-6,bill:'f7a46b4beffcbd96ddff72b75b16d8d98af930c6'},
 {id:'8lga32I559z8oTMCGu5n',before:86,after:30,change:-2,bill:'d34647e94597eb454d16ea7ec371cdb0060609cb'},
];
async function main(){
 assert(process.argv.includes('--correct-running-balances'),'Explicit authorization flag is required for the two approved running-balance corrections');
 await s.guard();
 assert(!fs.existsSync(path.join(run,'pre-records.json')),'This recovery attempt already captured its baseline. Preserve it; create a fresh full-backup attempt before retrying.');
 const before=await s.snapshot();
 const old=s.read(path.join(s.root,'.firebase/bill-recovery/20261022-162543/restart-records.json'));
 const newer=Object.keys(before).filter(k=>!old[k]||JSON.stringify(s.canonical(before[k].fields))!==JSON.stringify(s.canonical(old[k].fields)));
 const backup=s.exportState(path.join(run,'pre-export'));
 await s.api('http://127.0.0.1:4420/_admin/export',{path:path.join(run,'verified-pre-export'),initiatedBy:'brewverse-local-ledger-recovery'});
 s.same(backup,s.exportState(path.join(run,'verified-pre-export')));
 s.same(before,await s.snapshot());
 s.write(path.join(run,'pre-records.json'),before);
 s.write(path.join(run,'newer-than-old-checkpoint.json'),newer);
 s.write(path.join(run,'pre-export-hashes.json'),s.hashes(path.join(run,'verified-pre-export')));
 const folder=path.join(s.root,'.firebase/bill-history-backup/20261021-165406');
 const a=s.read(path.join(folder,'records-before.json')), b=s.read(path.join(folder,'records-after.json'));
 const missing=ids.map(id=>{const doc=a.stock_movements.find(d=>d.name.endsWith('/'+id));assert(doc,`Missing historical ${id}`);s.same(doc,b.stock_movements.find(d=>d.name===doc.name));assert.equal(doc.fields.cafeId.stringValue,cafe);assert.equal(doc.fields.stockItemId.stringValue,item);assert.equal(doc.fields.type.stringValue,'sale');assert(!before['stock_movements/'+id],`Movement already exists: ${id}`);
  const bill=before['bills/'+doc.fields.billId.stringValue];assert(bill,'Original bill not restored');s.same(bill.fields,a.bills.find(d=>d.name===bill.name).fields);return doc;});
 assert.equal(missing.reduce((sum,d)=>sum+s.number(d.fields.quantityChange),0),-56);
 const recipe=before['product_recipes/ZuKk9x0wOFMn1kvP9Kd8'];
 assert.equal(recipe.fields.ingredients.arrayValue.values.length,1);
 const ingredient=recipe.fields.ingredients.arrayValue.values[0].mapValue.fields;
 assert.equal(ingredient.stockItemId.stringValue,item);assert.equal(s.number(ingredient.quantity),2);
 const stock=before['stock_items/'+item];assert.equal(s.number(stock.fields.quantity),86,'Stock changed; investigate before recovery');
 assert.equal(before['stock_items/ZuKk9x0wOFMn1kvP9Kd8'].fields.photoUrl.stringValue,'','Do not overwrite photo');
 const expected=structuredClone(before);
 for(const doc of missing)expected['stock_movements/'+doc.name.split('/').pop()]=doc;
 expected['stock_items/'+item].fields.quantity={integerValue:'30'};
 for(const correction of corrections){
  const fields=before['stock_movements/'+correction.id]?.fields;
  assert(fields,'Recent stock movement is missing');
  assert.equal(fields.cafeId.stringValue,cafe);assert.equal(fields.stockItemId.stringValue,item);
  assert.equal(fields.billId.stringValue,correction.bill);
  assert.equal(s.number(fields.quantityAfter),correction.before);assert.equal(s.number(fields.quantityChange),correction.change);
  expected['stock_movements/'+correction.id].fields.quantityAfter={integerValue:String(correction.after)};
 }
 const summary=s.integrity(expected,backup);assert.equal(summary.burgerBuns,30);
 // Verify every sale in this ledger matches its saved bill and two-bun recipe.
 const movements=Object.entries(expected).filter(([k,d])=>k.startsWith('stock_movements/')&&d.fields.cafeId?.stringValue===cafe&&d.fields.stockItemId?.stringValue===item);
 const bills=Object.entries(before).filter(([k,d])=>k.startsWith('bills/')&&d.fields.cafeId?.stringValue===cafe);
 assert.equal(bills.length,7);assert.equal(movements.length,8);
 for(const [key,bill]of bills){const lines=bill.fields.items.arrayValue.values;assert.equal(lines.length,1);assert.equal(lines[0].mapValue.fields.productId.stringValue,'ZuKk9x0wOFMn1kvP9Kd8');const moves=movements.filter(([,d])=>d.fields.billId?.stringValue===key.split('/')[1]);assert.equal(moves.length,1);assert.equal(s.number(moves[0][1].fields.quantityChange),-2*s.number(lines[0].mapValue.fields.quantity));}
 s.write(path.join(run,'recovery-plan.json'),{movements:missing,corrections,oldQuantity:86,newQuantity:30,summary});
 console.log(JSON.stringify({stage:'validated-backup-and-plan',newerRecords:newer,ledgerMovements:movements.length,cafeBills:bills.length,newQuantity:30}));
 // Atomic create-only movements, one field update, and optimistic guards on every pre-existing document.
 const changed=new Set(['stock_items/'+item,...corrections.map(c=>'stock_movements/'+c.id)]);
 const writes=Object.entries(before).filter(([k])=>!changed.has(k)).map(([,d])=>({verify:d.name,currentDocument:{updateTime:d.updateTime}}));
 // Firestore's commit limit is 500 writes; relevant ledger/bill/recipe guards fit well below it.
 const guards=writes.filter(w=>w.verify.includes('/stock_movements/')||w.verify.includes('/bills/')||w.verify.includes('/product_recipes/'));
 guards.push({update:{name:stock.name,fields:{quantity:{integerValue:'30'}}},updateMask:{fieldPaths:['quantity']},currentDocument:{updateTime:stock.updateTime}});
 for(const correction of corrections){const doc=before['stock_movements/'+correction.id];guards.push({update:{name:doc.name,fields:{quantityAfter:{integerValue:String(correction.after)}}},updateMask:{fieldPaths:['quantityAfter']},currentDocument:{updateTime:doc.updateTime}});}
 for(const d of missing)guards.push({update:{name:d.name,fields:d.fields},currentDocument:{exists:false}});
 assert(guards.length<500);
 await s.api(s.base+':commit',{writes:guards});
 const after=await s.snapshot();s.same(s.fields(after),s.fields(expected));
 for(const [key,doc]of Object.entries(before))if(!changed.has(key))s.same(after[key],doc);
 await s.api('http://127.0.0.1:4420/_admin/export',{path:path.join(run,'post-export'),initiatedBy:'brewverse-local-ledger-recovery'});
 s.same(backup,s.exportState(path.join(run,'post-export')));
 s.write(path.join(run,'post-records.json'),after);
 s.write(path.join(run,'verification.json'),{restoredMovementIds:ids,runningBalanceCorrections:corrections,quantity:30,bills:bills.length,unrelatedDocumentsUnchanged:true,authAndStorageUnchanged:true,newerRecords:newer});
 console.log('RECOVERY_VERIFIED: four movements restored; stock 30; bills, loyalty and all unrelated documents unchanged.');
}
main().catch(error=>{console.error(error);process.exitCode=1;});
