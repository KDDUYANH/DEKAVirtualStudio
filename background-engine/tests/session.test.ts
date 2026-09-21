import test from 'node:test';
import assert from 'node:assert';
import { DeviceAuthManager } from '../src/auth/deviceAuth.js';

test('DeviceAuthManager - Persistent 24/7 Session & Token Refresh', async (t) => {
  const auth = new DeviceAuthManager();

  await t.test('1. Should register a new studio device with persistent and access tokens', () => {
    const reg = auth.registerDevice('STUDIO-PC-TEST-01', 'Operator PC 1', 'table-01');
    assert.ok(reg.persistentToken, 'Persistent token must be generated');
    assert.ok(reg.accessToken, 'Access token must be generated');
    assert.strictEqual(reg.session.deviceId, 'STUDIO-PC-TEST-01');
    assert.strictEqual(reg.session.status, 'online');
  });

  await t.test('2. Should verify a valid access token', () => {
    const reg = auth.registerDevice('STUDIO-PC-TEST-02', 'Operator PC 2', 'table-02');
    const verified = auth.verifyAccessToken(reg.accessToken);
    assert.ok(verified, 'Access token must be verified');
    assert.strictEqual(verified?.deviceId, 'STUDIO-PC-TEST-02');
    assert.strictEqual(verified?.tableId, 'table-02');
  });

  await t.test('3. Should perform silent token refresh using persistentToken', () => {
    const reg = auth.registerDevice('STUDIO-PC-TEST-03', 'Operator PC 3', 'table-03');
    const refreshed = auth.refreshAccessToken(reg.persistentToken);
    assert.ok(refreshed, 'Refresh must succeed');
    assert.ok(refreshed?.accessToken, 'New access token must be provided');
    assert.strictEqual(refreshed?.deviceId, 'STUDIO-PC-TEST-03');

    // Verify the newly issued token
    const verified = auth.verifyAccessToken(refreshed!.accessToken);
    assert.ok(verified, 'New access token must be valid');
    assert.strictEqual(verified?.deviceId, 'STUDIO-PC-TEST-03');
  });

  await t.test('4. Should reject invalid or malformed tokens', () => {
    const badVerified = auth.verifyAccessToken('invalid.jwt.token');
    assert.strictEqual(badVerified, null);

    const badRefreshed = auth.refreshAccessToken('invalid.persistent.token');
    assert.strictEqual(badRefreshed, null);
  });
});
