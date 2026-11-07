// Reconnect missing local services without stopping or importing over the
// surviving Firestore process. This is a Firebase CLI 15.34 recovery adapter.
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const cliRoot = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools');
const { EmulatorRegistry } = require(path.join(cliRoot, 'lib/emulator/registry'));
const { command } = require(path.join(cliRoot, 'lib/commands/emulators-start'));
const { logger } = require(path.join(cliRoot, 'lib/logger'));

(async () => {
  const projectRoot = path.resolve(__dirname, '..');
  const originalTemp = require('node:os').tmpdir();
  const runtimeTemp = path.join(projectRoot,'.firebase/workflow-logs',`reconnect-${Date.now()}.runtime-temp`);
  fs.mkdirSync(runtimeTemp,{recursive:true});
  process.env.TEMP=runtimeTemp;process.env.TMP=runtimeTemp;
  const backup = process.argv[2]
    ? path.resolve(process.argv[2])
    : fs.readFileSync(path.join(projectRoot, '.firebase/recovery/current-account-backup.txt'), 'utf8').trim();
  assert(fs.existsSync(path.join(backup,'firebase-export-metadata.json')),'Complete recovery export is required');
  const response = await fetch('http://127.0.0.1:8085/v1/projects/brewverse-security-tests/databases/(default)/documents/cafes/SnEadZW3hynRmz4Gc0lC', {
    headers: { Authorization: 'Bearer owner' }, signal: AbortSignal.timeout(5000),
  });
  assert.equal(response.ok, true);
  assert.equal((await response.json()).fields.ownerUid.stringValue, 'P3OvJpZGoBRKEpElF4keS512MvEG');
  EmulatorRegistry.set('firestore', {
    getName: () => 'firestore',
    getInfo: () => ({ name: 'firestore', host: '127.0.0.1', port: 8085,
      listen: [{ address: '127.0.0.1', family: 'IPv4', port: 8085 }], reservedPorts: [9160] }),
    start: async () => {},
    connect: async () => {},
    stop: async () => { console.log('External Firestore left running; no stop or data import performed.'); },
  });
  process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8085';
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  console.log('Connecting local Auth, Functions, and Storage to the existing verified Firestore.');
  const locatorTimer=setInterval(async()=>{
    try {
      const hub=await (await fetch('http://127.0.0.1:4420/')).json();
      const services=await (await fetch('http://127.0.0.1:4420/emulators')).json();
      if(hub.pid!==process.pid || services.auth?.port!==9099 || services.storage?.port!==9199 || services.functions?.port!==5001)return;
      fs.writeFileSync(path.join(originalTemp,'hub-brewverse-security-tests.json'),JSON.stringify(hub));
      clearInterval(locatorTimer);
    } catch (_) { /* Wait for this adapter's hub to become ready. */ }
  },1000);
  locatorTimer.unref();
  await command.runner()({ project: 'brewverse-security-tests',
    config: path.join(projectRoot, 'firebase.json'), only: 'auth,functions,storage',
    import: backup,
    debug: true, nonInteractive: true, cwd: projectRoot });
})().catch((error) => {
  logger.error(error.stack || error.message);
  process.exitCode = 1;
});
