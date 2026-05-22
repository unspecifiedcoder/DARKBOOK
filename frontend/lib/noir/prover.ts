// ============================================================
// Client-Side Order-Commitment Prover
// ============================================================
// Thin async wrapper around `proverWorker.ts`. The heavy UltraHonk
// proving runs off the main thread; this module just marshals the
// request, relays progress, and resolves with the proof.

import type {
    ProveStage,
    WorkerOutbound,
    ProveRequest,
} from "./proverWorker";

export type { ProveStage };

export type ProverStatus = "idle" | "loading" | "ready" | "proving" | "error";

/**
 * Inputs for the `darkbook_order_commitment` circuit. Field names mirror
 * the Noir circuit's parameters 1:1; every value is a decimal or 0x-hex
 * string (Noir's input encoding). The caller derives the public values
 * (commitment, nullifier, owner_id, ...) the same way the circuit does.
 */
export interface OrderProofInputs {
    // private
    price: string;
    amount: string;
    side: string;
    salt: string;
    senderSecret: string;
    baseToken: string;
    quoteToken: string;
    balance: string;
    balanceLeafNonce: string;
    balanceLeafIndex: string;
    balanceMerklePath: string[]; // length 20
    // public
    commitment: string;
    nullifier: string;
    balanceRoot: string;
    ownerId: string;
    chainId: string;
    marketId: string;
    expiryBlock: string;
}

export interface GeneratedProof {
    proof: Uint8Array;
    publicInputs: string[];
}

export interface ProveProgress {
    stage: ProveStage;
    pct: number;
}

/** Maps the camelCase input object to the circuit's snake_case parameter map. */
function toCircuitInputs(i: OrderProofInputs): Record<string, string | string[]> {
    if (i.balanceMerklePath.length !== 20) {
        throw new Error(`balanceMerklePath must have 20 elements, got ${i.balanceMerklePath.length}`);
    }
    return {
        price: i.price,
        amount: i.amount,
        side: i.side,
        salt: i.salt,
        sender_secret: i.senderSecret,
        base_token: i.baseToken,
        quote_token: i.quoteToken,
        balance: i.balance,
        balance_leaf_nonce: i.balanceLeafNonce,
        balance_leaf_index: i.balanceLeafIndex,
        balance_merkle_path: i.balanceMerklePath,
        commitment: i.commitment,
        nullifier: i.nullifier,
        balance_root: i.balanceRoot,
        owner_id: i.ownerId,
        chain_id: i.chainId,
        market_id: i.marketId,
        expiry_block: i.expiryBlock,
    };
}

export class ClientProver {
    private status: ProverStatus = "idle";
    private worker: Worker | null = null;
    private nextId = 1;
    /** Reject callbacks for proofs still in flight, so destroy() can settle them. */
    private pending = new Map<number, (reason: Error) => void>();

    /** Spawn the worker. Cheap -- the worker lazy-loads the circuit on first prove. */
    async initialize(): Promise<void> {
        if (this.worker) {
            this.status = "ready";
            return;
        }
        this.status = "loading";
        try {
            this.worker = new Worker(new URL("./proverWorker.ts", import.meta.url), {
                type: "module",
            });
            this.status = "ready";
        } catch (err) {
            this.status = "error";
            throw err;
        }
    }

    /**
     * Generate an order-commitment proof. `onProgress` fires with real
     * milestones streamed from the worker (loading -> executing -> proving).
     */
    async generateOrderProof(
        inputs: OrderProofInputs,
        onProgress?: (p: ProveProgress) => void,
    ): Promise<GeneratedProof> {
        if (!this.worker) await this.initialize();
        if (!this.worker) throw new Error("prover worker unavailable");

        const worker = this.worker;
        const id = this.nextId++;
        const circuitInputs = toCircuitInputs(inputs);
        this.status = "proving";

        return new Promise<GeneratedProof>((resolve, reject) => {
            this.pending.set(id, reject);
            const onMessage = (e: MessageEvent<WorkerOutbound>) => {
                const msg = e.data;
                if (msg.id !== id) return; // not our request
                if (msg.type === "progress") {
                    onProgress?.({ stage: msg.stage, pct: msg.pct });
                } else if (msg.type === "result") {
                    cleanup();
                    this.status = "ready";
                    resolve({ proof: msg.proof, publicInputs: msg.publicInputs });
                } else if (msg.type === "error") {
                    cleanup();
                    this.status = "ready";
                    reject(new Error(msg.message));
                }
            };
            const onError = (e: ErrorEvent) => {
                cleanup();
                this.status = "error";
                reject(new Error(`prover worker crashed: ${e.message}`));
            };
            const cleanup = () => {
                this.pending.delete(id);
                worker.removeEventListener("message", onMessage as EventListener);
                worker.removeEventListener("error", onError);
            };
            worker.addEventListener("message", onMessage as EventListener);
            worker.addEventListener("error", onError);

            const req: ProveRequest = { type: "prove", id, inputs: circuitInputs };
            worker.postMessage(req);
        });
    }

    getStatus(): ProverStatus {
        return this.status;
    }

    async destroy(): Promise<void> {
        // Settle any in-flight proofs before tearing down the worker, so
        // their promises don't hang forever.
        for (const reject of this.pending.values()) {
            reject(new Error("prover destroyed while a proof was in flight"));
        }
        this.pending.clear();
        this.worker?.terminate();
        this.worker = null;
        this.status = "idle";
    }
}

// Singleton -- the worker (and its cached circuit/backend) is reused.
let proverInstance: ClientProver | null = null;

export function getProver(): ClientProver {
    if (!proverInstance) {
        proverInstance = new ClientProver();
    }
    return proverInstance;
}
