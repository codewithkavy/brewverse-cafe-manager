// Approved, create-only historical bill recovery against loopback emulators.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const run = fs.readFileSync(path.join(root, '.firebase/bill-recovery/current-path.txt'), 'utf8').trim();
const base = 'http://127.0.0.1:8085/v1/projects/brewverse-security-tests/databases/(default)/documents';
const cafe = 'SnEadZW3hynRmz4Gc0lC';
const mode = process.argv[2];
async function api(url, body) {
  const res = await fetch(url, {method: body ? 'POST' : 'GET', headers: {Authorization:'Bearer owner', 'Content-Type':'application/json'}, body:body ? JSON.stringify(body) : undefined, signal:AbortSignal.timeout(20000)});
  assert(res.ok, `${res.status}: ${await res.clone().text()}`);
  return res.json();
}
function canonical(v) {
  if (Array.isArray(v)) return v.map(canonical);
  if (v && typeof v === 'object') return Object.fromEntries(Object.keys(v).sort().map(k=>[k, k === 'timestampValue' || k === 'createTime' || k === 'updateTime' ? v[k].replace(/(\.\d*?)0+Z$/, '$1Z').replace(/\.Z$/, 'Z') : canonical(v[k])]));
  return v;
}
const equal = (a,b) => assert.deepEqual(canonical(a),canonical(b));
async function snapshot() {
  const out = {};
  async function walk(parent) {
    let token;
    do {
      const ids = await api(`${parent}:listCollectionIds`, {pageSize:1000, ...(token ? {pageToken:token}: {})});
      for (const id of ids.collectionIds || []) {
        let next;
        do {
          const url = new URL(`${parent}/${id}`); url.searchParams.set('pageSize','1000'); url.searchParams.set('showMissing','true'); if(next) url.searchParams.set('pageToken',next);
          const page = await api(url);
          const docs = page.documents || [];
          for (const doc of docs) if(doc.fields) out[doc.name.split('/documents/')[1]] = doc;
          for(let i=0;i<docs.length;i+=20) await Promise.all(docs.slice(i,i+20).map(doc=>walk(`http://127.0.0.1:8085/v1/${doc.name}`)));
          next=page.nextPageToken;
        } while(next);
      }
      token=ids.nextPageToken;
    } while(token);
  }
  await walk(base); return out;
}
function original() {
  const folder=path.join(root,'.firebase/bill-history-backup/20261021-165406');
  const a=JSON.parse(fs.readFileSync(path.join(folder,'records-before.json'))).bills;
  const b=JSON.parse(fs.readFileSync(path.join(folder,'records-after.json'))).bills;
  equal(a,b);
  const own=a.filter(d=>d.fields.cafeId.stringValue===cafe);
  assert.equal(own.length,5);
  assert.equal(own.reduce((s,d)=>s+Number(d.fields.total.integerValue || d.fields.total.doubleValue),0),2480);
  for(const doc of own) {
    assert.equal(doc.name.split('/').pop(),doc.fields.billId.stringValue);
    assert.equal(doc.fields.createdAt.timestampValue.slice(0,10),'2026-10-21');
    assert.equal(doc.fields.status.stringValue,'completed');
    const items=doc.fields.items.arrayValue.values;
    assert.equal(items.reduce((s,i)=>s+Number(i.mapValue.fields.lineTotal.integerValue),0),Number(doc.fields.total.integerValue));
  }
  return own;
}
async function verify(current) {
  const before=JSON.parse(fs.readFileSync(path.join(run,'pre-records.json')));
  const own=original(); const expected={...before};
  for(const doc of own) expected[`bills/${doc.fields.billId.stringValue}`] ??= doc;
  assert.equal(Object.keys(current).length,Object.keys(expected).length);
  for(const [key,doc] of Object.entries(expected)) {
    assert(current[key],`Missing ${key}`);
    // Original fields are exact; new Firestore create/update metadata is server-managed.
    if(before[key] && mode !== 'restart') equal(current[key],doc); else equal(current[key].fields,doc.fields);
  }
  const query=await api(`${base}:runQuery`,{structuredQuery:{from:[{collectionId:'bills'}],where:{fieldFilter:{field:{fieldPath:'cafeId'},op:'EQUAL',value:{stringValue:cafe}}},orderBy:[{field:{fieldPath:'createdAt'},direction:'DESCENDING'},{field:{fieldPath:'__name__'},direction:'DESCENDING'}],limit:26}});
  assert.equal(query.filter(x=>x.document).length,5);
  console.log(JSON.stringify({mode,allDocuments:Object.keys(current).length,recovered:4,cafeBills:5,total:2480,otherCafeBills:Object.entries(current).filter(([k,d])=>k.startsWith('bills/')&&d.fields.cafeId.stringValue!==cafe).length,allPreexistingDocumentFieldsUnchanged:true,metadataCompared:mode !== 'restart'}));
}
(async()=>{
  const hub=await api('http://127.0.0.1:4420/emulators');
  for(const [name,port] of Object.entries({auth:9099,firestore:8085,functions:5001,storage:9199})) assert.equal(hub[name].port,port);
  assert(fs.existsSync(path.join(run,'pre-export/firebase-export-metadata.json')),'Full backup required');
  const own=original();
  if(mode==='recover') {
    assert(!fs.existsSync(path.join(run,'pre-records.json')),'Recovery already started; use verify');
    const before=await snapshot(); fs.writeFileSync(path.join(run,'pre-records.json'),JSON.stringify(before,null,2));
    const present=own.filter(d=>before[`bills/${d.fields.billId.stringValue}`]); assert.equal(present.length,1); equal(before[`bills/${present[0].fields.billId.stringValue}`].fields,present[0].fields);
    assert.equal(Number(present[0].fields.total.integerValue),240);
    const missing=own.filter(d=>!before[`bills/${d.fields.billId.stringValue}`]);
    assert.equal(missing.length,4);
    fs.writeFileSync(path.join(run,'recovery-plan.json'),JSON.stringify(missing,null,2));
    // Atomic create-only batch: existing IDs can never be overwritten or duplicated.
    await api(`${base}:commit`,{writes:missing.map(d=>({update:{name:d.name,fields:d.fields},currentDocument:{exists:false}}))});
  } else assert(['verify','restart'].includes(mode));
  const current=await snapshot(); await verify(current);
  fs.writeFileSync(path.join(run,mode==='recover'?'post-records.json':'restart-records.json'),JSON.stringify(current,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
