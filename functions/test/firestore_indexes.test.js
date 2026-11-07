const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');

test('root emulator config matches the physical phone and uses existing local resources', () => {
  const config = JSON.parse(readFileSync(path.join(repositoryRoot, 'firebase.json'), 'utf8'));
  const aliases = JSON.parse(readFileSync(path.join(repositoryRoot, '.firebaserc'), 'utf8'));
  assert.equal(aliases.projects.default, 'brewverse-security-tests');
  assert.equal(config.flutter.platforms.android.default.projectId, 'brewverse-593dc');
  for (const [name, port] of Object.entries({ auth: 9099, firestore: 8085, functions: 5001, storage: 9199 })) {
    assert.equal(config.emulators[name].host, '127.0.0.1');
    assert.equal(config.emulators[name].port, port);
  }
  assert.equal(config.functions[0].source, 'functions');
  for (const resource of [config.firestore.rules, config.storage.rules, `${config.functions[0].source}/src/index.js`]) {
    assert.ok(readFileSync(path.join(repositoryRoot, resource), 'utf8').length > 0);
  }
});

test('Firebase CLI config points to the tenant query index manifest', () => {
  const firebaseConfig = JSON.parse(
    readFileSync(path.join(repositoryRoot, 'firebase.json'), 'utf8'),
  );
  assert.equal(firebaseConfig.firestore?.indexes, 'firestore.indexes.json');

  const manifest = JSON.parse(
    readFileSync(path.join(repositoryRoot, firebaseConfig.firestore.indexes), 'utf8'),
  );
  const actual = manifest.indexes.map((index) => ({
    collectionGroup: index.collectionGroup,
    queryScope: index.queryScope,
    fields: index.fields.map(({ fieldPath, order }) => `${fieldPath}:${order}`),
  })).sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
  const expected = [
    {
      collectionGroup: 'bills',
      queryScope: 'COLLECTION',
      fields: ['cafeId:ASCENDING', 'customerPhone:ASCENDING', 'createdAt:DESCENDING'],
    },
    {
      collectionGroup: 'bills',
      queryScope: 'COLLECTION',
      fields: ['cafeId:ASCENDING', 'createdAt:ASCENDING'],
    },
    {
      collectionGroup: 'bills',
      queryScope: 'COLLECTION',
      fields: ['cafeId:ASCENDING', 'createdAt:DESCENDING'],
    },
    {
      collectionGroup: 'stock_movements',
      queryScope: 'COLLECTION',
      fields: ['cafeId:ASCENDING', 'createdAt:DESCENDING'],
    },
  ].sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));

  assert.deepEqual(actual, expected);
  assert.deepEqual(manifest.fieldOverrides, []);
});
