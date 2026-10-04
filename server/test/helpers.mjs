// A D1 stand-in on node:sqlite, with the real migration — enough of D1's
// surface (prepare/bind/first/all/run, batch) for the handlers.
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

export function freshDB() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec('PRAGMA foreign_keys = ON;');
  sqlite.exec(readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8'));
  const prepare = (sql) => {
    let args = [];
    const statement = {
      bind(...a) { args = a; return statement; },
      async first() { return sqlite.prepare(sql).get(...args) ?? null; },
      async all() { return { results: sqlite.prepare(sql).all(...args) }; },
      async run() { sqlite.prepare(sql).run(...args); return { success: true }; },
    };
    return statement;
  };
  return {
    sqlite,
    prepare,
    async batch(statements) { for (const s of statements) await s.run(); },
  };
}

const b64url = bytes => Buffer.from(bytes).toString('base64url');

/** A key pair served as a provider's JWKS, and a signer for its tokens. */
export async function fakeProvider(kid = 'k1') {
  const pair = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true, ['sign', 'verify']);
  const jwk = { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid, alg: 'RS256', use: 'sig' };
  const fetcher = async () => new Response(JSON.stringify({ keys: [jwk] }));
  async function sign(claims, { key = pair.privateKey, headerKid = kid } = {}) {
    const head = b64url(JSON.stringify({ alg: 'RS256', kid: headerKid }));
    const body = b64url(JSON.stringify(claims));
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${head}.${body}`));
    return `${head}.${body}.${b64url(new Uint8Array(sig))}`;
  }
  return { fetcher, sign, pair };
}
