// Sign in with Apple — the token check, copied from soccer/src/apple.js
// (2026-09-25, with its tests) on 2026-10-04 for RefTime. Only the audience
// differs: RefTime's bundle id.
//
// The app's "Sign in with Apple" button hands back an identity token: a JWT
// Apple signed, naming the person by a stable `sub` and (when they allow it) an
// email. This file checks that token and nothing else.
//
// ! CHECKED HERE, NOT TRUSTED FROM THE APP. The signature against Apple's own
// published keys, the issuer, the audience (our bundle id — a token minted for
// another app is refused), the expiry, and the nonce the app committed to
// before asking Apple. A token that fails any of these is simply not a sign-in.

const ISSUER = 'https://appleid.apple.com';
const KEYS_URL = 'https://appleid.apple.com/auth/keys';
export const APPLE_AUDIENCE = 'com.brisaloca.ref';

let cachedKeys = null;   // { at, keys } — per isolate
const KEY_TTL_MS = 60 * 60 * 1000;

const b64urlBytes = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')
  + '='.repeat((4 - s.length % 4) % 4)), c => c.charCodeAt(0));
const b64urlJson = s => JSON.parse(new TextDecoder().decode(b64urlBytes(s)));

async function appleKeys(fetcher, force = false) {
  if (!force && cachedKeys && Date.now() - cachedKeys.at < KEY_TTL_MS) return cachedKeys.keys;
  const res = await fetcher(KEYS_URL);
  if (!res.ok) throw new Error(`Apple keys: ${res.status}`);
  const { keys } = await res.json();
  cachedKeys = { at: Date.now(), keys: keys || [] };
  return cachedKeys.keys;
}

export async function sha256Hex(s) {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * The person an Apple identity token names, or null if it is not a valid one.
 *
 * @param token  the JWT the app received from Apple
 * @param nonce  the RAW nonce the app generated; Apple put its SHA-256 in the token
 * @returns {{sub, email, emailVerified, privateRelay}|null}
 */
export async function verifyAppleToken(token, nonce, {
  fetcher = fetch, now = Math.floor(Date.now() / 1000), audience = APPLE_AUDIENCE,
} = {}) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3 || !nonce) return null;
  let header, claims;
  try { header = b64urlJson(parts[0]); claims = b64urlJson(parts[1]); } catch { return null; }
  if (header.alg !== 'RS256' || !header.kid) return null;

  // Apple rotates its keys; an unknown kid is worth one fresh fetch.
  let jwk = (await appleKeys(fetcher)).find(k => k.kid === header.kid);
  if (!jwk) jwk = (await appleKeys(fetcher, true)).find(k => k.kid === header.kid);
  if (!jwk) return null;

  const key = await crypto.subtle.importKey('jwk', jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  if (!ok) return null;

  if (claims.iss !== ISSUER) return null;
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!aud.includes(audience)) return null;
  if (!claims.exp || claims.exp <= now) return null;
  if (!claims.sub) return null;
  // The app sent Apple SHA-256(nonce) and sends us the nonce itself, so a
  // token lifted from elsewhere cannot be replayed without the secret half.
  if (claims.nonce !== await sha256Hex(nonce)) return null;

  const email = String(claims.email || '').trim().toLowerCase() || null;
  const flag = v => v === true || v === 'true';
  return {
    sub: String(claims.sub),
    email,
    emailVerified: flag(claims.email_verified),
    privateRelay: flag(claims.is_private_email) || /@privaterelay\.appleid\.com$/.test(email || ''),
  };
}

/** For tests: forget the cached keys. */
export function _resetAppleKeys() { cachedKeys = null; }

