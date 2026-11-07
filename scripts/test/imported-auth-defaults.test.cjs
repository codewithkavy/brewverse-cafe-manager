const {test}=require('node:test'),a=require('node:assert/strict');
const {normalizeImportedAuthUser}=require('../local-emulator-state.cjs');
test('Auth import false defaults compare equal without hiding enabled verification or disabled accounts',()=>{
 const original={localId:'u',passwordHash:'protected-test-hash'};
 const imported={...original,disabled:false,emailVerified:false,passwordUpdatedAt:123,validSince:'123',lastRefreshAt:'now'};
 a.deepEqual(normalizeImportedAuthUser({...original}),normalizeImportedAuthUser({...imported}));
 a.notDeepEqual(normalizeImportedAuthUser({...original}),normalizeImportedAuthUser({...imported,disabled:true}));
 a.notDeepEqual(normalizeImportedAuthUser({...original}),normalizeImportedAuthUser({...imported,emailVerified:true}));
 a.equal(original.disabled,undefined);
 a.notDeepEqual(normalizeImportedAuthUser({...original}),normalizeImportedAuthUser({...original,passwordHash:'changed'}));
});
