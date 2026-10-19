const { readFileSync } = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} = require('firebase/firestore');

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
    const memberships = [
      ['ownerA', 'cafeA', 'owner', 'active'],
      ['managerA', 'cafeA', 'manager', 'active'],
      ['staffA', 'cafeA', 'staff', 'active'],
      ['ownerB', 'cafeB', 'owner', 'active'],
      ['revokedA', 'cafeA', 'owner', 'revoked'],
      ['unknownRole', 'cafeA', 'superuser', 'active'],
    ];

    for (const [uid, cafeId, role, status] of memberships) {
      await setDoc(doc(db, 'cafe_members', `${uid}_${cafeId}`), {
        uid,
        cafeId,
        role,
        status,
      });
    }
    await setDoc(doc(db, 'cafes', 'cafeA'), { cafeId: 'cafeA', name: 'A' });
    await setDoc(doc(db, 'cafes', 'cafeB'), { cafeId: 'cafeB', name: 'B' });

    for (const [collectionName, fields] of [
      ['stock_items', {
        name: 'Beans',
        category: 'ingredient',
        unit: 'g',
        quantity: 12,
        minimumQuantity: 2,
        purchasePricePerUnit: 0.1,
        sellingPrice: 2.5,
        photoUrl: '',
      }],
      ['product_recipes', { productId: 'latte', ingredients: [] }],
      ['bills', { total: 100, status: 'completed' }],
      ['stock_movements', { type: 'addition', quantityChange: 12 }],
    ]) {
      await setDoc(doc(db, collectionName, `${collectionName}A`), {
        ...fields,
        cafeId: 'cafeA',
      });
      await setDoc(doc(db, collectionName, `${collectionName}B`), {
        ...fields,
        cafeId: 'cafeB',
      });
    }
  });
});

const memberDb = (uid) => testEnv.authenticatedContext(uid).firestore();
const record = (db, collectionName, id) => doc(db, collectionName, id);

describe('BrewVerse test-only tenant authorization rules', () => {
  it('lets a member read only their own membership and café profile', async () => {
    const db = memberDb('ownerA');
    await assertSucceeds(getDoc(record(db, 'cafe_members', 'ownerA_cafeA')));
    await assertFails(getDoc(record(db, 'cafe_members', 'ownerB_cafeB')));
    await assertSucceeds(getDoc(record(db, 'cafes', 'cafeA')));
    await assertFails(getDoc(record(db, 'cafes', 'cafeB')));
  });

  it('allows a membership query only when constrained to the caller UID', async () => {
    const db = memberDb('ownerA');
    const ownMemberships = query(
      collection(db, 'cafe_members'),
      where('uid', '==', 'ownerA'),
    );
    await assertSucceeds(getDocs(ownMemberships));
    await assertFails(getDocs(collection(db, 'cafe_members')));

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'cafe_members', 'ownerA_corrupt'), {
        uid: 'ownerB', cafeId: 'cafeA', role: 'owner', status: 'active',
      });
    });
    await assertFails(getDoc(record(db, 'cafe_members', 'ownerA_corrupt')));
  });

  it('does not allow clients to create, update, or delete memberships', async () => {
    const db = memberDb('ownerA');
    await assertFails(setDoc(record(db, 'cafe_members', 'ownerA_cafeC'), {
      uid: 'ownerA', cafeId: 'cafeC', role: 'owner', status: 'active',
    }));
    await assertFails(updateDoc(record(db, 'cafe_members', 'ownerA_cafeA'), {
      role: 'owner',
    }));
    await assertFails(deleteDoc(record(db, 'cafe_members', 'ownerA_cafeA')));
  });

  it('isolates reads across inventory, recipes, bills, and movements', async () => {
    const db = memberDb('ownerA');
    for (const collectionName of [
      'stock_items', 'product_recipes', 'bills', 'stock_movements',
    ]) {
      await assertSucceeds(getDoc(record(db, collectionName, `${collectionName}A`)));
      await assertFails(getDoc(record(db, collectionName, `${collectionName}B`)));
    }

    const unauthenticated = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(record(unauthenticated, 'stock_items', 'stock_itemsA')));
    await assertSucceeds(getDoc(record(memberDb('staffA'), 'bills', 'billsA')));
  });

  it('requires café-constrained queries for tenant business collections', async () => {
    const db = memberDb('ownerA');
    const cafeAItems = query(
      collection(db, 'stock_items'),
      where('cafeId', '==', 'cafeA'),
    );
    const cafeBItems = query(
      collection(db, 'stock_items'),
      where('cafeId', '==', 'cafeB'),
    );
    await assertSucceeds(getDocs(cafeAItems));
    await assertFails(getDocs(cafeBItems));
    await assertFails(getDocs(collection(db, 'stock_items')));
  });

  it('allows managers to edit item details but reserves stock changes for trusted code', async () => {
    const owner = memberDb('ownerA');
    const manager = memberDb('managerA');
    const staff = memberDb('staffA');

    await assertFails(setDoc(record(owner, 'stock_items', 'owner-item'), {
      cafeId: 'cafeA', name: 'Owner item', quantity: 0,
    }));
    await assertFails(updateDoc(record(manager, 'stock_items', 'stock_itemsA'), {
      quantity: 11,
    }));
    await assertSucceeds(updateDoc(record(manager, 'stock_items', 'stock_itemsA'), {
      sellingPrice: 2.5,
      updatedAt: serverTimestamp(),
    }));
    for (const invalidUpdate of [
      { name: '' },
      { name: '   ' },
      { name: 'x'.repeat(121) },
      { category: 'superuser' },
      { unit: '' },
      { unit: '\t ' },
      { unit: 'x'.repeat(33) },
      { minimumQuantity: -1 },
      { purchasePricePerUnit: -0.01 },
      { sellingPrice: -0.01 },
      { sellingPrice: 'free' },
      { photoUrl: 12 },
      { photoUrl: 'x'.repeat(2049) },
      { updatedAt: 'backdated timestamp' },
    ]) {
      await assertFails(updateDoc(
        record(manager, 'stock_items', 'stock_itemsA'),
        invalidUpdate,
      ));
    }
    await assertFails(setDoc(record(staff, 'stock_items', 'staff-item'), {
      cafeId: 'cafeA', name: 'Staff item', quantity: 1,
    }));
    await assertFails(updateDoc(record(staff, 'stock_items', 'stock_itemsA'), {
      quantity: 11,
    }));

    await assertFails(setDoc(record(manager, 'product_recipes', 'latte-new'), {
      cafeId: 'cafeA', productId: 'latte', ingredients: [],
    }));
    await assertFails(setDoc(record(staff, 'product_recipes', 'staff-recipe'), {
      cafeId: 'cafeA', productId: 'latte', ingredients: [],
    }));
    await assertFails(deleteDoc(record(owner, 'stock_items', 'stock_itemsA')));
  });

  it('requires cafe ownership to remain unchanged on updates', async () => {
    const db = memberDb('ownerA');
    await assertFails(updateDoc(record(db, 'stock_items', 'stock_itemsA'), {
      cafeId: 'cafeB',
    }));
    await assertFails(setDoc(record(db, 'stock_items', 'missing-cafe'), {
      name: 'Unscoped item', quantity: 1,
    }));
  });

  it('reserves bill and stock movement writes for trusted backend operations', async () => {
    const manager = memberDb('managerA');
    const staff = memberDb('staffA');

    await assertFails(setDoc(record(manager, 'bills', 'new-bill'), {
      cafeId: 'cafeA', total: 25, status: 'completed',
    }));
    await assertFails(setDoc(record(staff, 'bills', 'staff-bill'), {
      cafeId: 'cafeA', total: 25, status: 'completed',
    }));
    await assertFails(updateDoc(record(manager, 'bills', 'billsA'), {
      total: 0,
    }));
    await assertFails(deleteDoc(record(manager, 'bills', 'billsA')));

    await assertFails(setDoc(record(manager, 'stock_movements', 'new-movement'), {
      cafeId: 'cafeA', type: 'addition', quantityChange: 1,
    }));
    await assertFails(updateDoc(record(manager, 'stock_movements', 'stock_movementsA'), {
      quantityChange: 0,
    }));
    await assertFails(deleteDoc(record(manager, 'stock_movements', 'stock_movementsA')));
  });

  it('denies revoked members and all unspecified collection paths', async () => {
    const revoked = memberDb('revokedA');
    const malformed = memberDb('unknownRole');
    const owner = memberDb('ownerA');
    await assertFails(getDoc(record(revoked, 'stock_items', 'stock_itemsA')));
    await assertFails(getDoc(record(malformed, 'cafes', 'cafeA')));
    await assertFails(getDoc(record(malformed, 'stock_items', 'stock_itemsA')));
    await assertFails(getDoc(record(owner, 'private_config', 'secrets')));
  });
});
