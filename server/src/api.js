// RefTime's API: sign in (Apple or Google), back up and sync matches and
// teams, delete the account. Every handler takes its database and its token
// verifiers as arguments, so the tests drive the real code on node:sqlite.

import { verifyAppleToken, sha256Hex } from './apple.js';
import { verifyGoogleToken } from './google.js';

export const KINDS = ['match', 'team'];
export const MAX_BODY = 256 * 1024;   // one item; a match is a few KB
export const MAX_BATCH = 200;

export const json = (body, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

const nowIso = () => new Date().toISOString();

function randomKey() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** The user a device key belongs to, or null. Bumps the key's last use. */
export async function authenticate(db, request) {
  const header = request.headers.get('authorization') || '';
  const key = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!key) return null;
  const hash = await sha256Hex(key);
  const row = await db.prepare('SELECT user_id FROM device_keys WHERE key_hash = ?').bind(hash).first();
  if (!row) return null;
  await db.prepare('UPDATE device_keys SET last_used_at = ? WHERE key_hash = ?').bind(nowIso(), hash).run();
  return row.user_id;
}

/** Sign in: a provider's verified identity in, a device key out. */
async function signIn(db, provider, who) {
  let user = await db.prepare('SELECT id, email FROM users WHERE provider = ? AND subject = ?')
    .bind(provider, who.sub).first();
  if (!user) {
    user = { id: crypto.randomUUID(), email: who.email };
    await db.prepare('INSERT INTO users (id, provider, subject, email, created_at) VALUES (?, ?, ?, ?, ?)')
      .bind(user.id, provider, who.sub, who.email, nowIso()).run();
  } else if (!user.email && who.email) {
    // Apple shares the email on the first sign-in only; keep it when it comes.
    await db.prepare('UPDATE users SET email = ? WHERE id = ?').bind(who.email, user.id).run();
    user.email = who.email;
  }
  const key = randomKey();
  const at = nowIso();
  await db.prepare('INSERT INTO device_keys (key_hash, user_id, created_at, last_used_at) VALUES (?, ?, ?, ?)')
    .bind(await sha256Hex(key), user.id, at, at).run();
  return json({ key, provider, email: user.email || null });
}

export async function appleSignIn(db, body, { verify = verifyAppleToken } = {}) {
  const who = await verify(body?.identity_token, body?.nonce);
  if (!who) return json({ error: 'That Apple sign-in could not be checked. Try again.' }, 401);
  return signIn(db, 'apple', who);
}

export async function googleSignIn(db, body, clientID, { verify = verifyGoogleToken } = {}) {
  if (!clientID) return json({ error: 'Google sign-in is not set up yet.' }, 503);
  const who = await verify(body?.id_token, clientID);
  if (!who) return json({ error: 'That Google sign-in could not be checked. Try again.' }, 401);
  return signIn(db, 'google', who);
}

/** Changes since `since` (server ms): every item touched after it. */
export async function listItems(db, userID, since) {
  const after = Number.isFinite(since) ? since : 0;
  const { results } = await db.prepare(
    'SELECT kind, id, body, deleted, updated_at FROM items WHERE user_id = ? AND updated_at > ? ORDER BY updated_at',
  ).bind(userID, after).all();
  const items = results.map(r => ({
    kind: r.kind, id: r.id, deleted: !!r.deleted, updatedAt: r.updated_at,
    body: r.body ? JSON.parse(r.body) : null,
  }));
  const latest = items.reduce((m, i) => Math.max(m, i.updatedAt), after);
  return json({ items, latest });
}

/** Upserts a batch. Each item: {kind, id, body} or {kind, id, deleted: true}. */
export async function putItems(db, userID, body, now = Date.now()) {
  const items = Array.isArray(body?.items) ? body.items : null;
  if (!items) return json({ error: 'Expected {items: [...]}.' }, 400);
  if (items.length > MAX_BATCH) return json({ error: `At most ${MAX_BATCH} items at a time.` }, 413);
  const statements = [];
  for (const item of items) {
    if (!KINDS.includes(item?.kind) || typeof item?.id !== 'string' || !/^[0-9A-Fa-f-]{36}$/.test(item.id)) {
      return json({ error: 'Each item needs a kind (match or team) and a UUID id.' }, 400);
    }
    const text = item.deleted ? null : JSON.stringify(item.body ?? null);
    if (text && text.length > MAX_BODY) return json({ error: `Item ${item.id} is too large.` }, 413);
    if (!item.deleted && item.body == null) return json({ error: `Item ${item.id} has no body.` }, 400);
    statements.push(db.prepare(
      `INSERT INTO items (user_id, kind, id, body, deleted, updated_at) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT (user_id, kind, id) DO UPDATE SET body = excluded.body, deleted = excluded.deleted,
         updated_at = excluded.updated_at`,
    ).bind(userID, item.kind, item.id.toUpperCase(), text, item.deleted ? 1 : 0, now));
  }
  if (statements.length) await db.batch(statements);
  return json({ saved: statements.length, at: now });
}

/** Deletes the account and everything in it — Apple requires the button. */
export async function deleteAccount(db, userID) {
  await db.batch([
    db.prepare('DELETE FROM items WHERE user_id = ?').bind(userID),
    db.prepare('DELETE FROM device_keys WHERE user_id = ?').bind(userID),
    db.prepare('DELETE FROM users WHERE id = ?').bind(userID),
  ]);
  return json({ deleted: true });
}

/** Signs this device out: its key stops working. */
export async function signOut(db, request) {
  const header = request.headers.get('authorization') || '';
  const key = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (key) await db.prepare('DELETE FROM device_keys WHERE key_hash = ?').bind(await sha256Hex(key)).run();
  return json({ signedOut: true });
}
