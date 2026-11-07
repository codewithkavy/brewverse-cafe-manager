// Read-only phone verification plus a new native export; never advances a pointer.
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const s=require('./local-emulator-state.cjs');
async function main(){
  await s.guard();
  const folder=fs.readFileSync(path.join(s.root,'.firebase/reliability/current-path.txt'),'utf8').trim();
  assert(folder.startsWith(path.join(s.root,'.firebase/reliability')+path.sep));
  const before=s.read(path.join(folder,'phone-before.json'));
  const after=await s.snapshot();s.same(after,before);
  const target=path.join(folder,'phone-verification-'+Date.now());
  await s.api('http://127.0.0.1:4420/_admin/export',{path:target,initiatedBy:'read-only-reliability-preservation-check'});
  // Auth import regenerates emulator timing fields. Compare every identity,
  // credential, provider and config field while excluding only those timings.
  const original=s.exportState(path.join(folder,'phone-export'),true),current=s.exportState(target,true);
  try { s.same(current,original); } catch (_) { throw new Error('Auth/Storage preservation comparison failed; inspect private exports locally.'); }
  const beforeUsers=s.exportState(path.join(folder,'phone-export')).auth.users;
  const afterUsers=s.exportState(target).auth.users;
  for(const user of beforeUsers) assert.equal(afterUsers.find(u=>u.localId===user.localId)?.validSince,user.validSince,'Original local session cutoff changed');
  const checkpoint=path.join(s.root,'.firebase/checkpoints/stable-v1-20261022-182112');
  s.same(s.hashes(checkpoint),s.read(path.join(folder,'protected-hashes.json')));
  const integrity=s.integrity(after,current);
  const bills=Object.entries(after).filter(([id])=>id.startsWith('bills/'));
  const own=bills.filter(([,doc])=>doc.fields.cafeId?.stringValue==='SnEadZW3hynRmz4Gc0lC');
  assert.equal(own.length,7);assert.equal(bills.length-own.length,26);assert.equal(integrity.burgerBuns,30);
  const result={verifiedAt:new Date().toISOString(),firestoreDocuments:Object.keys(after).length,cafeBills:own.length,otherCafeBills:bills.length-own.length,burgerBuns:integrity.burgerBuns,authUsers:current.auth.users.length,storageObjects:current.storage.objects.length,firestoreVersionsUnchanged:true,authIdentitiesCredentialsAndConfigUnchanged:true,originalSessionCutoffUnchanged:true,authImportTimingFieldsExcluded:['passwordUpdatedAt','lastRefreshAt'],storageBytesAndMetadataUnchanged:true,protectedCheckpointHashesUnchanged:true,export:target};
  s.write(path.join(folder,'preservation-result.json'),result);console.log(JSON.stringify(result,null,2));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
