// DEKA token service — Cloudflare Worker (free tier is enough for a studio).
//
// Holds the ONLY copy of the Millicast API secret. The iPhone never sees it.
//
//   POST   /v1/session               {operatorID, operatorKey}  -> {sessionToken, expiresAt}
//   POST   /v1/publish-token         Bearer session, {streamName} -> {streamName, token, tokenId, apiUrl, expiresAt}
//   DELETE /v1/publish-token/:id     Bearer session              -> 204
//   GET    /v1/health                                            -> {ok:true}
//
// Secrets (wrangler secret put …): MILLICAST_API_SECRET, SESSION_SIGNING_KEY, OPERATORS
//   OPERATORS = JSON {"<operatorID>": "<sha256 hex of operatorKey>"}
// Vars (wrangler.toml): ALLOWED_STREAM_PATTERN, PUBLISH_TOKEN_TTL_SECONDS, SESSION_TTL_SECONDS

const MILLICAST_API = 'https://api.millicast.com/api/publish_token';
const DIRECTOR_PUBLISH = 'https://director.millicast.com/api/director/publish';

const enc = new TextEncoder();

// ---------- helpers (exported for tests) ----------

export function isoNoMillis(date) {
  // Swift's JSONDecoder .iso8601 does not accept fractional seconds.
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function b64urlDecode(str) {
  const s = str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4);
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function hmacKey(secret) {
  return crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export async function signJWT(payload, secret) {
  const header = b64url(enc.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(secret), enc.encode(`${header}.${body}`));
  return `${header}.${body}.${b64url(new Uint8Array(sig))}`;
}

export async function verifyJWT(token, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  const parts = (token || '').split('.');
  if (parts.length !== 3) return null;
  const [h, b, s] = parts;
  const header = JSON.parse(new TextDecoder().decode(b64urlDecode(h)));
  if (header.alg !== 'HS256') return null; // never accept "none" or other algs
  const ok = await crypto.subtle.verify('HMAC', await hmacKey(secret), b64urlDecode(s), enc.encode(`${h}.${b}`));
  if (!ok) return null;
  const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(b)));
  if (typeof payload.exp !== 'number' || payload.exp <= nowSeconds) return null;
  return payload;
}

export function validStreamName(name, pattern) {
  if (typeof name !== 'string' || name.length < 1 || name.length > 128) return false;
  if (!/^[A-Za-z0-9._-]+$/.test(name)) return false;
  return new RegExp(`^(?:${pattern || '.*'})$`).test(name);
}

const json = (status, obj) =>
  new Response(obj === undefined ? null : JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });

async function authed(request, env) {
  const auth = request.headers.get('authorization') || '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  return verifyJWT(token, env.SESSION_SIGNING_KEY);
}

// ---------- handlers ----------

async function createSession(request, env) {
  const body = await request.json().catch(() => ({}));
  const { operatorID, operatorKey } = body;
  const operators = JSON.parse(env.OPERATORS || '{}');
  const expected = operators[operatorID];
  const actual = typeof operatorKey === 'string' ? await sha256Hex(operatorKey) : '';
  if (!expected || !timingSafeEqual(expected, actual)) return json(401, { error: 'invalid operator credentials' });

  const ttl = Number(env.SESSION_TTL_SECONDS || 43200);
  const exp = Math.floor(Date.now() / 1000) + ttl;
  const sessionToken = await signJWT({ sub: operatorID, scope: 'publish', exp, iat: exp - ttl }, env.SESSION_SIGNING_KEY);
  return json(200, { sessionToken, expiresAt: isoNoMillis(new Date(exp * 1000)) });
}

async function createPublishToken(request, env, session) {
  const { streamName } = await request.json().catch(() => ({}));
  if (!validStreamName(streamName, env.ALLOWED_STREAM_PATTERN)) return json(400, { error: 'stream name not allowed' });

  const ttl = Number(env.PUBLISH_TOKEN_TTL_SECONDS || 14400);
  const res = await fetch(MILLICAST_API, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      authorization: `Bearer ${env.MILLICAST_API_SECRET}`,
    },
    body: JSON.stringify({
      label: `deka-${session.sub}-${Date.now()}`,
      streams: [{ streamName, isRegex: false }],
      expires: ttl,
    }),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok || !payload?.data?.token) {
    return json(502, { error: 'millicast token creation failed', status: res.status });
  }
  return json(200, {
    streamName,
    token: payload.data.token,
    tokenId: payload.data.id != null ? String(payload.data.id) : null,
    apiUrl: DIRECTOR_PUBLISH,
    expiresAt: isoNoMillis(new Date(Date.now() + ttl * 1000)),
  });
}

async function revokePublishToken(id, env) {
  if (!/^\d+$/.test(id)) return json(400, { error: 'bad token id' });
  const res = await fetch(`${MILLICAST_API}/${id}`, {
    method: 'DELETE',
    headers: { accept: 'application/json', authorization: `Bearer ${env.MILLICAST_API_SECRET}` },
  });
  return res.ok ? new Response(null, { status: 204 }) : json(502, { error: 'revoke failed', status: res.status });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');
    try {
      if (request.method === 'GET' && path === '/v1/health') return json(200, { ok: true });
      if (request.method === 'POST' && path === '/v1/session') return await createSession(request, env);

      const session = await authed(request, env);
      if (!session) return json(401, { error: 'unauthorized' });

      if (request.method === 'POST' && path === '/v1/publish-token') return await createPublishToken(request, env, session);
      const m = path.match(/^\/v1\/publish-token\/([^/]+)$/);
      if (request.method === 'DELETE' && m) return await revokePublishToken(m[1], env);
      return json(404, { error: 'not found' });
    } catch (e) {
      return json(500, { error: 'internal error' }); // never echo secrets or stack traces
    }
  },
};
