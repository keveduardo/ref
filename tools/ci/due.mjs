// Is Ref's TestFlight build close enough to expiry to replace?
//
//   node tools/ci/due.mjs [bundle id, default com.brisaloca.ref]
//
// ! WHY THIS EXISTS. Ref is built by Xcode on a GitHub macOS runner, not by
// xtool, so it cannot be in brisaloca-rebuild.timer's loop on kevg10 — and
// without this its builds would simply lapse after 90 days and the app would
// stop opening. Copied from brisaloca-ios tools/ci/rowing-due.mjs (Swim is the
// other app with this problem; both pass their own bundle id).
//
// Same rule, same code: `decide()` from needs-rebuild.mjs, so no two robots
// can disagree about what "due" means. Run by the `due` job of
// .github/workflows/ref.yml on a schedule; it writes `due=true|false` to
// $GITHUB_OUTPUT, and only `due=true` starts the macOS build and upload.
// A failure to ask exits non-zero — an unanswered question must not read as
// "not due".
import { appendFileSync } from 'node:fs';
import { loadKey, mintToken, findApp, listBuilds } from './asc.mjs';
import { decide } from './needs-rebuild.mjs';

const BUNDLE_ID = process.argv[2] || 'com.brisaloca.ref';

const token = await mintToken(loadKey());
const app = await findApp(token, BUNDLE_ID);
if (!app) throw new Error(`no App Store Connect record for ${BUNDLE_ID}`);

const verdict = decide(await listBuilds(token, app.id));
console.log(`${BUNDLE_ID}: ${verdict.rebuild ? 'due' : 'not due'} — ${verdict.reason}`);
if (process.env.GITHUB_OUTPUT) {
  appendFileSync(process.env.GITHUB_OUTPUT, `due=${verdict.rebuild}\n`);
}
