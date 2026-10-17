const { readFileSync } = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc, updateDoc, deleteDoc } = require('firebase/firestore');

const projectId = 'brewverse-security-tests';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8085,
      rules: readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'cafe_members', 'ownerA_cafeA'), {
      uid: 'ownerA',
      cafeId: 'cafeA',
      role: 'owner',
      status: 'active',
    });
    await setDoc(doc(db, 'cafe_members', 'ownerB_cafeB'), {
      uid: 'ownerB',
      cafeId: 'cafeB',
      role: 'owner',
      status: 'active',
    });
    await setDoc(doc(db, 'stock_items', 'itemA'), {
      cafeId: 'cafeA',
      name: 'Café A beans',
      quantity: 10,
    });
    await setDoc(doc(db, 'stock_items', 'itemB'), {
      cafeId: 'cafeB',
      name: 'Café B beans',
      quantity: 20,
    });
  });
});

describe('BrewVerse test-only inventory tenant rules', () => {
  it('allows an active member to read their own café inventory', async () => {
    const db = testEnv.authenticatedContext('ownerA').firestore();
    await assertSucceeds(getDoc(doc(db, 'stock_items', 'itemA')));
  });

  it('denies reading another café inventory by document ID', async () => {
    const db = testEnv.authenticatedContext('ownerA').firestore();
    await assertFails(getDoc(doc(db, 'stock_items', 'itemB')));
  });

  it('denies unauthenticated reads', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'stock_items', 'itemA')));
  });

  it('allows creating inventory only for a café the user belongs to', async () => {
    const db = testEnv.authenticatedContext('ownerA').firestore();
    await assertSucceeds(setDoc(doc(db, 'stock_items', 'newA'), {
      cafeId: 'cafeA',
      name: 'New beans',
      quantity: 5,
    }));
    await assertFails(setDoc(doc(db, 'stock_items', 'newB'), {
      cafeId: 'cafeB',
      name: 'Cross-tenant beans',
      quantity: 5,
    }));
  });

  it('prevents changing an item to another café', async () => {
    const db = testEnv.authenticatedContext('ownerA').firestore();
    await assertFails(updateDoc(doc(db, 'stock_items', 'itemA'), {
      cafeId: 'cafeB',
    }));
  });

  it('denies access when the membership is revoked', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'cafe_members', 'ownerA_cafeA'), {
        status: 'revoked',
      });
    });
    const db = testEnv.authenticatedContext('ownerA').firestore();
    await assertFails(getDoc(doc(db, 'stock_items', 'itemA')));
  });

  it('does not let clients write membership records', async () => {
    const db = testEnv.authenticatedContext('ownerA').firestore();
    await assertFails(setDoc(doc(db, 'cafe_members', 'ownerA_cafeB'), {
      uid: 'ownerA',
      cafeId: 'cafeB',
      role: 'owner',
      status: 'active',
    }));
  });

  it('denies access to unspecified collections by default', async () => {
    const db = testEnv.authenticatedContext('ownerA').firestore();
    await assertFails(getDoc(doc(db, 'bills', 'someBill')));
  });
});
