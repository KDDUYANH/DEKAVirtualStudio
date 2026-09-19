import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { signJWT, verifyJWT, sha256Hex, timingSafeEqual, validStreamName, isoNoMillis } from '../src/index.js';

const env = {
  SESSION_SIGNING_KEY: 'test-signing-key-32-bytes-minimum!!',
  OPERATORS: '',
  MILLICAST_API_SECRET: 'never-leaves-the-server',
  ALLOWED_STREAM_PATTERN: 'deka-.*',
  PUBLISH_TOKEN_TTL_SECONDS: '3600',
};

test('JWT round trip and expiry', async () => {
  const now = Math.floor(Date.now() / 1000);
  const t = await signJWT({ sub: 'cam1', exp: now + 60 }, env.SESSION_SIGNING_KEY);
  assert.equal((await verifyJWT(t, env.SESSION_SIGNING_KEY)).sub, 'cam1');
  assert.equal(await verifyJWT(t, 'wrong-key'), null);
  assert.equal(await verifyJWT(t, env.SESSION_SIGNING_KEY, now + 61), null);
});

test('JWT rejects tampering and alg none', async () => {
  const now = Math.floor(Date.now() / 1000);
  const t = await signJWT({ sub: 'cam1', exp: now + 60 }, env.SESSION_SIGNING_KEY);
  const [h, b, s] = t.split('.');
  const forgedBody = Buffer.from(JSON.stringify({ sub: 'admin', exp: now + 60 })).toString('base64url');
  assert.equal(await verifyJWT(`${h}.${forgedBody}.${s}`, env.SESSION_SIGNING_KEY), null);
  const none = Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url');
  assert.equal(await verifyJWT(`${none}.${b}.`, env.SESSION_SIGNING_KEY), null);
});

test('helpers', async () => {
  assert.equal((await sha256Hex('abc')).slice(0, 8), 'ba7816bf');
  assert.ok(timingSafeEqual('abcd', 'abcd'));
  assert.ok(!timingSafeEqual('abcd', 'abce'));
  assert.ok(validStreamName('deka-studio-a', env.ALLOWED_STREAM_PATTERN));
  assert.ok(!validStreamName('other', env.ALLOWED_STREAM_PATTERN));
  assert.ok(!validStreamName('deka-a/../b', env.ALLOWED_STREAM_PATTERN));
  assert.match(isoNoMillis(new Date(0)), /^1970-01-01T00:00:00Z$/);
});

test('session: wrong key 401, right key issues token; publish-token calls Millicast with server secret', async () => {
  const hash = await sha256Hex('operator-key-1');
  const e = { ...env, OPERATORS: JSON.stringify({ cam1: hash }) };
  const bad = await worker.fetch(new Request('https://x/v1/session', { method: 'POST', body: JSON.stringify({ operatorID: 'cam1', operatorKey: 'nope' }) }), e);
  assert.equal(bad.status, 401);
  const ok = await worker.fetch(new Request('https://x/v1/session', { method: 'POST', body: JSON.stringify({ operatorID: 'cam1', operatorKey: 'operator-key-1' }) }), e);
  assert.equal(ok.status, 200);
  const { sessionToken, expiresAt } = await ok.json();
  assert.match(expiresAt, /Z$/);

  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, init });
    return new Response(JSON.stringify({ status: 'success', data: { id: 42, token: 'pub-token' } }), { status: 200 });
  };
  const noAuth = await worker.fetch(new Request('https://x/v1/publish-token', { method: 'POST', body: '{}' }), e);
  assert.equal(noAuth.status, 401);
  const res = await worker.fetch(new Request('https://x/v1/publish-token', {
    method: 'POST', headers: { authorization: `Bearer ${sessionToken}` }, body: JSON.stringify({ streamName: 'deka-studio-a' }),
  }), e);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.token, 'pub-token');
  assert.equal(body.tokenId, '42');
  assert.equal(calls[0].init.headers.authorization, 'Bearer never-leaves-the-server');
  assert.equal(JSON.parse(calls[0].init.body).expires, 3600);
  assert.ok(!JSON.stringify(body).includes('never-leaves-the-server'));

  const denied = await worker.fetch(new Request('https://x/v1/publish-token', {
    method: 'POST', headers: { authorization: `Bearer ${sessionToken}` }, body: JSON.stringify({ streamName: 'someone-else' }),
  }), e);
  assert.equal(denied.status, 400);

  const del = await worker.fetch(new Request('https://x/v1/publish-token/42', { method: 'DELETE', headers: { authorization: `Bearer ${sessionToken}` } }), e);
  assert.equal(del.status, 204);
  assert.equal(calls[1].init.method, 'DELETE');
});
