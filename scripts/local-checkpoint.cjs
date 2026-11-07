const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const s=require('./local-emulator-state.cjs');
const home=path.join(s.root,'.firebase/checkpoints');
const pointerFile=path.join(home,'current.json');
const sessionFile=path.join(home,'session.json');
function atomic(file,data){fs.mkdirSync(path.dirname(file),{recursive:true});const tmp=file+'.'+crypto.randomUUID()+'.tmp';s.write(tmp,data);fs.renameSync(tmp,file);}
function validate(pointer, parent=home){
 assert.equal(pointer.version,1);assert.equal(pointer.project,s.project);
 assert(typeof pointer.directory==='string' && !path.isAbsolute(pointer.directory),'Checkpoint must use a relative path');
 const directory=path.resolve(parent,pointer.directory);
 assert(directory.startsWith(path.resolve(parent)+path.sep),'Checkpoint escaped its directory');
 const manifestFile=path.join(directory,'manifest.json');
 assert.equal(s.hash(fs.readFileSync(manifestFile)),pointer.manifestSha256,'Checkpoint manifest checksum mismatch');
 const manifest=s.read(manifestFile);assert.equal(manifest.project,s.project);assert.equal(manifest.complete,true);
 const actual=s.hashes(path.join(directory,'export'));s.same(actual,manifest.exportHashes);
 const records=s.read(path.join(directory,'records.json'));
 assert.equal(s.hash(fs.readFileSync(path.join(directory,'records.json'))),manifest.recordsSha256,'Record snapshot checksum mismatch');
 const state=s.exportState(path.join(directory,'export'));
 s.same(s.integrity(records,state),manifest.integrity);
 return {directory,manifest,records,state,importPath:path.join(directory,'export')};
}
function resolve(requireClean=true,parent=home){
 const pointerPath=path.join(parent,'current.json'),sessionPath=path.join(parent,'session.json');
 assert(fs.existsSync(pointerPath),'No validated checkpoint pointer. Save and verify a full live checkpoint first; automatic empty/older fallback is disabled.');
 const result=validate(s.read(pointerPath),parent);
 if(requireClean) {
  assert(fs.existsSync(sessionPath),'Checkpoint session marker is missing; inspect retained snapshots before importing.');
  const session=s.read(sessionPath);
  assert.equal(session.status,'clean','Previous emulator session was not safely checkpointed and stopped. Refusing stale import. Inspect retained exports and recover the latest session explicitly.');
  assert.equal(session.checkpoint,s.read(pointerPath).directory,'Session checkpoint is stale');
 }
 return result;
}
async function save(){
 await s.guard();fs.mkdirSync(home,{recursive:true});
 const id=new Date().toISOString().replace(/[:.]/g,'-')+'-'+crypto.randomUUID().slice(0,8);
 const directory=path.join(home,id);fs.mkdirSync(directory);
 const before=await s.snapshot();s.write(path.join(directory,'records.json'),before);
 // Native hub export coordinates all three stateful services. A second capture
 // checks Auth/Storage stability as well as every Firestore document/version.
 await s.api('http://127.0.0.1:4420/_admin/export',{path:path.join(directory,'export'),initiatedBy:'brewverse-validated-checkpoint'});
 const state=s.exportState(path.join(directory,'export'));
 await s.api('http://127.0.0.1:4420/_admin/export',{path:path.join(directory,'verification-export'),initiatedBy:'brewverse-checkpoint-stability-check'});
 s.same(state,s.exportState(path.join(directory,'verification-export')));
 s.same(before,await s.snapshot());
 const integrity=s.integrity(before,state);
 const manifest={version:1,project:s.project,complete:true,createdAt:new Date().toISOString(),exportHashes:s.hashes(path.join(directory,'export')),recordsSha256:s.hash(fs.readFileSync(path.join(directory,'records.json'))),integrity};
 s.write(path.join(directory,'manifest.json'),manifest);
 const pointer={version:1,project:s.project,directory:id,manifestSha256:s.hash(fs.readFileSync(path.join(directory,'manifest.json')))};
 validate(pointer);
 // No pointer is advanced until the entire immutable export has passed validation.
 atomic(pointerFile,pointer);
 const hub=await s.api('http://127.0.0.1:4420/');
 atomic(sessionFile,{version:1,status:'running',checkpoint:id,hubPid:hub.pid,savedAt:manifest.createdAt});
 console.log(`Validated checkpoint: ${directory}`);
 return directory;
}
async function compare(){
 await s.guard();const saved=resolve(false);s.same(s.fields(await s.snapshot()),s.fields(saved.records));
 const folder=path.join(home,'checks',crypto.randomUUID());
 fs.mkdirSync(path.dirname(folder),{recursive:true});
 await s.api('http://127.0.0.1:4420/_admin/export',{path:folder,initiatedBy:'brewverse-restart-verification'});
 // Import regenerates only these emulator-managed Auth timing fields.
 s.same(s.exportState(folder,true),s.exportState(path.join(saved.directory,'export'),true));
 s.integrity(await s.snapshot(),s.exportState(folder));
 console.log('Live Firestore fields, Auth identities/credentials/config, Storage bytes/metadata match the checkpoint.');
}
async function main(){
 const command=process.argv[2];
 if(command==='save')await save();
 else if(command==='resolve')console.log(resolve().importPath);
 else if(command==='reserve'){
  const saved=resolve();const pointer=s.read(pointerFile);
  atomic(sessionFile,{version:1,status:'starting',checkpoint:pointer.directory,startedAt:new Date().toISOString()});
  console.log(saved.importPath);
 }else if(command==='verify-live')await compare();
 else if(command==='mark-running'){
  await s.guard();const session=s.read(sessionFile);assert.equal(session.status,'starting');
  const hub=await s.api('http://127.0.0.1:4420/');atomic(sessionFile,{...session,status:'running',hubPid:hub.pid});
 }else if(command==='mark-clean'){
  const pointer=s.read(pointerFile);validate(pointer);const session=s.read(sessionFile);
  assert.equal(session.status,'running');assert.equal(session.checkpoint,pointer.directory);
  try{await fetch('http://127.0.0.1:4420/',{signal:AbortSignal.timeout(1000)});throw new Error('Emulator hub is still running');}catch(e){if(e.message==='Emulator hub is still running')throw e;}
  atomic(sessionFile,{...session,status:'clean',stoppedAt:new Date().toISOString()});
 }else throw new Error('Use save, resolve, reserve, mark-running, verify-live, or mark-clean');
}
module.exports={validate,resolve,atomic};
if(require.main===module){
 let lock;
 const lockFile=path.join(home,'operation.lock');
 (async()=>{try{
  fs.mkdirSync(home,{recursive:true});
  lock=fs.openSync(lockFile,'wx');fs.writeFileSync(lock,JSON.stringify({pid:process.pid,startedAt:new Date().toISOString()}));
  await main();
 }finally{if(lock!==undefined){fs.closeSync(lock);fs.unlinkSync(lockFile);}}})().catch(e=>{console.error(`CHECKPOINT REFUSED: ${e.message}`);process.exitCode=1;});
}
