// Locates and loads compiled Noir circuit artifacts.
//
// The matcher reads from `<repo>/matcher/circuits/`, populated by
// `scripts/sync-circuits.mjs` (which copies from the workspace's
// `circuits/target/`). Keeping artifacts inside the matcher's package
// means the prover doesn't need to know about the workspace layout
// once it's running.

import { readFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export type CircuitName =
    | "darkbook_order_commitment"
    | "darkbook_match_proof"
    | "darkbook_balance_update";

export interface CompiledCircuit {
    name: CircuitName;
    bytecode: string;
    abi: unknown;
    debug_symbols?: string;
    file_map?: unknown;
}

const here = dirname(fileURLToPath(import.meta.url));
const ARTIFACTS_DIR = resolve(here, "..", "circuits");

export function loadCircuit(name: CircuitName): CompiledCircuit {
    const path = join(ARTIFACTS_DIR, `${name}.json`);
    if (!existsSync(path)) {
        throw new Error(
            `compiled circuit not found at ${path}. ` +
            `Run \`nargo compile --workspace\` in /circuits, ` +
            `then \`npm run sync-circuits\` in /matcher.`
        );
    }
    const raw = JSON.parse(readFileSync(path, "utf-8"));
    return {
        name,
        bytecode: raw.bytecode,
        abi: raw.abi,
        debug_symbols: raw.debug_symbols,
        file_map: raw.file_map,
    };
}

export function loadVerificationKey(name: CircuitName): Uint8Array {
    const path = join(ARTIFACTS_DIR, "vk", name, "vk");
    if (!existsSync(path)) {
        throw new Error(
            `verification key not found at ${path}. ` +
            `Run \`bash circuits/scripts/codegen-verifiers.sh\` to generate, ` +
            `then \`npm run sync-circuits\` in /matcher.`
        );
    }
    return readFileSync(path);
}

export function artifactsDir(): string {
    return ARTIFACTS_DIR;
}
