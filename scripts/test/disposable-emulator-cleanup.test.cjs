const {test}=require('node:test'),assert=require('node:assert/strict');
const {verifiedDisposable,newDisposable}=require('../disposable-emulator-cleanup.cjs');
const candidate={ExecutablePath:'C:\\Java\\bin\\java.exe',CommandLine:'java -jar cloud-firestore-emulator-v1.22.0.jar --host 127.0.0.1 --port 13185 --websocket_port 13160 --project_id brewverse-security-tests --functions_emulator 127.0.0.1:13101'};
test('cleanup identifies only the exact disposable Firestore process',()=>{
 assert(verifiedDisposable(candidate));
 for(const [from,to]of [['13185','8085'],['13160','9160'],['13101','5001'],['brewverse-security-tests','production'],['127.0.0.1','0.0.0.0'],['13185','131850']])assert.equal(verifiedDisposable({...candidate,CommandLine:candidate.CommandLine.replace(from,to)}),false);
 assert.equal(verifiedDisposable({...candidate,ExecutablePath:'C:\\node.exe'}),false);
 assert.equal(verifiedDisposable({}),false);
});

test('cleanup excludes pre-existing processes and recognizes PID reuse by creation time',()=>{
 const old={...candidate,ProcessId:123,CreationDate:'old'};
 const primary={...candidate,ProcessId:456,CreationDate:'now',CommandLine:candidate.CommandLine.replace('13185','8085')};
 assert.deepEqual(newDisposable([old,primary],[old]),[]);
 const reused={...old,CreationDate:'new'};
 assert.deepEqual(newDisposable([reused,primary],[old]),[reused]);
});
