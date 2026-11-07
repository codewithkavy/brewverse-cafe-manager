const {test}=require('node:test');
const assert=require('node:assert/strict');
const {verifiedIdentity}=require('../src/auth_policy');
const password={uid:'u',token:{email:'owner@example.test',email_verified:false,firebase:{sign_in_provider:'password'}}};
test('cloud password accounts require server-verified email claims',()=>{
 assert.equal(verifiedIdentity(password,{}),false);
 assert.equal(verifiedIdentity({...password,token:{...password.token,email_verified:true}},{}),true);
 assert.equal(verifiedIdentity({uid:'u',token:{email_verified:true}},{}),false);
 assert.equal(verifiedIdentity(null,{}),false);
});
test('phone-only cloud identities require verified phone provider and number',()=>{
 assert.equal(verifiedIdentity({uid:'u',token:{firebase:{sign_in_provider:'phone'},phone_number:'+919876543210'}},{}),true);
 assert.equal(verifiedIdentity({uid:'u',token:{firebase:{sign_in_provider:'anonymous'},phone_number:'+919876543210'}},{}),false);
 assert.equal(verifiedIdentity({uid:'u',token:{firebase:{sign_in_provider:'phone'}}},{}),false);
});
test('verification exemption requires the isolated project and explicit local Auth emulator',()=>{
 assert.equal(verifiedIdentity(password,{GCLOUD_PROJECT:'brewverse-security-tests',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:13198'}),true);
 assert.equal(verifiedIdentity(password,{GCLOUD_PROJECT:'brewverse-593dc',FIREBASE_AUTH_EMULATOR_HOST:'127.0.0.1:13198'}),false);
 assert.equal(verifiedIdentity(password,{GCLOUD_PROJECT:'brewverse-security-tests'}),false);
 assert.equal(verifiedIdentity(password,{GCLOUD_PROJECT:'brewverse-security-tests',FIREBASE_AUTH_EMULATOR_HOST:'remote.example:9099'}),false);
 assert.equal(verifiedIdentity({...password,token:{...password.token,aud:'brewverse-security-tests'}},{}),false);
});
