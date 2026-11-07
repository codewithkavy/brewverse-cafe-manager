const net = require('node:net');
const { setTimeout: delay } = require('node:timers/promises');

function probePort(port) {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => server.close(resolve));
  });
}

async function assertPortsAvailable(ports, { waitForReleaseMs = 0, retryDelayMs = 100 } = {}) {
  const deadline = Date.now() + waitForReleaseMs;
  for (const port of ports) {
    while (true) {
      try {
        await probePort(port);
        break;
      } catch (error) {
        // Never hide unknown failures or terminate an unrecognized listener.
        if (error.code !== 'EADDRINUSE' || Date.now() >= deadline) throw error;
        await delay(Math.min(retryDelayMs, deadline - Date.now()));
      }
    }
  }
}

module.exports = { assertPortsAvailable };
