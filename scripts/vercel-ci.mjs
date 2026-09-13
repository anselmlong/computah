// Keep the credential out of workflow arguments and command-failure reports.
import { spawnSync } from 'node:child_process';

if (!process.env.VERCEL_TOKEN) {
  console.error('VERCEL_TOKEN is required for deployment.');
  process.exit(1);
}
const result = spawnSync('vercel', [...process.argv.slice(2), '--token', process.env.VERCEL_TOKEN], {
  stdio: 'inherit',
});
if (result.error) console.error('Could not start the Vercel CLI.');
process.exit(result.status ?? 1);
