// Turn on a capability for an app's App ID, and retire its App Store profile so
// the next build's profile carries the matching entitlement.
//
//   node tools/ci/enable-capability.mjs push com.brisaloca.homecare [com.brisaloca.soccer ...]
//   node tools/ci/enable-capability.mjs apple-sign-in com.brisaloca.soccer
//   node tools/ci/enable-capability.mjs healthkit com.brisaloca.hub
//   node tools/ci/enable-capability.mjs healthkit com.brisaloca.hub --dry-run
//
// Renamed from enable-push.mjs on 2026-09-27, when HealthKit became the third
// capability: the old name had stopped describing the job two capabilities ago.
// The interface changed with it — "which capability" is a required argument
// rather than an optional flag that defaulted to push — because a script that
// silently assumes one capability is how the wrong one gets switched on.
//
// ! Why the profile goes too. distsign takes the signature's entitlements from
// the profile (distsign.mjs PLIST_PY), so a capability reaches a build only
// through a profile issued AFTER it. Apple usually marks the old one invalid,
// which ensureProfile already replaces; deleting it here makes that certain
// rather than usual. The next `rebuild.mjs` issues a fresh one.
//
// Idempotent: a capability already on is reported and left alone.
import { loadKey, mintToken, api } from './asc.mjs';

/// Apple's capabilityType strings, and the one that needs settings. Sign in
/// with Apple must say which App ID is the primary one for consent; each of
/// ours stands alone. HealthKit needs nothing extra — `HEALTHKIT_RECORDS` is
/// the clinical-records variant and is deliberately not this.
const CAPABILITIES = {
  push: { type: 'PUSH_NOTIFICATIONS', what: 'push' },
  'apple-sign-in': {
    type: 'APPLE_ID_AUTH',
    what: 'Sign in with Apple',
    settings: [{ key: 'APPLE_ID_AUTH_APP_CONSENT', options: [{ key: 'PRIMARY_APP_CONSENT' }] }],
  },
  healthkit: { type: 'HEALTHKIT', what: 'HealthKit' },
};

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const [name, ...ids] = argv.filter((a) => !a.startsWith('--'));
const capability = CAPABILITIES[name];

if (!capability || !ids.length) {
  console.error('usage: enable-capability.mjs <' + Object.keys(CAPABILITIES).join('|')
    + '> <bundle id>... [--dry-run]');
  process.exit(2);
}

const token = await mintToken(loadKey());
for (const identifier of ids) {
  const found = await api(`/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=200&include=bundleIdCapabilities`, { token });
  // Exact match: the filter also returns xtool's own XTL-… App IDs.
  const record = (found.data || []).find((b) => b.attributes.identifier === identifier);
  if (!record) { console.log(`${identifier}: no App ID registered — skipped`); continue; }

  const caps = (found.included || []).filter((i) => i.type === 'bundleIdCapabilities'
    && (record.relationships?.bundleIdCapabilities?.data || []).some((d) => d.id === i.id));

  if (caps.some((c) => c.attributes.capabilityType === capability.type)) {
    console.log(`${identifier}: ${capability.what} already on`);
    continue;
  }

  if (dryRun) {
    console.log(`${identifier}: would turn on ${capability.what} (${capability.type}) and retire its App Store profile`);
    continue;
  }

  await api('/v1/bundleIdCapabilities', { token, method: 'POST', body: { data: {
    type: 'bundleIdCapabilities',
    attributes: { capabilityType: capability.type, ...(capability.settings ? { settings: capability.settings } : {}) },
    relationships: { bundleId: { data: { type: 'bundleIds', id: record.id } } },
  } } });
  console.log(`${identifier}: ${capability.what} turned on`);

  const profileName = `${identifier} App Store`;
  const profiles = await api(`/v1/profiles?filter[name]=${encodeURIComponent(profileName)}&limit=10`, { token });
  for (const p of profiles.data || []) {
    await api(`/v1/profiles/${p.id}`, { token, method: 'DELETE' });
    console.log(`${identifier}: retired profile "${p.attributes.name}" (${p.attributes.profileState}) — the next build issues one with ${capability.what}`);
  }
}
