const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

function isolatedRuntimeTemp(directory, inheritedEnv = process.env) {
  const root = path.resolve(directory);
  const tempDirectory = fs.mkdtempSync(path.join(root, 'runtime-temp-'));
  assert(tempDirectory.startsWith(root + path.sep), 'Runtime temp escaped evidence directory');
  const env = { ...inheritedEnv };
  // Remove case variants as Windows environment names are case-insensitive.
  for (const key of Object.keys(env)) {
    if (/^(TEMP|TMP|TMPDIR)$/i.test(key)) delete env[key];
  }
  Object.assign(env, { TEMP: tempDirectory, TMP: tempDirectory, TMPDIR: tempDirectory });
  return { env, tempDirectory };
}

module.exports = { isolatedRuntimeTemp };
