const { readFileSync } = require('node:fs');
const path = require('node:path');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const { doc, setDoc } = require('firebase/firestore');
const { deleteObject, getBytes, ref, uploadBytes } = require('firebase/storage');

const projectId = 'brewverse-security-tests';
let testEnv;

before(async () => {
  if (process.env.GCLOUD_PROJECT !== projectId ||
      !process.env.FIRESTORE_EMULATOR_HOST ||
      !process.env.FIREBASE_STORAGE_EMULATOR_HOST) {
    throw new Error(
      'Refusing to run Storage rules tests outside the isolated Firestore and Storage emulators.',
    );
  }
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8085,
      rules: readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: readFileSync(path.join(__dirname, '..', 'storage.rules'), 'utf8'),
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const [uid, cafeId, role, status] of [
      ['ownerA', 'cafeA', 'owner', 'active'],
      ['managerA', 'cafeA', 'manager', 'active'],
      ['staffA', 'cafeA', 'staff', 'active'],
      ['ownerB', 'cafeB', 'owner', 'active'],
      ['revokedA', 'cafeA', 'manager', 'revoked'],
      ['unknownRole', 'cafeA', 'superuser', 'active'],
    ]) {
      await setDoc(doc(db, 'cafe_members', `${uid}_${cafeId}`), {
        uid,
        cafeId,
        role,
        status,
      });
    }
  });
});

function storageFor(uid) {
  return testEnv.authenticatedContext(uid).storage();
}

const image = new Uint8Array([137, 80, 78, 71]);
const jpeg = { contentType: 'image/jpeg' };

describe('BrewVerse test-only tenant Storage rules', () => {
  it('allows active members to read only same-café product images', async () => {
    const managerRef = ref(storageFor('managerA'), 'cafes/cafeA/products/item.jpg');
    await assertSucceeds(uploadBytes(managerRef, image, jpeg));
    await assertSucceeds(getBytes(managerRef));
    await assertSucceeds(
      getBytes(ref(storageFor('staffA'), 'cafes/cafeA/products/item.jpg')),
    );
    await assertFails(
      getBytes(ref(storageFor('ownerB'), 'cafes/cafeA/products/item.jpg')),
    );
    await assertFails(
      getBytes(
        ref(testEnv.unauthenticatedContext().storage(), 'cafes/cafeA/products/item.jpg'),
      ),
    );
    await assertFails(
      getBytes(ref(storageFor('revokedA'), 'cafes/cafeA/products/item.jpg')),
    );
    await assertFails(
      getBytes(ref(storageFor('unknownRole'), 'cafes/cafeA/products/item.jpg')),
    );
  });

  it('allows managers to upload valid images and denies staff writes', async () => {
    const managerRef = ref(storageFor('managerA'), 'cafes/cafeA/products/manager.jpg');
    const staffRef = ref(storageFor('staffA'), 'cafes/cafeA/products/staff.jpg');
    const foreignCafeRef = ref(storageFor('ownerB'), 'cafes/cafeA/products/foreign.jpg');
    await assertSucceeds(uploadBytes(managerRef, image, jpeg));
    await assertFails(uploadBytes(staffRef, image, jpeg));
    await assertFails(uploadBytes(foreignCafeRef, image, jpeg));
  });

  it('rejects unsupported content types and oversized images', async () => {
    const managerStorage = storageFor('managerA');
    await assertFails(
      uploadBytes(
        ref(managerStorage, 'cafes/cafeA/products/not-an-image.bin'),
        new Uint8Array([1, 2, 3]),
        { contentType: 'application/octet-stream' },
      ),
    );
    await assertFails(
      uploadBytes(
        ref(managerStorage, 'cafes/cafeA/products/too-large.jpg'),
        new Uint8Array(5 * 1024 * 1024 + 1),
        jpeg,
      ),
    );
  });

  it('denies unscoped legacy paths and unauthorized deletion', async () => {
    const seeded = await testEnv.withSecurityRulesDisabled((context) =>
      uploadBytes(
        ref(context.storage(), 'cafes/cafeA/products/seeded.jpg'),
        image,
        jpeg,
      ),
    );
    void seeded;
    await assertFails(
      getBytes(ref(storageFor('ownerA'), 'products/seeded.jpg')),
    );
    await assertFails(
      deleteObject(ref(storageFor('staffA'), 'cafes/cafeA/products/seeded.jpg')),
    );
    await assertSucceeds(
      deleteObject(ref(storageFor('ownerA'), 'cafes/cafeA/products/seeded.jpg')),
    );
  });
});
