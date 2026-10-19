#!/usr/bin/env node
// Read-only CLI wrapper for a caller-supplied JSON snapshot. Never connects to Firebase.
const fs = require('node:fs');
const path = require('node:path');
const { preflightLegacyMigration } = require('../src/legacy_migration_preflight');

function usage() {
  process.stderr.write(
    'Usage: node scripts/preflight_legacy_migration.js <input.json|->\n' +
    'Use - to read JSON from stdin. This command does not access Firebase.\n',
  );
}

const [inputPath, ...extraArgs] = process.argv.slice(2);
if (inputPath === '--help' || inputPath === '-h') {
  usage();
  process.exit(0);
}
if (!inputPath || extraArgs.length > 0) {
  usage();
  process.exit(64);
}

let source;
try {
  source = inputPath === '-'
    ? fs.readFileSync(0, 'utf8')
    : fs.readFileSync(path.resolve(inputPath), 'utf8');
} catch (error) {
  process.stderr.write(`Could not read supplied input: ${error.message}\n`);
  process.exit(66);
}

let input;
try {
  input = JSON.parse(source);
} catch (error) {
  process.stderr.write(`Supplied input is not valid JSON: ${error.message}\n`);
  process.exit(65);
}

const result = preflightLegacyMigration(input);
process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
if (!result.safeToReview) process.exitCode = 2;
