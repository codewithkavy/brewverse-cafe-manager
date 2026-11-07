const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const { test } = require('node:test');
const { isolatedRuntimeTemp } = require('../local-runtime-temp.cjs');

const root = path.resolve(__dirname, '../../.firebase/recovery');
const fixture = () => fs.mkdtempSync(path.join(root, 'temp-isolation-regression-'));
const subprocess = `
 const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
 const temp=path.resolve(os.tmpdir());
 const expected=path.resolve(process.env.EXPECTED_TEMP);
 assert.equal(temp,expected);
 const blobs=path.join(temp,'firebase/storage/blobs');
 const locator=path.join(temp,'hub-brewverse-security-tests.json');
 if(process.env.LIFECYCLE==='primary') {
  fs.mkdirSync(blobs,{recursive:true});
  fs.writeFileSync(path.join(blobs,'primary-sentinel'),'preserve-original-storage');
  fs.writeFileSync(locator,'primary-hub-sentinel');
 } else {
  fs.mkdirSync(blobs,{recursive:true});
  fs.writeFileSync(path.join(blobs,'disposable-sentinel'),'test-only');
  fs.writeFileSync(locator,'disposable-hub-sentinel');
  // Reproduce Firebase Storage's shutdown deletion, confined to this child temp.
  assert(blobs.startsWith(expected+path.sep));
  fs.rmSync(blobs,{recursive:true});
 }
 console.log(temp);
`;
function launch(env, lifecycle) {
 const result=cp.spawnSync(process.execPath,['-e',subprocess], {
  env:{...env,NODE_OPTIONS:'',EXPECTED_TEMP:env.TEMP,LIFECYCLE:lifecycle},
  windowsHide:true,encoding:'utf8',
 });
 assert.equal(result.status,0,result.stderr);
 assert.equal(result.stdout.trim(),env.TEMP);
}

test('disposable Storage shutdown cannot delete primary blobs or replace its hub locator',()=>{
 const evidence=fixture();
 const primary=isolatedRuntimeTemp(evidence);
 const disposable=isolatedRuntimeTemp(evidence,primary.env);
 assert.notEqual(disposable.tempDirectory,primary.tempDirectory);
 launch(primary.env,'primary');
 launch(disposable.env,'disposable');
 assert.equal(fs.readFileSync(path.join(primary.tempDirectory,'firebase/storage/blobs/primary-sentinel'),'utf8'),'preserve-original-storage');
 assert.equal(fs.readFileSync(path.join(primary.tempDirectory,'hub-brewverse-security-tests.json'),'utf8'),'primary-hub-sentinel');
 assert.equal(fs.existsSync(path.join(disposable.tempDirectory,'firebase/storage/blobs')),false);
 assert.equal(fs.readFileSync(path.join(disposable.tempDirectory,'hub-brewverse-security-tests.json'),'utf8'),'disposable-hub-sentinel');
});

test('all temporary environment aliases override inherited shared or mixed-case paths',()=>{
 const evidence=fixture();
 const result=isolatedRuntimeTemp(evidence,{TEMP:'shared-a',TMP:'shared-b',TMPDIR:'shared-c',temp:'shared-d',Tmp:'shared-e',KEEP:'retained'});
 assert.equal(result.env.TEMP,result.tempDirectory);
 assert.equal(result.env.TMP,result.tempDirectory);
 assert.equal(result.env.TMPDIR,result.tempDirectory);
 assert.equal(result.env.KEEP,'retained');
 assert.equal(result.env.temp,undefined);
 assert.equal(result.env.Tmp,undefined);
 launch(result.env,'primary');
});
