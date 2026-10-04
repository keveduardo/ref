// The ship job's certificate hygiene.
//
//   node tools/ci/dev-certs.mjs snapshot <file>     before the archive
//   node tools/ci/dev-certs.mjs revoke-new <file>   after it, always
//
// Why: every ship run starts on a fresh GitHub Mac with no signing key, so
// automatic signing makes a new "Apple Development: Created via API"
// certificate for the archive — and its private key dies with the runner.
// Twenty-two of them had piled up by 2026-10-04, when ship run #46 failed with
// "Your account has reached the maximum number of certificates". Revoking the
// one this run created keeps the count flat; it can never be used again
// anyway. Only certificates that did not exist before the run are touched —
// xtool's (7MYY6Q3AUR) and anything else already there are left alone.
import { readFileSync, writeFileSync } from 'node:fs';
import { loadKey, mintToken, api } from './asc.mjs';

const [mode, file] = process.argv.slice(2);
if (!['snapshot', 'revoke-new'].includes(mode) || !file) {
  console.error('usage: dev-certs.mjs snapshot|revoke-new <file>');
  process.exit(2);
}

// In CI the ship job writes the key where asc.mjs looks, as the due job does.
const token = await mintToken(loadKey());
const res = await api('/v1/certificates?filter[certificateType]=DEVELOPMENT&limit=200', { token });
const ids = res.data.map((c) => c.id);

if (mode === 'snapshot') {
  writeFileSync(file, JSON.stringify(ids));
  console.log(`${ids.length} development certificates before the archive`);
} else {
  const before = new Set(JSON.parse(readFileSync(file, 'utf8')));
  const created = ids.filter((id) => !before.has(id));
  for (const id of created) {
    await api(`/v1/certificates/${id}`, { token, method: 'DELETE' });
    console.log(`revoked ${id} (this run's throwaway development certificate)`);
  }
  if (created.length === 0) console.log('no new development certificate to revoke');
}
