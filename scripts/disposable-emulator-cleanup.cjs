const {execFileSync}=require('node:child_process');
function verifiedDisposable(process) {
  const cmd=process.CommandLine || '';
  return /[\\/]java\.exe$/i.test(process.ExecutablePath||'') &&
    /cloud-firestore-emulator-v[\d.]+\.jar(?:\s|$)/.test(cmd) &&
    /--host 127\.0\.0\.1(?:\s|$)/.test(cmd) &&
    /--port 13185(?:\s|$)/.test(cmd) &&
    /--websocket_port 13160(?:\s|$)/.test(cmd) &&
    /--project_id brewverse-security-tests(?:\s|$)/.test(cmd) &&
    /--functions_emulator 127\.0\.0\.1:13101(?:\s|$)/.test(cmd);
}
function processes() {
  const text=execFileSync('powershell.exe',['-NoProfile','-Command',"Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CreationDate,ExecutablePath,CommandLine | ConvertTo-Json -Compress"],{encoding:'utf8',windowsHide:true});
  return JSON.parse(text);
}
function newDisposable(current,baseline) {
  return current.filter(verifiedDisposable).filter(proc=>
    !baseline.some(old=>old.ProcessId===proc.ProcessId && old.CreationDate===proc.CreationDate));
}
function cleanup(baseline) {
  // CLI shutdown must finish first. Only remove newly spawned, exactly identified orphan JVMs.
  for(const proc of newDisposable(processes(),baseline)) {
    const fresh=processes().find(p=>p.ProcessId===proc.ProcessId);
    if(!fresh || fresh.CreationDate!==proc.CreationDate || !verifiedDisposable(fresh))throw Error('Disposable JVM identity changed');
    execFileSync('taskkill.exe',['/PID',String(proc.ProcessId),'/T','/F'],{windowsHide:true,stdio:'inherit'});
  }
}
module.exports={verifiedDisposable,newDisposable,processes,cleanup};
