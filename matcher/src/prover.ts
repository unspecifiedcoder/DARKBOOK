// ============================================================
// DarkBook Matcher -- Proof Generation Service
// ============================================================
//
// Generates the three UltraHonk proofs the engine demands at settlement
// time: `order_commitment` (per trader), `match_proof` (per match), and
// `balance_update` (per match).
//
// Why subprocess rather than @noir-lang/noir_js + @aztec/bb.js?
//
//   The npm packages are versioned against specific nargo/bb releases.
//   We already verified that the `nargo` and `bb` binaries on the host
//   produce proofs the on-chain verifier accepts (see
//   `circuits/scripts/gen-fixtures.sh` and contracts/test/*Fixture.t.sol).
//   Shelling out to those same binaries removes a class of version-skew
//   bugs and keeps the matcher hermetic with respect to the rest of the
//   pipeline. The npm deps stay declared in package.json so a future
//   pure-JS switch is a search-and-replace away.

import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import type { CircuitName } from "./circuits.js";

const here = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(here, "..", "..");
const CIRCUITS_DIR = resolve(REPO_ROOT, "circuits");

// Resolve the `bb` and `nargo` binaries to absolute paths.
//
// Critical: `@aztec/bb.js` ships its own `bb` binary and exposes it as a
// package bin, so under `npm`/`npx` the node_modules/.bin shim shadows the
// system `bb` on PATH. That bundled binary is built against a newer glibc
// and fails to run on many hosts. We therefore resolve `bb` explicitly,
// preferring an env override, then the conventional system location,
// before ever falling back to a bare PATH lookup.
export function resolveBb(): string {
    const candidates = [
        process.env.DARKBOOK_BB_PATH,
        "/usr/local/bin/bb",
        `${process.env.HOME ?? ""}/.bb/bb`,
    ].filter((p): p is string => !!p);
    for (const c of candidates) {
        if (existsSync(c)) return c;
    }
    return "bb"; // last resort: bare PATH lookup
}

export function resolveNargo(): string {
    const candidates = [
        process.env.DARKBOOK_NARGO_PATH,
        "/usr/local/bin/nargo",
        `${process.env.HOME ?? ""}/.nargo/bin/nargo`,
    ].filter((p): p is string => !!p);
    for (const c of candidates) {
        if (existsSync(c)) return c;
    }
    return "nargo";
}

const BB_BIN = resolveBb();
const NARGO_BIN = resolveNargo();

export interface ProofBundle {
    /** UltraHonk proof bytes, ready to pass as the `proof` arg to the engine. */
    proof: Uint8Array;
    /** Public inputs in field order, each as a 0x-prefixed 32-byte hex string. */
    publicInputs: `0x${string}`[];
    /**
     * The exact `public_inputs` file `bb prove` emitted (concatenated
     * 32-byte fields). Pass this verbatim to `bb verify -i` -- it is the
     * canonical serialization and avoids byte-mismatch from re-encoding.
     */
    publicInputsRaw: Uint8Array;
    /** Total proof generation time in milliseconds. */
    elapsedMs: number;
}

/** Inputs that map 1:1 to the `darkbook_order_commitment` circuit. */
export interface OrderCommitmentInputs {
    // private
    price: bigint;
    amount: bigint;
    side: 0 | 1;
    salt: bigint;
    senderSecret: bigint;
    baseToken: bigint;
    quoteToken: bigint;
    balance: bigint;
    balanceLeafNonce: bigint;
    balanceLeafIndex: bigint;
    balanceMerklePath: bigint[]; // length TREE_DEPTH = 20
    // public
    commitment: `0x${string}`;
    nullifier: `0x${string}`;
    balanceRoot: `0x${string}`;
    ownerId: `0x${string}`;
    chainId: bigint;
    marketId: bigint;
    expiryBlock: bigint;
}

/** Inputs for `darkbook_match_proof`. */
export interface MatchProofInputs {
    // order A (private)
    ownerIdA: `0x${string}`;
    priceA: bigint;
    amountA: bigint;
    sideA: 0 | 1;
    expiryBlockA: bigint;
    saltA: bigint;
    // order B (private)
    ownerIdB: `0x${string}`;
    priceB: bigint;
    amountB: bigint;
    sideB: 0 | 1;
    expiryBlockB: bigint;
    saltB: bigint;
    // match (private)
    fillAmount: bigint;
    matchNonce: bigint;
    // public
    commitmentA: `0x${string}`;
    commitmentB: `0x${string}`;
    fillReceipt: `0x${string}`;
    settlementPrice: bigint;
    marketId: bigint;
    chainId: bigint;
}

/** A trader's four-leaf state for `darkbook_balance_update`. */
export interface BalanceTraderInputs {
    ownerId: `0x${string}`;
    oldBase: bigint;
    oldQuote: bigint;
    newLeafNonceBase: bigint;
    newLeafNonceQuote: bigint;
    oldLeafNonceBase: bigint;
    oldLeafNonceQuote: bigint;
    leafIndexBase: bigint;
    leafIndexQuote: bigint;
    pathBaseInOld: bigint[];   // length 20
    pathQuoteInMid: bigint[];  // length 20
}

/** Inputs for `darkbook_balance_update`. */
export interface BalanceUpdateInputs {
    a: BalanceTraderInputs;
    b: BalanceTraderInputs;
    // private market/match context
    sideA: 0 | 1;
    baseToken: bigint;
    quoteToken: bigint;
    commitmentA: `0x${string}`;
    commitmentB: `0x${string}`;
    fillAmount: bigint;
    matchNonce: bigint;
    // public
    oldRoot: `0x${string}`;
    midRoot: `0x${string}`;
    newRoot: `0x${string}`;
    fillReceipt: `0x${string}`;
    settlementPrice: bigint;
}

export class ProverService {
    private isInitialized = false;

    async initialize(): Promise<void> {
        if (this.isInitialized) return;
        // Sanity-check artifact presence so we fail fast on misconfiguration.
        // The subprocess prover consumes ACIR + VK directly from the
        // workspace's `circuits/target/` (that's where `nargo compile` and
        // `codegen-verifiers.sh` write them), so we validate THAT path --
        // not the matcher-local `circuits/` copy, which is reserved for a
        // future pure-JS prover.
        const targetDir = join(CIRCUITS_DIR, "target");
        const required: CircuitName[] = [
            "darkbook_order_commitment",
            "darkbook_match_proof",
            "darkbook_balance_update",
        ];
        for (const name of required) {
            const acir = join(targetDir, `${name}.json`);
            const vk = join(targetDir, "vk", name, "vk");
            if (!existsSync(acir)) {
                throw new Error(
                    `missing acir: ${acir}. Run \`nargo compile --workspace\` in /circuits.`,
                );
            }
            if (!existsSync(vk)) {
                throw new Error(
                    `missing vk: ${vk}. Run \`bash circuits/scripts/codegen-verifiers.sh\`.`,
                );
            }
        }
        console.log(`[Prover] initialised; artifacts at ${targetDir}`);
        this.isInitialized = true;
    }

    async generateOrderCommitmentProof(inputs: OrderCommitmentInputs): Promise<ProofBundle> {
        this.ensureReady();
        const proverToml = this.renderOrderCommitmentToml(inputs);
        return this.runProof("darkbook_order_commitment", "order_commitment", proverToml, [
            inputs.commitment,
            inputs.nullifier,
            inputs.balanceRoot,
            inputs.ownerId,
            this.bigintToHex(inputs.chainId),
            this.bigintToHex(inputs.marketId),
            this.bigintToHex(inputs.expiryBlock),
        ]);
    }

    async generateMatchProof(inputs: MatchProofInputs): Promise<ProofBundle> {
        this.ensureReady();
        const proverToml = this.renderMatchToml(inputs);
        return this.runProof("darkbook_match_proof", "match_proof", proverToml, [
            inputs.commitmentA,
            inputs.commitmentB,
            inputs.fillReceipt,
            this.bigintToHex(inputs.settlementPrice),
            this.bigintToHex(inputs.marketId),
            this.bigintToHex(inputs.chainId),
        ]);
    }

    async generateBalanceUpdateProof(inputs: BalanceUpdateInputs): Promise<ProofBundle> {
        this.ensureReady();
        const proverToml = this.renderBalanceUpdateToml(inputs);
        return this.runProof("darkbook_balance_update", "balance_update", proverToml, [
            inputs.oldRoot,
            inputs.midRoot,
            inputs.newRoot,
            inputs.fillReceipt,
            this.bigintToHex(inputs.settlementPrice),
        ]);
    }

    isReady(): boolean {
        return this.isInitialized;
    }

    // ---------- internals ----------

    private ensureReady() {
        if (!this.isInitialized) throw new Error("Prover not initialised; call initialize() first");
    }

    private renderOrderCommitmentToml(i: OrderCommitmentInputs): string {
        if (i.balanceMerklePath.length !== 20) {
            throw new Error(`balanceMerklePath must have 20 elements, got ${i.balanceMerklePath.length}`);
        }
        const path = i.balanceMerklePath.map((v) => `"${v.toString()}"`).join(", ");
        return [
            `price = "${i.price}"`,
            `amount = "${i.amount}"`,
            `side = "${i.side}"`,
            `salt = "${this.bigintToHex(i.salt)}"`,
            `sender_secret = "${this.bigintToHex(i.senderSecret)}"`,
            `base_token = "${i.baseToken}"`,
            `quote_token = "${i.quoteToken}"`,
            `balance = "${i.balance}"`,
            `balance_leaf_nonce = "${i.balanceLeafNonce}"`,
            `balance_leaf_index = "${i.balanceLeafIndex}"`,
            `balance_merkle_path = [${path}]`,
            `commitment = "${i.commitment}"`,
            `nullifier = "${i.nullifier}"`,
            `balance_root = "${i.balanceRoot}"`,
            `owner_id = "${i.ownerId}"`,
            `chain_id = "${i.chainId}"`,
            `market_id = "${i.marketId}"`,
            `expiry_block = "${i.expiryBlock}"`,
            "",
        ].join("\n");
    }

    private renderMatchToml(i: MatchProofInputs): string {
        return [
            `owner_id_a = "${i.ownerIdA}"`,
            `price_a = "${i.priceA}"`,
            `amount_a = "${i.amountA}"`,
            `side_a = "${i.sideA}"`,
            `expiry_block_a = "${i.expiryBlockA}"`,
            `salt_a = "${this.bigintToHex(i.saltA)}"`,
            `owner_id_b = "${i.ownerIdB}"`,
            `price_b = "${i.priceB}"`,
            `amount_b = "${i.amountB}"`,
            `side_b = "${i.sideB}"`,
            `expiry_block_b = "${i.expiryBlockB}"`,
            `salt_b = "${this.bigintToHex(i.saltB)}"`,
            `fill_amount = "${i.fillAmount}"`,
            `match_nonce = "${i.matchNonce}"`,
            `commitment_a = "${i.commitmentA}"`,
            `commitment_b = "${i.commitmentB}"`,
            `fill_receipt = "${i.fillReceipt}"`,
            `settlement_price = "${i.settlementPrice}"`,
            `market_id = "${i.marketId}"`,
            `chain_id = "${i.chainId}"`,
            "",
        ].join("\n");
    }

    private renderBalanceUpdateToml(i: BalanceUpdateInputs): string {
        const path = (arr: bigint[], label: string): string => {
            if (arr.length !== 20) {
                throw new Error(`${label} must have 20 elements, got ${arr.length}`);
            }
            return `[${arr.map((v) => `"${v.toString()}"`).join(", ")}]`;
        };
        return [
            `a_owner_id = "${i.a.ownerId}"`,
            `a_old_base = "${i.a.oldBase}"`,
            `a_old_quote = "${i.a.oldQuote}"`,
            `a_new_leaf_nonce_base = "${i.a.newLeafNonceBase}"`,
            `a_new_leaf_nonce_quote = "${i.a.newLeafNonceQuote}"`,
            `a_old_leaf_nonce_base = "${i.a.oldLeafNonceBase}"`,
            `a_old_leaf_nonce_quote = "${i.a.oldLeafNonceQuote}"`,
            `a_leaf_index_base = "${i.a.leafIndexBase}"`,
            `a_leaf_index_quote = "${i.a.leafIndexQuote}"`,
            `a_path_base_in_old = ${path(i.a.pathBaseInOld, "a.pathBaseInOld")}`,
            `a_path_quote_in_mid = ${path(i.a.pathQuoteInMid, "a.pathQuoteInMid")}`,
            `b_owner_id = "${i.b.ownerId}"`,
            `b_old_base = "${i.b.oldBase}"`,
            `b_old_quote = "${i.b.oldQuote}"`,
            `b_new_leaf_nonce_base = "${i.b.newLeafNonceBase}"`,
            `b_new_leaf_nonce_quote = "${i.b.newLeafNonceQuote}"`,
            `b_old_leaf_nonce_base = "${i.b.oldLeafNonceBase}"`,
            `b_old_leaf_nonce_quote = "${i.b.oldLeafNonceQuote}"`,
            `b_leaf_index_base = "${i.b.leafIndexBase}"`,
            `b_leaf_index_quote = "${i.b.leafIndexQuote}"`,
            `b_path_base_in_old = ${path(i.b.pathBaseInOld, "b.pathBaseInOld")}`,
            `b_path_quote_in_mid = ${path(i.b.pathQuoteInMid, "b.pathQuoteInMid")}`,
            `side_a = "${i.sideA}"`,
            `base_token = "${i.baseToken}"`,
            `quote_token = "${i.quoteToken}"`,
            `commitment_a = "${i.commitmentA}"`,
            `commitment_b = "${i.commitmentB}"`,
            `fill_amount = "${i.fillAmount}"`,
            `match_nonce = "${i.matchNonce}"`,
            `old_root = "${i.oldRoot}"`,
            `mid_root = "${i.midRoot}"`,
            `new_root = "${i.newRoot}"`,
            `fill_receipt = "${i.fillReceipt}"`,
            `settlement_price = "${i.settlementPrice}"`,
            "",
        ].join("\n");
    }

    private runProof(
        pkg: CircuitName,
        pkgShortDir: string,
        proverToml: string,
        publicInputs: `0x${string}`[],
    ): ProofBundle {
        const started = Date.now();

        // Each proof gets a fresh tmpdir for its Prover.toml and the bb
        // prove output.
        //
        // CONCURRENCY CAVEAT: `nargo execute` writes the witness to the
        // SHARED path circuits/target/<pkg>.gz -- not the tmpdir. Two
        // concurrent proofs of the *same* circuit would race on that file
        // (one's `bb prove` could read the other's witness). The matcher
        // proves sequentially today so this is not hit; if proving is ever
        // parallelised, pass a per-call witness path here.
        const tmp = mkdtempSync(join(tmpdir(), `darkbook-prove-${pkgShortDir}-`));
        const proverPath = join(tmp, "Prover.toml");
        writeFileSync(proverPath, proverToml);

        try {
            // nargo execute writes target/<pkg>.gz (witness)
            const execResult = spawnSync(
                NARGO_BIN,
                ["execute", "--package", pkg, "--prover-name", proverPath, "--silence-warnings"],
                { cwd: CIRCUITS_DIR, encoding: "utf-8" },
            );
            if (execResult.status !== 0) {
                throw new Error(
                    `nargo execute failed (${execResult.status}): ${execResult.stderr || execResult.stdout}`,
                );
            }

            const acirPath = join(CIRCUITS_DIR, "target", `${pkg}.json`);
            const witnessPath = join(CIRCUITS_DIR, "target", `${pkg}.gz`);
            const vkPath = join(CIRCUITS_DIR, "target", "vk", pkg, "vk");
            const proveOut = join(tmp, "out");

            const proveResult = spawnSync(
                BB_BIN,
                [
                    "prove",
                    "-b", acirPath,
                    "-w", witnessPath,
                    "-k", vkPath,
                    "-o", proveOut,
                    "-t", "evm",
                ],
                { encoding: "utf-8" },
            );
            if (proveResult.status !== 0) {
                throw new Error(
                    `bb prove failed (${proveResult.status}): ${proveResult.stderr || proveResult.stdout}`,
                );
            }

            const proofBytes = readFileSync(join(proveOut, "proof"));
            const pubBytes = readFileSync(join(proveOut, "public_inputs"));
            return {
                proof: new Uint8Array(proofBytes.buffer, proofBytes.byteOffset, proofBytes.byteLength),
                publicInputs,
                publicInputsRaw: new Uint8Array(pubBytes.buffer, pubBytes.byteOffset, pubBytes.byteLength),
                elapsedMs: Date.now() - started,
            };
        } finally {
            try { rmSync(tmp, { recursive: true, force: true }); } catch { /* ignore */ }
        }
    }

    private bigintToHex(n: bigint | number): `0x${string}` {
        const v = typeof n === "bigint" ? n : BigInt(n);
        return `0x${v.toString(16).padStart(64, "0")}` as `0x${string}`;
    }
}
