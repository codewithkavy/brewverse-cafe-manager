const assert = require('node:assert/strict');
const net = require('node:net');
const { test } = require('node:test');
const { assertPortsAvailable } = require('../local-port-preflight.cjs');
function listener() {
  const server = net.createServer();
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}
const close = server => new Promise(resolve => server.close(resolve));

test('startup preflight rejects an occupied disposable port immediately', async () => {
  const server = await listener();
  try {
    await assert.rejects(assertPortsAvailable([server.address().port]), { code: 'EADDRINUSE' });
    assert.equal(server.listening, true);
  } finally { await close(server); }
});

test('post-cleanup preflight waits for a real listener to release its port', async () => {
  const server = await listener(), port = server.address().port;
  const release = setTimeout(() => server.close(), 80);
  try {
    await assertPortsAvailable([port], { waitForReleaseMs: 2000, retryDelayMs: 20 });
    assert.equal(server.listening, false);
  } finally {
    clearTimeout(release);
    if (server.listening) await close(server);
  }
});

test('post-cleanup preflight stops at its bound without terminating the listener', async () => {
  const server = await listener();
  try {
    await assert.rejects(assertPortsAvailable([server.address().port], { waitForReleaseMs: 80, retryDelayMs: 20 }), { code: 'EADDRINUSE' });
    assert.equal(server.listening, true);
  } finally { await close(server); }
});

test('invalid port errors are propagated rather than retried', async () => {
  await assert.rejects(assertPortsAvailable([-1], { waitForReleaseMs: 2000 }), { code: 'ERR_SOCKET_BAD_PORT' });
});
