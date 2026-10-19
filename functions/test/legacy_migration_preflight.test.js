const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const { preflightLegacyMigration } = require('../src/legacy_migration_preflight');

function input() {
  return {
    documents: {
      stock_items: [
        { id: 'latte', data: { category: 'finished' } },
        { id: 'beans', data: { category: 'ingredient' } },
      ],
      product_recipes: [{ id: 'latte', data: {
        productId: 'latte', ingredients: [{ stockItemId: 'beans', quantity: 1 }], packaging: [],
      } }],
      bills: [{ id: 'bill-1', data: { items: [{ productId: 'latte', quantity: 1 }] } }],
      stock_movements: [{ id: 'move-1', data: { stockItemId: 'beans' } }],
    },
    ownerByRecord: {
      'stock_items/latte': 'cafe-a', 'stock_items/beans': 'cafe-a',
      'product_recipes/latte': 'cafe-a', 'bills/bill-1': 'cafe-a',
      'stock_movements/move-1': 'cafe-a',
    },
    ownerUidByCafe: { 'cafe-a': 'verified-owner-uid' },
  };
}

test('creates a deterministic review plan without mutating supplied export data', () => {
  const source = input();
  const before = structuredClone(source);
  const plan = preflightLegacyMigration(source);
  assert.equal(plan.safeToReview, true);
  assert.deepEqual(plan.errors, []);
  assert.equal(plan.updates.length, 5);
  assert.deepEqual(source, before);
  assert.deepEqual(plan.updates.map(({ collection, id }) => `${collection}/${id}`), [
    'bills/bill-1', 'product_recipes/latte', 'stock_items/beans',
    'stock_items/latte', 'stock_movements/move-1',
  ]);
});

test('rejects missing ownership, unverified café owners, and conflicting tenant data', () => {
  const source = input();
  delete source.ownerByRecord['bills/bill-1'];
  delete source.ownerUidByCafe['cafe-a'];
  source.documents.stock_items[0].data.cafeId = 'cafe-b';
  const plan = preflightLegacyMigration(source);
  assert.equal(plan.safeToReview, false);
  assert.ok(plan.errors.some((error) => error.includes('No explicit café owner mapping for bills/bill-1')));
  assert.ok(plan.errors.some((error) => error.includes('no operator-supplied owner UID mapping')));
  assert.ok(plan.errors.some((error) => error.includes('conflicting cafeId cafe-b')));
});

test('rejects cross-café references and flags historical movements with deleted items', () => {
  const source = input();
  source.ownerUidByCafe['cafe-b'] = 'another-verified-owner';
  source.ownerByRecord['stock_items/beans'] = 'cafe-b';
  source.documents.stock_movements[0].data.stockItemId = 'deleted-item';
  const plan = preflightLegacyMigration(source);
  assert.equal(plan.safeToReview, false);
  assert.ok(plan.errors.some((error) => error.includes('assigned to another café')));
  assert.ok(plan.warnings.some((warning) => warning.includes('stock_items/deleted-item')));
});

test('rejects mappings to absent documents and malformed references', () => {
  const source = input();
  source.ownerByRecord['bills/absent'] = 'cafe-a';
  source.documents.bills[0].data.items[0].productId = '';
  const plan = preflightLegacyMigration(source);
  assert.equal(plan.safeToReview, false);
  assert.ok(plan.errors.some((error) => error.includes('references missing document')));
  assert.ok(plan.errors.some((error) => error.includes('invalid bill product reference')));
});

test('rejects recipes and bills that violate finished-product and stock rules', () => {
  const finishedIngredient = input();
  finishedIngredient.documents.stock_items[1].data.category = 'finished';
  const recipePlan = preflightLegacyMigration(finishedIngredient);
  assert.ok(recipePlan.errors.some((error) => error.includes('must reference ingredient stock')));

  const nonFinishedProduct = input();
  nonFinishedProduct.documents.stock_items[0].data.category = 'ingredient';
  const productPlan = preflightLegacyMigration(nonFinishedProduct);
  assert.ok(productPlan.errors.some((error) => error.includes('product must be a finished stock item')));
  assert.ok(productPlan.errors.some((error) => error.includes('bill items must reference finished products')));

  const invalidQuantity = input();
  invalidQuantity.documents.product_recipes[0].data.ingredients[0].quantity = 0;
  const quantityPlan = preflightLegacyMigration(invalidQuantity);
  assert.ok(quantityPlan.errors.some((error) => error.includes('invalid ingredients line or quantity')));
});

test('offline CLI emits a reviewable plan for the bundled synthetic example', () => {
  const cli = path.join(__dirname, '..', 'scripts', 'preflight_legacy_migration.js');
  const sample = path.join(__dirname, '..', 'examples', 'legacy_migration_preflight.sample.json');
  const result = spawnSync(process.execPath, [cli, sample], { encoding: 'utf8' });

  assert.equal(result.status, 0, result.stderr);
  const plan = JSON.parse(result.stdout);
  assert.equal(plan.safeToReview, true);
  assert.equal(plan.updates.length, 5);
  assert.deepEqual(plan.errors, []);
});

test('offline CLI returns a non-zero status for unsafe ownership mappings', () => {
  const cli = path.join(__dirname, '..', 'scripts', 'preflight_legacy_migration.js');
  const result = spawnSync(process.execPath, [cli, '-'], {
    encoding: 'utf8',
    input: JSON.stringify({
      documents: {
        stock_items: [],
        product_recipes: [],
        bills: [],
        stock_movements: [],
      },
      ownerByRecord: { 'stock_items/missing': 'sample-cafe' },
      ownerUidByCafe: { 'sample-cafe': 'operator-reviewed-owner-uid' },
    }),
  });

  assert.equal(result.status, 2);
  assert.equal(JSON.parse(result.stdout).safeToReview, false);
  assert.match(result.stdout, /references missing document/);
});
