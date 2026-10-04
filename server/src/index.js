// RefTime's server: reftime.brisaloca.com. The public pages App Store
// Connect links to, and the optional backup API the app signs in to.
// See ../../SCOPE.md, "Optional sign-in".

import { homePage, privacyPage, supportPage } from './pages.js';
import {
  json, authenticate, appleSignIn, googleSignIn, listItems, putItems, deleteAccount, signOut,
} from './api.js';

const html = (body) => new Response(body, {
  headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=300' },
});

async function readJson(request) {
  try { return await request.json(); } catch { return null; }
}

export async function handle(request, env, deps = {}) {
  const url = new URL(request.url);
  const { pathname } = url;
  const method = request.method;
  const db = env.DB;

  if (method === 'GET' && pathname === '/') return html(homePage());
  if (method === 'GET' && pathname === '/privacy') return html(privacyPage());
  if (method === 'GET' && pathname === '/support') return html(supportPage());

  if (pathname === '/v1/auth/apple' && method === 'POST') {
    return appleSignIn(db, await readJson(request), deps);
  }
  if (pathname === '/v1/auth/google' && method === 'POST') {
    return googleSignIn(db, await readJson(request), env.GOOGLE_CLIENT_ID, deps);
  }
  if (pathname === '/v1/auth/config' && method === 'GET') {
    // What the app may offer: Google only once it has a client id here.
    return json({ apple: true, google: !!env.GOOGLE_CLIENT_ID });
  }

  if (pathname.startsWith('/v1/')) {
    const userID = await authenticate(db, request);
    if (!userID) return json({ error: 'Sign in again.' }, 401);

    if (pathname === '/v1/items' && method === 'GET') {
      return listItems(db, userID, Number(url.searchParams.get('since') || 0));
    }
    if (pathname === '/v1/items' && method === 'PUT') {
      return putItems(db, userID, await readJson(request));
    }
    if (pathname === '/v1/session' && method === 'DELETE') return signOut(db, request);
    if (pathname === '/v1/account' && method === 'DELETE') return deleteAccount(db, userID);
  }

  return json({ error: 'Not found.' }, 404);
}

export default {
  fetch: (request, env) => handle(request, env),
};
