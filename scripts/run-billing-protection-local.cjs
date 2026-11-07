// Dedicated disposable-suite entry point. Never imports or exports phone data.
const fs=require('node:fs'),p=require('node:path'),cp=require('node:child_process');
const s=require('./local-emulator-state.cjs'),c=require('./local-checkpoint.cjs');
const cleanup=require('./disposable-emulator-cleanup.cjs');
const {isolatedRuntimeTemp}=require('./local-runtime-temp.cjs');
const {assertPortsAvailable}=require('./local-port-preflight.cjs');
async function freePorts(options) {
 await assertPortsAvailable([13185,13160,13198,13199,13101,13120,13121,13129,13149],options);
}
async function run({inventoryLoyalty = false, productionReadiness = false} = {}) {
 process.chdir(s.root);
 await s.guard();
 const saved=c.resolve(false);
 s.same(s.fields(await s.snapshot()),s.fields(saved.records));
 await freePorts();
 const hashes=s.hashes(saved.directory),allCheckpointHashes=s.hashes(p.join(s.root,'.firebase/checkpoints')),baseline=cleanup.processes();
 const dir=p.join(s.root,'.firebase/recovery/'+(productionReadiness?'production-readiness-':inventoryLoyalty?'inventory-loyalty-':'billing-protection-')+Date.now()+'-'+require('node:crypto').randomUUID().slice(0,8));
 fs.mkdirSync(dir);
 fs.writeFileSync(p.join(dir,'baseline.json'),JSON.stringify({checkpoint:saved.directory,hashes,allCheckpointHashes,primaryHub:await s.api('http://127.0.0.1:4420/')},null,2));
 const beforeExport=p.join(dir,'primary-before-export');
 await s.api('http://127.0.0.1:4420/_admin/export',{path:beforeExport,initiatedBy:'preserve-current-auth-and-storage-before-isolated-tests'});
 const beforeState=s.exportState(beforeExport,true);
 fs.copyFileSync(p.join(__dirname,'billing-test-network-guard.cjs'),p.join(dir,'loopback-only.cjs'));
 const profile=p.join(dir,'profile');
 for(const part of ['appdata','config'])fs.mkdirSync(p.join(profile,part),{recursive:true});
 const {env,tempDirectory}=isolatedRuntimeTemp(dir);
 fs.writeFileSync(p.join(dir,'runtime-temp.json'),JSON.stringify({directory:tempDirectory},null,2));
 for(const key of Object.keys(env))if(/TOKEN|PROXY|GOOGLE_APPLICATION_CREDENTIALS|NODE_OPTIONS|FIREBASE_CONFIG/i.test(key))delete env[key];
 Object.assign(env,{
  USERPROFILE:profile,APPDATA:p.join(profile,'appdata'),XDG_CONFIG_HOME:p.join(profile,'config'),
  CLOUDSDK_CONFIG:p.join(profile,'gcloud'),GOOGLE_APPLICATION_CREDENTIALS:p.join(profile,'absent.json'),
  GCLOUD_PROJECT:s.project,GOOGLE_CLOUD_PROJECT:s.project,
  FIREBASE_EMULATORS_PATH:p.join(process.env.USERPROFILE,'.cache/firebase/emulators'),
  FIREBASE_CLI_DISABLE_USAGE:'true',CI:'true',GCE_METADATA_HOST:'127.0.0.1:9',METADATA_SERVER_DETECTION:'none',
  BREWVERSE_ISOLATED_HOME:profile,
  NODE_OPTIONS:'--require="'+p.join(dir,'loopback-only.cjs').replaceAll('\\','/')+'"',
  FIRESTORE_EMULATOR_HOST:'127.0.0.1:13185',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:13198',FIREBASE_STORAGE_EMULATOR_HOST:'127.0.0.1:13199',
 });
 const locator=p.join(require('node:os').tmpdir(),'hub-brewverse-security-tests.json');
 const original=fs.readFileSync(locator);
 fs.writeFileSync(p.join(dir,'phone-hub-locator.json'),original);
 console.log('Disposable suite evidence:',dir);
 let code;
 try {
  code=await new Promise((resolve,reject)=>{
   const child=cp.spawn(process.execPath,[p.join(process.env.APPDATA,'npm/node_modules/firebase-tools/lib/bin/firebase.js'),
    'emulators:exec','--config',p.join(s.root,'firebase.test-emulators.json'),'--project',s.project,
    '--only','auth,firestore,functions,storage',
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-local-backend.ps1 -BillHistory '+(productionReadiness?'-ProductionReadiness':inventoryLoyalty?'-InventoryLoyalty':'-BillingProtection')],
    {env,windowsHide:true,stdio:['ignore','pipe','pipe']});
   for(const [stream,name]of [[child.stdout,'stdout.log'],[child.stderr,'stderr.log']]){
    const out=fs.createWriteStream(p.join(dir,name));
    stream.on('data',bytes=>{out.write(bytes);process.stdout.write(bytes)});
    stream.on('end',()=>out.end());
   }
   child.once('error',reject);child.once('close',resolve);
  });
 } finally {
  // The CLI already attempted graceful shutdown. Reap only verified new test JVMs.
  try { cleanup.cleanup(baseline); } finally {
   // The child uses its own temp hub locator. Never overwrite the primary locator.
   require('node:assert/strict').deepEqual(fs.readFileSync(locator),original,'Primary hub locator changed during disposable tests');
  }
 }
 await freePorts({waitForReleaseMs:20000});
 await s.guard();
 s.same(s.fields(await s.snapshot()),s.fields(saved.records));
 s.same(s.hashes(saved.directory),hashes);
 s.same(s.hashes(p.join(s.root,'.firebase/checkpoints')),allCheckpointHashes);
 const verificationExport=p.join(dir,'primary-verification-export');
 await s.api('http://127.0.0.1:4420/_admin/export',{path:verificationExport,initiatedBy:'isolated-test-primary-integrity-verification'});
 s.same(s.exportState(verificationExport,true),beforeState);
 fs.writeFileSync(p.join(dir,'result.json'),JSON.stringify({exitCode:code,mainUnchanged:true,checkpointUnchanged:true,allCheckpointsUnchanged:true,authStorageMatch:true},null,2));
 process.exitCode=code===0?0:1;
}
if(require.main===module)run({inventoryLoyalty:process.argv.includes('--inventory-loyalty'),productionReadiness:process.argv.includes('--production-readiness')}).catch(error=>{console.error(error);process.exitCode=1});
module.exports={run};
