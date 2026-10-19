// Pure, offline preflight for an explicitly supplied Firestore export.
// This module deliberately has no Firebase imports and performs no I/O.
const BUSINESS_COLLECTIONS = [
  'stock_items',
  'product_recipes',
  'bills',
  'stock_movements',
];

function preflightLegacyMigration(input) {
  const errors = [];
  const warnings = [];
  const updates = [];
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { safeToReview: false, updates, errors: ['Input must be an object.'], warnings };
  }

  const docs = input.documents ?? {};
  const ownerMap = input.ownerByRecord ?? {};
  const ownerByCafe = input.ownerUidByCafe ?? {};
  const records = new Map();
  for (const collection of BUSINESS_COLLECTIONS) {
    if (docs[collection] == null) {
      errors.push(`Missing documents list for ${collection}.`);
      continue;
    }
    if (!Array.isArray(docs[collection])) {
      errors.push(`${collection} must be a list.`);
      continue;
    }
    for (const record of docs[collection]) {
      if (!record || typeof record.id !== 'string' || !record.id ||
          !record.data || typeof record.data !== 'object' || Array.isArray(record.data)) {
        errors.push(`${collection} contains a record with an invalid id or data object.`);
        continue;
      }
      const key = `${collection}/${record.id}`;
      if (records.has(key)) {
        errors.push(`Duplicate document in input: ${key}.`);
        continue;
      }
      records.set(key, { collection, id: record.id, data: record.data });
    }
  }

  const assignments = new Map();
  for (const [key, cafeId] of Object.entries(ownerMap)) {
    if (!records.has(key)) {
      errors.push(`Ownership mapping references missing document: ${key}.`);
      continue;
    }
    if (typeof cafeId !== 'string' || !cafeId.trim()) {
      errors.push(`Ownership mapping for ${key} has an invalid café ID.`);
      continue;
    }
    assignments.set(key, cafeId.trim());
  }
  for (const [key, record] of records) {
    const cafeId = assignments.get(key);
    if (!cafeId) {
      errors.push(`No explicit café owner mapping for ${key}.`);
      continue;
    }
    if (typeof ownerByCafe[cafeId] !== 'string' || !ownerByCafe[cafeId].trim()) {
      errors.push(`Café ${cafeId} has no operator-supplied owner UID mapping.`);
    }
    if (record.data.cafeId != null && record.data.cafeId !== cafeId) {
      errors.push(`${key} already has conflicting cafeId ${String(record.data.cafeId)}.`);
      continue;
    }
    if (record.data.cafeId == null) updates.push({ collection: record.collection, id: record.id, cafeId });
    if (record.collection === 'stock_items' &&
        record.data.category !== 'ingredient' && record.data.category !== 'finished') {
      errors.push(`${key} has an unsupported stock category.`);
    }
  }

  const cafeFor = (collection, id) => assignments.get(`${collection}/${id}`);
  for (const [key, record] of records) {
    const sourceCafe = assignments.get(key);
    if (!sourceCafe) continue;
    const checkReference = (collection, refId, label) => {
      if (typeof refId !== 'string' || !refId) {
        errors.push(`${key} has an invalid ${label} reference.`);
        return;
      }
      const refCafe = cafeFor(collection, refId);
      if (!refCafe) {
        const message = `${key} references missing or unmapped ${collection}/${refId}.`;
        if (record.collection === 'stock_movements') warnings.push(message);
        else errors.push(message);
      } else if (refCafe !== sourceCafe) {
        errors.push(`${key} references ${collection}/${refId} assigned to another café.`);
      }
      return records.get(`${collection}/${refId}`) ?? null;
    };
    if (record.collection === 'product_recipes') {
      if (record.data.productId !== record.id) {
        errors.push(`${key} productId must match the recipe document ID.`);
      }
      const product = checkReference('stock_items', record.data.productId, 'product');
      if (product && product.data.category !== 'finished') {
        errors.push(`${key} product must be a finished stock item.`);
      }
      for (const section of ['ingredients', 'packaging']) {
        if (section === 'packaging' && record.data[section] == null) continue;
        const lines = record.data[section];
        if (!Array.isArray(lines) || lines.length > 100 ||
            (section === 'ingredients' && lines.length === 0)) {
          errors.push(`${key} ${section} must be a list with a valid number of lines.`);
          continue;
        }
        for (const line of lines) {
          if (!line || typeof line !== 'object' || Array.isArray(line) ||
              typeof line.quantity !== 'number' || !Number.isFinite(line.quantity) ||
              line.quantity <= 0) {
            errors.push(`${key} contains an invalid ${section} line or quantity.`);
            continue;
          }
          const stockItem = checkReference(
            'stock_items', line.stockItemId, `${section} stock item`,
          );
          if (stockItem && stockItem.data.category === 'finished') {
            errors.push(`${key} ${section} must reference ingredient stock, not a finished product.`);
          }
        }
      }
    } else if (record.collection === 'bills') {
      const items = record.data.items;
      if (!Array.isArray(items) || items.length === 0 || items.length > 100) {
        errors.push(`${key} items must be a non-empty list of at most 100 products.`);
      } else {
        for (const line of items) {
          if (!line || typeof line !== 'object' || Array.isArray(line) ||
              !Number.isSafeInteger(line.quantity) || line.quantity <= 0) {
            errors.push(`${key} contains an invalid bill item or quantity.`);
            continue;
          }
          const product = checkReference('stock_items', line.productId, 'bill product');
          if (product && product.data.category !== 'finished') {
            errors.push(`${key} bill items must reference finished products.`);
          }
        }
      }
    } else if (record.collection === 'stock_movements') {
      checkReference('stock_items', record.data.stockItemId, 'stock item');
    }
  }

  updates.sort((a, b) => `${a.collection}/${a.id}`.localeCompare(`${b.collection}/${b.id}`));
  errors.sort();
  warnings.sort();
  return { safeToReview: errors.length === 0, updates, errors, warnings };
}

module.exports = { preflightLegacyMigration };
