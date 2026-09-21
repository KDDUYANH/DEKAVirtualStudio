import { describe, it } from 'node:test';
import assert from 'node:assert';
import { WebSocketSourceAdapter } from '../dist/adapters/websocketSourceAdapter.js';
import { AdapterManager } from '../dist/adapters/adapterManager.js';

describe('Source Discovery & Normalization (Zero-Mock)', () => {
  it('Initial status must be NO_SOURCE and not have fake/mock rounds', () => {
    const adapter = new WebSocketSourceAdapter({
      id: 'test-ws-01',
      name: 'Test Stream',
      type: 'WEBSOCKET',
      targetUrl: 'http://localhost',
      wsEndpoint: 'ws://127.0.0.1:9999',
      autoReconnect: false,
      maxReconnectAttempts: 1,
    });

    assert.strictEqual(adapter.getStatus(), 'NO_SOURCE');
    const output = adapter.getOutput();
    assert.strictEqual(output.latestGameState, null, 'Must NOT contain mock game state');
    assert.strictEqual(output.latestChatMessage, null, 'Must NOT contain fake chat messages');
  });

  it('Normalizes real game state messages correctly', (t, done) => {
    const adapter = new WebSocketSourceAdapter({
      id: 'test-ws-game',
      name: 'Game Stream',
      type: 'WEBSOCKET',
      targetUrl: 'http://localhost',
      wsEndpoint: 'ws://127.0.0.1:9998',
      autoReconnect: false,
      maxReconnectAttempts: 1,
    });

    const rawWsPayload = JSON.stringify({
      roundId: 'R-99821',
      countdown: 15,
      status: 'BETTING',
      dice: [3, 4, 6],
    });

    adapter.on('game-state', (normalized) => {
      assert.strictEqual(normalized.roundId, 'R-99821');
      assert.strictEqual(normalized.countdownSeconds, 15);
      assert.strictEqual(normalized.status, 'BETTING');
      assert.deepStrictEqual(normalized.result.raw.dice, [3, 4, 6]);
      done();
    });

    adapter.handleMessage(Buffer.from(rawWsPayload));
  });

  it('Normalizes chat messages with author, vip, and text correctly', (t, done) => {
    const adapter = new WebSocketSourceAdapter({
      id: 'test-ws-chat',
      name: 'Chat Stream',
      type: 'WEBSOCKET',
      targetUrl: 'http://localhost',
      wsEndpoint: 'ws://127.0.0.1:9997',
      autoReconnect: false,
      maxReconnectAttempts: 1,
    });

    const rawChatPayload = JSON.stringify({
      user: 'VipPlayer_88',
      msg: 'Chúc mừng anh em nổ hũ!',
      cmd: 'chat',
    });

    adapter.on('chat-message', (msg) => {
      assert.strictEqual(msg.username, 'VipPlayer_88');
      assert.strictEqual(msg.message, 'Chúc mừng anh em nổ hũ!');
      assert.strictEqual(msg.type, 'USER');
      done();
    });

    adapter.handleMessage(Buffer.from(rawChatPayload));
  });

  it('AdapterManager manages registration, health summary, and clean removal', async () => {
    const manager = new AdapterManager();

    const adapter = await manager.registerAdapter({
      id: 'ws-runtime-01',
      name: 'Live Chat Adapter',
      type: 'WEBSOCKET',
      targetUrl: 'http://localhost',
      wsEndpoint: 'ws://127.0.0.1:9996',
      autoReconnect: false,
      maxReconnectAttempts: 1,
    });

    assert.ok(adapter);
    assert.strictEqual(manager.getAdapter('ws-runtime-01'), adapter);

    const healthSummary = manager.getHealthSummary();
    assert.ok(healthSummary['ws-runtime-01']);

    const removed = await manager.removeAdapter('ws-runtime-01');
    assert.strictEqual(removed, true);
    assert.strictEqual(manager.getAdapter('ws-runtime-01'), undefined);

    await manager.shutdown();
  });
});
