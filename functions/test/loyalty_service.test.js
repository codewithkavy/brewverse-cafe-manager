const assert = require('node:assert/strict');
const { test } = require('node:test');

const {
  DEFAULT_LOYALTY_SETTINGS,
  LoyaltyPolicyError,
  calculateEarnedPoints,
  calculateRedemption,
  normalizePhoneNumber,
  resolveLoyaltySettings,
  validateLoyaltySettings,
} = require('../src/loyalty_service');

test('default loyalty policy awards base points and the highest qualifying bonus tier', () => {
  const settings = resolveLoyaltySettings(null);
  assert.equal(settings.expiryMonths, 12);
  assert.equal(calculateEarnedPoints({ netPaidMinor: 9999, settings }), 0);
  assert.equal(calculateEarnedPoints({ netPaidMinor: 10000, settings }), 4);
  assert.equal(calculateEarnedPoints({ netPaidMinor: 50000, settings }), 25);
  assert.equal(calculateEarnedPoints({ netPaidMinor: 100000, settings }), 50);
});

test('disabled loyalty and disabled expiry are represented explicitly', () => {
  const settings = validateLoyaltySettings({
    ...DEFAULT_LOYALTY_SETTINGS,
    enabled: false,
    expiryMonths: null,
    bonusTiers: [],
  });
  assert.equal(settings.enabled, false);
  assert.equal(settings.expiryMonths, null);
  assert.equal(calculateEarnedPoints({ netPaidMinor: 100000, settings }), 0);
});

test('redemption converts points to paise and enforces balance and bill cap', () => {
  const settings = resolveLoyaltySettings(null);
  assert.deepEqual(calculateRedemption({
    requestedPoints: 10,
    balancePoints: 15,
    billTotalMinor: 5000,
    settings,
  }), { points: 10, discountMinor: 1000 });
  assert.throws(() => calculateRedemption({
    requestedPoints: 16,
    balancePoints: 15,
    billTotalMinor: 5000,
    settings,
  }), LoyaltyPolicyError);
  assert.throws(() => calculateRedemption({
    requestedPoints: 51,
    balancePoints: 100,
    billTotalMinor: 5000,
    settings,
  }), /bill limit/);
});

test('redemption limit can be configured below the full bill amount', () => {
  const settings = validateLoyaltySettings({
    ...DEFAULT_LOYALTY_SETTINGS,
    maxRedemptionPercent: 20,
    bonusTiers: [],
  });
  assert.throws(() => calculateRedemption({
    requestedPoints: 11,
    balancePoints: 100,
    billTotalMinor: 5000,
    settings,
  }), /bill limit/);
  assert.deepEqual(calculateRedemption({
    requestedPoints: 10,
    balancePoints: 100,
    billTotalMinor: 5000,
    settings,
  }), { points: 10, discountMinor: 1000 });
});

test('phone lookup requires normalized international phone format', () => {
  assert.equal(normalizePhoneNumber('+91 98765-43210'), '+919876543210');
  assert.throws(() => normalizePhoneNumber('9876543210'), /international format/);
});

test('rejects invalid expiry, duplicate bonus thresholds and unsafe values', () => {
  assert.throws(() => validateLoyaltySettings({
    ...DEFAULT_LOYALTY_SETTINGS,
    expiryMonths: 0,
    bonusTiers: [],
  }), /Expiry/);
  assert.throws(() => validateLoyaltySettings({
    ...DEFAULT_LOYALTY_SETTINGS,
    bonusTiers: [
      { minimumSpendMinor: 50000, points: 5 },
      { minimumSpendMinor: 50000, points: 10 },
    ],
  }), /thresholds must be unique/);
  assert.throws(() => validateLoyaltySettings({
    ...DEFAULT_LOYALTY_SETTINGS,
    bonusTiers: [],
    maxRedemptionPercent: 101,
  }), /between 0 and 100/);
});
