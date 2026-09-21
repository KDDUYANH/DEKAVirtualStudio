import test from 'node:test';
import assert from 'node:assert';
import { ServerWatchdog } from '../src/telemetry/watchdogServer.js';

test('ServerWatchdog - Heartbeat & Degradation Telemetry', async (t) => {
  const watchdog = new ServerWatchdog();
  const tableId = 'test-table-telemetry';

  await t.test('1. Record heartbeat from client and store metrics', () => {
    const recorded = watchdog.recordHeartbeat({
      tableId,
      deviceId: 'STUDIO-VMIX-01',
      fps: 59.8,
      droppedFrames: 2,
      uptimeSeconds: 120,
      activeLayersCount: 6,
    });

    assert.strictEqual(recorded.tableId, tableId);
    assert.strictEqual(recorded.networkStatus, 'online');
    assert.strictEqual(recorded.droppedFrames, 2);
  });

  await t.test('2. Query telemetry data', () => {
    const data = watchdog.getTelemetry(tableId);
    assert.strictEqual(data.tableId, tableId);
    assert.strictEqual(data.networkStatus, 'online');
    assert.ok(data.lastHeartbeat > 0);
  });

  await t.test('3. Return offline status for nonexistent or timed-out tables', () => {
    const unknown = watchdog.getTelemetry('table-unknown');
    assert.strictEqual(unknown.networkStatus, 'offline');
    assert.strictEqual(unknown.fps, 0);
  });
});
