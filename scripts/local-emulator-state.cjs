const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const project = 'brewverse-security-tests';
const base = `http://127.0.0.1:8085/v1/projects/${project}/databases/(default)/documents`;
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key,
    /^(timestampValue|createTime|updateTime)$/.test(key) && typeof value[key] === 'string'
      ? value[key].replace(/(\.\d*?)0+Z$/, '$1Z').replace(/\.Z$/, 'Z') : canonical(value[key])]));
  return value;
}
const same = (a, b) => assert.deepEqual(canonical(a), canonical(b));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const write = (file, data) => fs.writeFileSync(file, JSON.stringify(data, null, 2));
async function api(url, body) {
  assert(new URL(url).hostname === '127.0.0.1', 'Only loopback emulator requests are allowed');
  const response = await fetch(url, { method: body ? 'POST' : 'GET', headers: {Authorization:'Bearer owner', 'Content-Type':'application/json'},
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(60000) });
  assert(response.ok, `Local request failed: ${response.status} ${await response.clone().text()}`);
  return response.json();
}
async function guard() {
  const hub = await api('http://127.0.0.1:4420/');
  const locator = read(path.join(require('node:os').tmpdir(), `hub-${project}.json`));
  assert.equal(hub.pid, locator.pid, 'Wrong project emulator hub');
  const services = await api('http://127.0.0.1:4420/emulators');
  for (const [name, port] of Object.entries({auth:9099,firestore:8085,functions:5001,storage:9199})) {
    assert.equal(services[name]?.port, port, `Missing emulator: ${name}`);
    assert.equal(services[name]?.host, '127.0.0.1');
  }
}
async function snapshot() {
  const result = {};
  async function walk(parent) {
    let pageToken;
    do {
      const page = await api(`${parent}:listCollectionIds`, {pageSize:1000, ...(pageToken ? {pageToken} : {})});
      for (const id of page.collectionIds || []) {
        let token;
        do {
          const url = new URL(`${parent}/${id}`);
          url.searchParams.set('pageSize','1000'); url.searchParams.set('showMissing','true');
          if (token) url.searchParams.set('pageToken', token);
          const docs = await api(url.href);
          for (const doc of docs.documents || []) if (doc.fields) result[doc.name.split('/documents/')[1]] = doc;
          for (let i=0;i<(docs.documents || []).length;i+=20) await Promise.all(docs.documents.slice(i,i+20).map(doc=>walk(`http://127.0.0.1:8085/v1/${doc.name}`)));
          token = docs.nextPageToken;
        } while (token);
      }
      pageToken = page.nextPageToken;
    } while (pageToken);
  }
  await walk(base); return result;
}
function fields(records) { return Object.fromEntries(Object.entries(records).map(([key,doc])=>[key,doc.fields])); }
// Auth import materializes these documented false defaults. Normalize only
// comparisons; never rewrite account exports or hide a true security flag.
function normalizeImportedAuthUser(user) {
  for (const key of ['passwordUpdatedAt', 'validSince', 'lastRefreshAt']) delete user[key];
  for (const key of ['disabled', 'emailVerified']) if (user[key] === undefined) user[key] = false;
  return user;
}
function exportState(folder, afterImport = false) {
  const metadata = read(path.join(folder,'firebase-export-metadata.json'));
  for (const service of ['auth','firestore','storage']) assert(metadata[service], `Incomplete export: ${service}`);
  assert(metadata.firestore.metadata_file, 'Missing native Firestore metadata');
  for(const relative of [metadata.auth.path,metadata.storage.path,metadata.firestore.path,metadata.firestore.metadata_file]) {
    const target=path.resolve(folder,relative);
    assert(target.startsWith(path.resolve(folder)+path.sep),'Export resource escaped checkpoint');
    assert(fs.existsSync(target),`Missing export resource: ${relative}`);
  }
  assert(Object.keys(hashes(path.join(folder,metadata.firestore.path))).some(file=>file.includes('output-')),'Missing native Firestore data shards');
  const auth = read(path.join(folder,metadata.auth.path,'accounts.json'));
  auth.users?.sort((a,b)=>a.localId.localeCompare(b.localId));
  if (afterImport) for (const user of auth.users || []) normalizeImportedAuthUser(user);
  const storageRoot = path.join(folder, metadata.storage.path);
  const storage = {buckets:read(path.join(storageRoot,'buckets.json')).buckets.sort((a,b)=>a.id.localeCompare(b.id)), objects:[]};
  const metaRoot = path.join(storageRoot,'metadata');
  if (fs.existsSync(metaRoot)) for (const file of fs.readdirSync(metaRoot)) {
    const object = read(path.join(metaRoot,file));
    const bytes = fs.readFileSync(path.join(storageRoot,'blobs',file.replace(/\.json$/,'')));
    assert.equal(bytes.length, Number(object.size), `Storage size mismatch: ${object.name}`);
    if(object.md5Hash) assert.equal(crypto.createHash('md5').update(bytes).digest('base64'),object.md5Hash,`Storage checksum mismatch: ${object.name}`);
    storage.objects.push({metadata:object,sha256:hash(bytes)});
  }
  storage.objects.sort((a,b)=>(a.metadata.bucket+'/'+a.metadata.name).localeCompare(b.metadata.bucket+'/'+b.metadata.name));
  return {auth, authConfig:read(path.join(folder,metadata.auth.path,'config.json')), storage};
}
function integrity(records, exported) {
  const warnings = [];
  const byItem = new Map();
  for (const [key,doc] of Object.entries(records)) if (key.startsWith('stock_movements/')) {
    const f=doc.fields; const item=f.stockItemId?.stringValue; const cafe=f.cafeId?.stringValue;
    if(item && cafe) { const id=cafe+'/'+item; if(!byItem.has(id))byItem.set(id,[]); byItem.get(id).push(f); }
  }
  // Only the repaired user's ledger is a promotion invariant; unrelated test fixtures deliberately include partial ledgers.
  const item='tQNQuUPwYjq6WyZ2Vrur'; const cafe='SnEadZW3hynRmz4Gc0lC';
  const ledger=byItem.get(cafe+'/'+item) || [];
  ledger.sort((a,b)=>Date.parse(a.createdAt.timestampValue)-Date.parse(b.createdAt.timestampValue));
  let quantity=0;
  for(const f of ledger) { quantity+=number(f.quantityChange); assert.equal(number(f.quantityAfter),quantity,'Burger Bun ledger discontinuity'); }
  assert.equal(number(records['stock_items/'+item]?.fields.quantity),quantity,'Burger Bun quantity differs from ledger');
  const saleIds=new Set(ledger.filter(f=>f.type.stringValue==='sale').map(f=>f.billId?.stringValue));
  for(const [key,doc] of Object.entries(records)) if(key.startsWith('bills/') && doc.fields.cafeId?.stringValue===cafe) {
    const usesBurger=(doc.fields.items?.arrayValue?.values || []).some(line=>line.mapValue?.fields.productId?.stringValue==='ZuKk9x0wOFMn1kvP9Kd8');
    if(usesBurger && doc.fields.status?.stringValue==='completed') assert(saleIds.has(key.split('/')[1]), `Missing movement for ${key}`);
  }
  for(const [key,doc] of Object.entries(records)) {
    const url=doc.fields.photoUrl?.stringValue;
    if(!url) continue;
    try { const u=new URL(url); if(u.hostname!=='127.0.0.1') {warnings.push(`${key}: nonlocal photo URL not fetched`);continue;}
      const m=u.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/); assert(m,'Invalid local photo URL');
      assert(exported.storage.objects.some(o=>o.metadata.bucket===decodeURIComponent(m[1])&&o.metadata.name===decodeURIComponent(m[2])), `Missing photo object for ${key}`);
    } catch(error) { throw new Error(`Photo integrity: ${error.message}`); }
  }
  return {burgerBuns:quantity,documents:Object.keys(records).length,warnings};
}
function number(value) { assert(value && ('integerValue' in value || 'doubleValue' in value),'Numeric value required'); return Number(value.integerValue ?? value.doubleValue); }
function hashes(folder) {
  const result={};
  function walk(dir) { for(const entry of fs.readdirSync(dir,{withFileTypes:true})) {const file=path.join(dir,entry.name); if(entry.isDirectory())walk(file); else result[path.relative(folder,file).replaceAll('\\','/')]=hash(fs.readFileSync(file));} }
  walk(folder); return result;
}
module.exports={normalizeImportedAuthUser,root,project,base,canonical,same,hash,read,write,api,guard,snapshot,fields,exportState,integrity,number,hashes};
