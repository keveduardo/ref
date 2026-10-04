// The public pages: what App Store Connect links to (privacy policy, support)
// and a plain home page. Plain HTML, no scripts, no tracking.

const page = (title, body) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>
  :root { color-scheme: light dark; --ink: #1d1d1f; --muted: #6e6e73; --bg: #fbfbfd; --accent: #1f7a3a; }
  @media (prefers-color-scheme: dark) { :root { --ink: #f5f5f7; --muted: #a1a1a6; --bg: #111; --accent: #4cc26a; } }
  body { font: 17px/1.55 -apple-system, system-ui, sans-serif; color: var(--ink); background: var(--bg);
         max-width: 40rem; margin: 0 auto; padding: 2rem 1rem 4rem; }
  h1 { font-size: 1.9rem; margin-bottom: .2rem; } h2 { font-size: 1.15rem; margin-top: 2rem; }
  p.lede { color: var(--muted); margin-top: 0; } a { color: var(--accent); }
  footer { margin-top: 3rem; color: var(--muted); font-size: .9rem; }
</style></head><body>${body}
<footer><a href="/">RefTime</a> · <a href="/privacy">Privacy</a> · <a href="/support">Support</a></footer>
</body></html>`;

export const homePage = () => page('RefTime', `
<h1>RefTime</h1>
<p class="lede">A soccer referee's watch and phone, together.</p>
<p>The Apple Watch runs the match — the clock, the score, cards and
substitutions, quarter breaks and half-time, with a buzz for each — while the
phone sets matches up and keeps the reports. Presets follow AYSO's rules for
each age group.</p>`);

export const privacyPage = () => page('RefTime — Privacy', `
<h1>Privacy</h1>
<p class="lede">Last updated 4 October 2026.</p>

<h2>Without an account</h2>
<p>Everything stays on your iPhone and Apple Watch: your matches, teams,
reports and the workout. Nothing is sent to us.</p>

<h2>Health and location</h2>
<p>With your permission, the watch records a match as a workout in Apple
Health (heart rate, active energy, steps, distance and the route). That data
stays on your devices and in Apple Health. It is <strong>never</strong> sent
to our server, sold, shared or used for advertising — including when you sign
in.</p>

<h2>If you sign in</h2>
<p>Signing in (with Apple or Google) is optional and only backs up your
matches and teams so they survive a new phone. We then store:</p>
<ul>
  <li>the account identifier Apple or Google gives us, and the email address
      if you chose to share it;</li>
  <li>your matches (teams, kick-off, timeline of goals, cards and
      substitutions) and your team sheets (names and shirt numbers) —
      without any health numbers or routes.</li>
</ul>
<p>It is stored on Cloudflare's infrastructure and used only to give it back
to you. There are no ads, analytics or trackers.</p>

<h2>Deleting your data</h2>
<p>In the app, Settings › Account › <strong>Delete account</strong> deletes
your account and everything backed up, immediately. Deleting the app deletes
what is on your devices.</p>

<h2>Contact</h2>
<p><a href="mailto:kevinamaya@gmail.com">kevinamaya@gmail.com</a></p>`);

export const supportPage = () => page('RefTime — Support', `
<h1>Support</h1>
<p class="lede">Questions, bugs or ideas for RefTime.</p>
<p>Email <a href="mailto:kevinamaya@gmail.com">kevinamaya@gmail.com</a> and
include what you were doing, which watch and iPhone you have, and a
screenshot if you can.</p>
<h2>Common questions</h2>
<p><strong>The watch doesn't buzz with my wrist down.</strong> Allow Health
access when RefTime asks — the workout is what keeps the app running with your
wrist down.</p>
<p><strong>A match I set up isn't on the watch.</strong> Open RefTime on the
iPhone with the watch nearby; matches travel automatically.</p>
<p><strong>I recorded something by mistake.</strong> On the watch, Record ›
Undo takes back the last incident; a half ended by mistake can be resumed from
the half-time screen.</p>`);
