'use strict';
const fs=require('fs'),p=require('path'),os=require('os'),net=require('net'),Module=require('module');
const dir=__dirname,log=p.join(dir,'isolation-events.jsonl');
function record(event,extra={}){fs.appendFileSync(log,JSON.stringify({at:new Date().toISOString(),pid:process.pid,event,...extra})+'\n');}
function local(host){return ['127.0.0.1','localhost','::1','[::1]','::ffff:127.0.0.1'].includes(String(host||'localhost').toLowerCase());}
const connect=net.Socket.prototype.connect;
net.Socket.prototype.connect=function(...args){let options=args[0];if(Array.isArray(options))options=options[0];if(typeof options==='number')options={port:options,host:typeof args[1]==='string'?args[1]:'localhost'};if(typeof options==='string')options={path:options};options=options||{};if(!options.path&&!local(options.host)){record('blocked-remote-connect',{host:String(options.host),port:options.port});const e=Error('BREWVERSE_LOCAL_ONLY: non-loopback connection denied');e.code='BREWVERSE_LOCAL_ONLY';throw e;}return connect.apply(this,args);};
const realLoad=Module._load;
Module._load=function(id,parent,isMain){const result=realLoad.apply(this,arguments);if(typeof id==='string'&&id.includes('adminSdkConfig')&&result.getProjectAdminSdkConfigOrCached){result.getProjectAdminSdkConfigOrCached=async(project)=>{if(project!=='brewverse-security-tests')throw Error('Unexpected project');record('local-admin-config');return {projectId:project,storageBucket:project+'.appspot.com'};};}return result;};
const forbidden=JSON.parse(process.env.BREWVERSE_FORBIDDEN_CREDENTIAL_PATHS||'[]').map(x=>p.resolve(x).toLowerCase());
function check(file){if(typeof file!=='string'&&!Buffer.isBuffer(file)&&!(file instanceof URL))return;const path=p.resolve(file instanceof URL?require('url').fileURLToPath(file):String(file)).toLowerCase();if(forbidden.some(x=>path===x||path.startsWith(x+p.sep))){record('blocked-credential-read');throw Error('BREWVERSE_LOCAL_ONLY: original credential path denied');}}
for(const key of ['readFileSync','readFile','openSync','open','createReadStream']){const real=fs[key];fs[key]=function(file,...args){check(file);return real.call(this,file,...args);};}
for(const key of ['readFile','open']){const real=fs.promises[key].bind(fs.promises);fs.promises[key]=async(file,...args)=>{check(file);return real(file,...args);};}
record('process-isolation-active',{entry:p.basename(process.argv[1]||''),homeIsolated:os.homedir()===process.env.BREWVERSE_ISOLATED_HOME,explicitAdcMissing:!fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS||''),project:process.env.GCLOUD_PROJECT,firestoreHost:process.env.FIRESTORE_EMULATOR_HOST||null,authHost:process.env.FIREBASE_AUTH_EMULATOR_HOST||null,storageHost:process.env.FIREBASE_STORAGE_EMULATOR_HOST||null});

