// Copies the compiled circuit artifacts (ACIR + VKs) from
// `../circuits/target/` into `./circuits/` so the matcher can load them
// without referencing files outside its own package.
//
// Run on postinstall, or manually via `npm run sync-circuits`. Idempotent.

import { existsSync, mkdirSync, copyFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const src = resolve(here, "..", "..", "circuits", "target");
const dst = resolve(here, "..", "circuits");

if (!existsSync(src)) {
    console.warn(`[sync-circuits] no circuits/target/ at ${src}; run nargo compile first`);
    process.exit(0);
}

mkdirSync(dst, { recursive: true });

const acirFiles = readdirSync(src).filter((f) => f.startsWith("darkbook_") && f.endsWith(".json"));
for (const f of acirFiles) {
    const from = join(src, f);
    const to = join(dst, f);
    copyFileSync(from, to);
    const size = statSync(to).size;
    console.log(`[sync-circuits] ${f} (${size} bytes)`);
}

const vkRoot = join(src, "vk");
if (existsSync(vkRoot)) {
    for (const pkg of readdirSync(vkRoot)) {
        const vkFrom = join(vkRoot, pkg, "vk");
        if (existsSync(vkFrom)) {
            const vkDst = join(dst, "vk", pkg);
            mkdirSync(vkDst, { recursive: true });
            copyFileSync(vkFrom, join(vkDst, "vk"));
            console.log(`[sync-circuits] vk/${pkg}/vk`);
        }
    }
}

console.log(`[sync-circuits] done -> ${dst}`);
