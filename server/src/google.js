// Sign in with Google — the same shape as apple.js: a Google ID token (a JWT
// Google signed) checked against Google's published keys, the issuer, the
// audience (RefTime's own OAuth client id, from the environment) and the
// expiry. Nothing about the token is trusted from the app.
//
// The client id is configuration, not code: until GOOGLE_CLIENT_ID is set,
// Google sign-in answers 503 and the app does not offer it.

const ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];
const KEYS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

let cachedKeys = null;
const KEY_TTL_MS = 60 * 60 * 1000;

const b64urlBytes = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')
  + '='.repeat((4 - s.length % 4) % 4)), c => c.charCodeAt(0));
const b64urlJson = s => JSON.parse(new TextDecoder().decode(b64urlBytes(s)));

async function googleKeys(fetcher, force = false) {
  if (!force && cachedKeys && Date.now() - cachedKeys.at < KEY_TTL_MS) return cachedKeys.keys;
  const res = await fetcher(KEYS_URL);
  if (!res.ok) throw new Error(`Google keys: ${res.status}`);
  const { keys } = await res.json();
  cachedKeys = { at: Date.now(), keys: keys || [] };
  return cachedKeys.keys;
}

/** The person a Google ID token names, or null if it is not a valid one. */
export async function verifyGoogleToken(token, audience, {
  fetcher = fetch, now = Math.floor(Date.now() / 1000),
} = {}) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3 || !audience) return null;
  let header, claims;
  try { header = b64urlJson(parts[0]); claims = b64urlJson(parts[1]); } catch { return null; }
  if (header.alg !== 'RS256' || !header.kid) return null;

  let jwk = (await googleKeys(fetcher)).find(k => k.kid === header.kid);
  if (!jwk) jwk = (await googleKeys(fetcher, true)).find(k => k.kid === header.kid);
  if (!jwk) return null;

  const key = await crypto.subtle.importKey('jwk', jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlBytes(parts[2]),
    new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
  if (!ok) return null;

  if (!ISSUERS.includes(claims.iss)) return null;
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!aud.includes(audience)) return null;
  if (!claims.exp || claims.exp <= now) return null;
  if (!claims.sub) return null;
  const email = String(claims.email || '').trim().toLowerCase() || null;
  return { sub: String(claims.sub), email, emailVerified: claims.email_verified === true || claims.email_verified === 'true' };
}

export function _resetGoogleKeys() { cachedKeys = null; }
