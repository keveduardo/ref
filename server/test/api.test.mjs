// The API end to end through the router, on node:sqlite with the real
// migration; the token check is stubbed here (tokens.test.mjs covers it).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../src/index.js';
import { freshDB } from './helpers.mjs';

const verify = async (token) => (token === 'good' ? { sub: 'apple-1', email: 'ref@example.com' } : null);
const deps = { verify };
const MATCH = '11111111-2222-4333-8444-555555555555';
const TEAM = 'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE';

function call(env, method, path, { body, key } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (key) headers.authorization = `Bearer ${key}`;
  return handle(new Request(`https://reftime.brisaloca.com${path}`,
    { method, headers, body: body ? JSON.stringify(body) : undefined }), env, deps);
}

async function signedIn(env) {
  const res = await call(env, 'POST', '/v1/auth/apple', { body: { identity_token: 'good', nonce: 'n' } });
  assert.equal(res.status, 200);
  return (await res.json()).key;
}

test('the public pages are served', async () => {
  const env = { DB: freshDB() };
  for (const path of ['/', '/privacy', '/support']) {
    const res = await call(env, 'GET', path);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type'), /text\/html/);
  }
  assert.match(await (await call(env, 'GET', '/privacy')).text(), /never<\/strong> sent/);
});

test('a bad Apple token is a 401 and makes no account', async () => {
  const env = { DB: freshDB() };
  const res = await call(env, 'POST', '/v1/auth/apple', { body: { identity_token: 'bad', nonce: 'n' } });
  assert.equal(res.status, 401);
  assert.equal(env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM users').get().n, 0);
});

test('signing in twice is one account with two device keys', async () => {
  const env = { DB: freshDB() };
  const a = await signedIn(env);
  const b = await signedIn(env);
  assert.notEqual(a, b);
  assert.equal(env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM users').get().n, 1);
  assert.equal(env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM device_keys').get().n, 2);
  // Only hashes are stored.
  assert.equal(env.DB.sqlite.prepare('SELECT COUNT(*) AS n FROM device_keys WHERE key_hash = ?').get(a).n, 0);
});

test('items go up, come back since a point, and a deletion travels', async () => {
  const env = { DB: freshDB() };
  const key = await signedIn(env);
  const put = await call(env, 'PUT', '/v1/items', { key, body: { items: [
    { kind: 'match', id: MATCH, body: { setup: { competition: 'AYSO 10U Girls' } } },
    { kind: 'team', id: TEAM, body: { team: { name: 'Sharks' } } },
  ] } });
  assert.equal(put.status, 200);
  const all = await (await call(env, 'GET', '/v1/items?since=0', { key })).json();
  assert.equal(all.items.length, 2);
  assert.equal(all.items.find(i => i.kind === 'match').body.setup.competition, 'AYSO 10U Girls');

  await new Promise(r => setTimeout(r, 5));
  await call(env, 'PUT', '/v1/items', { key, body: { items: [{ kind: 'match', id: MATCH, deleted: true }] } });
  const since = await (await call(env, 'GET', `/v1/items?since=${all.latest}`, { key })).json();
  assert.deepEqual(since.items.map(i => [i.kind, i.deleted, i.body]), [['match', true, null]]);
});

test('one account cannot see another', async () => {
  const env = { DB: freshDB() };
  const mine = await signedIn(env);
  await call(env, 'PUT', '/v1/items', { key: mine, body: { items: [{ kind: 'team', id: TEAM, body: { a: 1 } }] } });
  const otherDeps = { verify: async () => ({ sub: 'apple-2', email: null }) };
  const res = await handle(new Request('https://x/v1/auth/apple', { method: 'POST',
    body: JSON.stringify({ identity_token: 'x', nonce: 'n' }) }), env, otherDeps);
  const theirs = (await res.json()).key;
  const seen = await (await call(env, 'GET', '/v1/items', { key: theirs })).json();
  assert.equal(seen.items.length, 0);
});

test('bad requests are refused', async () => {
  const env = { DB: freshDB() };
  const key = await signedIn(env);
  assert.equal((await call(env, 'GET', '/v1/items')).status, 401);
  assert.equal((await call(env, 'GET', '/v1/items', { key: 'nope' })).status, 401);
  assert.equal((await call(env, 'PUT', '/v1/items', { key, body: { items: [{ kind: 'photo', id: TEAM, body: {} }] } })).status, 400);
  assert.equal((await call(env, 'PUT', '/v1/items', { key, body: { items: [{ kind: 'team', id: 'x', body: {} }] } })).status, 400);
  const big = { kind: 'team', id: TEAM, body: { blob: 'x'.repeat(300 * 1024) } };
  assert.equal((await call(env, 'PUT', '/v1/items', { key, body: { items: [big] } })).status, 413);
});

test('Google is off until its client id is set', async () => {
  const env = { DB: freshDB() };
  assert.equal((await call(env, 'POST', '/v1/auth/google', { body: { id_token: 'x' } })).status, 503);
  assert.deepEqual(await (await call(env, 'GET', '/v1/auth/config')).json(), { apple: true, google: false });
});

test('sign out kills this key; delete account removes everything', async () => {
  const env = { DB: freshDB() };
  const a = await signedIn(env);
  const b = await signedIn(env);
  await call(env, 'PUT', '/v1/items', { key: a, body: { items: [{ kind: 'team', id: TEAM, body: { a: 1 } }] } });
  assert.equal((await call(env, 'DELETE', '/v1/session', { key: a })).status, 200);
  assert.equal((await call(env, 'GET', '/v1/items', { key: a })).status, 401);
  assert.equal((await call(env, 'DELETE', '/v1/account', { key: b })).status, 200);
  for (const table of ['users', 'device_keys', 'items']) {
    assert.equal(env.DB.sqlite.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n, 0, table);
  }
});
