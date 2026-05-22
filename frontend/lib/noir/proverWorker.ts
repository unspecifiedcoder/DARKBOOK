// ============================================================
// Order-commitment proving Web Worker
// ============================================================
// Browser UltraHonk proving takes 5-15s. Running it on the main thread
// freezes the UI for that whole window, so the actual work happens here,
// off-thread. The worker streams progress milestones back so the UI can
// show a real status (not a fake spinner).
//
// Protocol:
//   main -> worker : { type: "prove", id, inputs }
//   worker -> main : { type: "progress", id, stage, pct }
//   worker -> main : { type: "result", id, proof, publicInputs }
//   worker -> main : { type: "error", id, message }

import { Noir } from "@noir-lang/noir_js";
import { UltraHonkBackend } from "@aztec/bb.js";

export type ProveStage = "loading" | "executing" | "proving" | "done";

export interface ProveRequest {
    type: "prove";
    id: number;
    /** Noir input map -- keys MUST match the circuit's parameter names. */
    inputs: Record<string, string | string[]>;
}

export interface ProgressMessage {
    type: "progress";
    id: number;
    stage: ProveStage;
    pct: number;
}

export interface ResultMessage {
    type: "result";
    id: number;
    proof: Uint8Array;
    publicInputs: string[];
}

export interface ErrorMessage {
    type: "error";
    id: number;
    message: string;
}

export type WorkerOutbound = ProgressMessage | ResultMessage | ErrorMessage;

// The compiled circuit is fetched once and cached for the worker's life.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let circuitCache: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let backendCache: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let noirCache: any = null;

const CIRCUIT_URL = "/circuits/darkbook_order_commitment.json";

function post(msg: WorkerOutbound) {
    // No transferables: the proof is only ~9 KB, so a structured-clone
    // copy is negligible and avoids any chance of detaching a buffer
    // that is a view into a larger pool.
    // @ts-expect-error -- worker global scope
    self.postMessage(msg);
}

function progress(id: number, stage: ProveStage, pct: number) {
    post({ type: "progress", id, stage, pct });
}

async function ensureLoaded(id: number) {
    if (circuitCache && backendCache && noirCache) return;
    progress(id, "loading", 5);
    const res = await fetch(CIRCUIT_URL);
    if (!res.ok) {
        throw new Error(
            `failed to fetch circuit artifact (${res.status}). ` +
            `Did \`npm run sync-circuits\` run? Expected ${CIRCUIT_URL}.`,
        );
    }
    circuitCache = await res.json();
    progress(id, "loading", 20);
    noirCache = new Noir(circuitCache);
    backendCache = new UltraHonkBackend(circuitCache.bytecode);
    progress(id, "loading", 30);
}

async function handleProve(req: ProveRequest) {
    const { id, inputs } = req;
    try {
        await ensureLoaded(id);

        // 1. Execute the circuit -> witness.
        progress(id, "executing", 40);
        const { witness } = await noirCache.execute(inputs);

        // 2. Generate the proof. `keccak: true` selects the EVM-compatible
        //    transcript so the proof verifies against the Solidity verifier
        //    generated with `bb ... -t evm`.
        progress(id, "proving", 55);
        const { proof, publicInputs } = await backendCache.generateProof(witness, {
            keccak: true,
        });

        progress(id, "done", 100);
        const bytes = proof instanceof Uint8Array ? proof : new Uint8Array(proof);
        post({ type: "result", id, proof: bytes, publicInputs });
    } catch (err) {
        post({
            type: "error",
            id,
            message: err instanceof Error ? err.message : String(err),
        });
    }
}

// @ts-expect-error -- worker global scope
self.onmessage = (e: MessageEvent<ProveRequest>) => {
    if (e.data?.type === "prove") {
        void handleProve(e.data);
    }
};
