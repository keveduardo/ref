// The token checks run for real against a key pair made here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyAppleToken, sha256Hex, _resetAppleKeys, APPLE_AUDIENCE } from '../src/apple.js';
import { verifyGoogleToken, _resetGoogleKeys } from '../src/google.js';
import { fakeProvider } from './helpers.mjs';

const NOW = 1_800_000_000;
const provider = await fakeProvider();
const nonce = 'raw-nonce-123';

const appleClaims = async (extra = {}) => ({
  iss: 'https://appleid.apple.com', aud: APPLE_AUDIENCE, exp: NOW + 600, iat: NOW,
  sub: '001.abc', email: 'Ref@Example.com', email_verified: 'true',
  nonce: await sha256Hex(nonce), ...extra,
});

test('a good Apple token names its person', async () => {
  _resetAppleKeys();
  const who = await verifyAppleToken(await provider.sign(await appleClaims()), nonce,
    { fetcher: provider.fetcher, now: NOW });
  assert.equal(who.sub, '001.abc');
  assert.equal(who.email, 'ref@example.com');
});

test('the audience is RefTime — a token for another app is refused', async () => {
  _resetAppleKeys();
  assert.equal(APPLE_AUDIENCE, 'com.brisaloca.ref');
  const token = await provider.sign(await appleClaims({ aud: 'com.brisaloca.soccer' }));
  assert.equal(await verifyAppleToken(token, nonce, { fetcher: provider.fetcher, now: NOW }), null);
});

test('expired, wrong nonce, forged signature: all refused', async () => {
  _resetAppleKeys();
  const opts = { fetcher: provider.fetcher, now: NOW };
  assert.equal(await verifyAppleToken(await provider.sign(await appleClaims({ exp: NOW - 1 })), nonce, opts), null);
  assert.equal(await verifyAppleToken(await provider.sign(await appleClaims()), 'other', opts), null);
  const other = await fakeProvider();
  assert.equal(await verifyAppleToken(await other.sign(await appleClaims()), nonce, opts), null);
});

test('Google: right client id passes, wrong one or none does not', async () => {
  _resetGoogleKeys();
  const claims = { iss: 'https://accounts.google.com', aud: 'client-1', exp: NOW + 600, sub: 'g-1',
    email: 'ref@example.com', email_verified: true };
  const token = await provider.sign(claims);
  const opts = { fetcher: provider.fetcher, now: NOW };
  assert.equal((await verifyGoogleToken(token, 'client-1', opts)).sub, 'g-1');
  assert.equal(await verifyGoogleToken(token, 'client-2', opts), null);
  assert.equal(await verifyGoogleToken(token, '', opts), null);
});
