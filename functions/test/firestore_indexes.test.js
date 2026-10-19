const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const repositoryRoot = path.resolve(__dirname, '../..');

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
