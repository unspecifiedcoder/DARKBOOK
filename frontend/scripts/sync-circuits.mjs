// Copies the compiled order_commitment circuit artifact from the
// workspace's `circuits/target/` into `frontend/public/circuits/` so the
// browser prover can fetch it as a static asset.
//
// Runs on predev/prebuild and via `npm run sync-circuits`. Idempotent.
// Only order_commitment is needed client-side -- match_proof and
// balance_update are the matcher's job, never the browser's.

import { existsSync, mkdirSync, copyFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, "..", "..", "circuits", "target", "darkbook_order_commitment.json");
const dstDir = resolve(here, "..", "public", "circuits");
const dst = join(dstDir, "darkbook_order_commitment.json");

if (!existsSync(src)) {
    console.warn(
        `[sync-circuits] ${src} not found.\n` +
        `  Run \`nargo compile --workspace\` in /circuits first.\n` +
        `  Skipping -- the browser prover will report a missing-artifact error.`,
    );
    process.exit(0);
}

mkdirSync(dstDir, { recursive: true });
copyFileSync(src, dst);
console.log(`[sync-circuits] darkbook_order_commitment.json -> public/circuits/ (${statSync(dst).size} bytes)`);
