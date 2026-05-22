// Integration test: ProverService generates real UltraHonk proofs that
// match the canonical fixtures used by the Foundry tests. Proofs aren't
// deterministic byte-for-byte (the prover samples randomness), so we
// can't compare proof bytes directly -- instead we (a) check the
// reported elapsed time / size are sensible and (b) re-verify the
// generated proof natively via `bb verify`, which is the same path the
// fixture script uses to sanity-check.

import { describe, it, expect, beforeAll } from "vitest";
import { spawnSync } from "node:child_process";
import { writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { ProverService, resolveBb } from "../src/prover.js";
import type {
    OrderCommitmentInputs,
    MatchProofInputs,
    BalanceUpdateInputs,
} from "../src/prover.js";

const BB = resolveBb();

/** Build a 20-element Merkle path with non-zero values at indices 1 and 2. */
function path3(v1: bigint, v2: bigint): bigint[] {
    const p = Array(20).fill(0n) as bigint[];
    p[1] = v1;
    p[2] = v2;
    return p;
}

const here = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(here, "..", "..");
const VK_DIR = resolve(REPO_ROOT, "circuits", "target", "vk");

// Canonical fixture witness for order_commitment -- same values that
// `circuits/order_commitment/src/main.nr::print_fixture_values` emits.
const ORDER_FIXTURE: OrderCommitmentInputs = {
    price: 100n,
    amount: 50n,
    side: 0,
    salt: 0xABC123n,
    senderSecret: 0xDEADBEEFn,
    baseToken: 11n,
    quoteToken: 22n,
    balance: 10_000n,
    balanceLeafNonce: 1n,
    balanceLeafIndex: 0n,
    balanceMerklePath: Array(20).fill(0n) as bigint[],
    commitment: "0x0a6c2196b8445b12dfd50212382eea56db8cf395f6290838234206fc0234a0c4",
    nullifier: "0x2d4cddf1a51904a47fc66f3e73e20356cdf3f0f4712497dbc81c38a74b52e385",
    balanceRoot: "0x1fd357b38a122063e6609acef276ec1117f88070dcb308ac56f38327ab3803f0",
    ownerId: "0x0221e4b4837371040a10fe17b9a4ab5923592881cda453ff85bfe74c22f859ad",
    chainId: 31337n,
    marketId: 1n,
    expiryBlock: 100_000n,
};

const MATCH_FIXTURE: MatchProofInputs = {
    ownerIdA: ("0x" + "64".padStart(64, "0")) as `0x${string}`, // 100
    priceA: 110n,
    amountA: 50n,
    sideA: 0,
    expiryBlockA: 100_000n,
    saltA: 1n,
    ownerIdB: ("0x" + "c8".padStart(64, "0")) as `0x${string}`, // 200
    priceB: 90n,
    amountB: 40n,
    sideB: 1,
    expiryBlockB: 100_000n,
    saltB: 2n,
    fillAmount: 30n,
    matchNonce: 999n,
    commitmentA: "0x153657ffb2ddce11ef88f4d7500e6961bdb6afe935b54062fb94175cfa82dc73",
    commitmentB: "0x204aa3af7ab7b8d868f8db24bb0454458a5197f6036e6c0dac03ec36f0fcd5f2",
    fillReceipt: "0x275199da460ce433549a6fbe4029dec282c10d69c6664cf681280f421556a621",
    settlementPrice: 100n,
    marketId: 1n,
    chainId: 31337n,
};

// Coherent with MATCH_FIXTURE: same commitments / fill / price / nonce,
// so the fill_receipt this proof binds matches the match proof's.
const BALANCE_FIXTURE: BalanceUpdateInputs = {
    a: {
        ownerId: ("0x" + "64".padStart(64, "0")) as `0x${string}`, // 100
        oldBase: 0n,
        oldQuote: 10_000n,
        newLeafNonceBase: 2n,
        newLeafNonceQuote: 2n,
        oldLeafNonceBase: 1n,
        oldLeafNonceQuote: 1n,
        leafIndexBase: 0n,
        leafIndexQuote: 2n,
        pathBaseInOld: path3(
            0x0ec5c4c421230d22dd2df48101d2d5bd186c545b8bff4f1cde4cc9e905cfb9can,
            0x0f9b2c0512963bcd5566da4029709e55cac07e552598a8952a80f8ffdf033e6dn,
        ),
        pathQuoteInMid: path3(
            0x04110e83a21d04e099c40969a2b57457d1dfb87d10f62fd889b8e6f2327f5263n,
            0x2f9efce1ca35eaf9c352b78244fe1f307ae6f373745acccd335b7a2e6064f464n,
        ),
    },
    b: {
        ownerId: ("0x" + "c8".padStart(64, "0")) as `0x${string}`, // 200
        oldBase: 100n,
        oldQuote: 0n,
        newLeafNonceBase: 2n,
        newLeafNonceQuote: 2n,
        oldLeafNonceBase: 1n,
        oldLeafNonceQuote: 1n,
        leafIndexBase: 4n,
        leafIndexQuote: 6n,
        pathBaseInOld: path3(
            0x28cdf25885b0d3393547485d069a8586955f79ea8622b7438738178d384bff66n,
            0x10a05f8315ca73aeff269207326bd78b5d4647bf4ef288f657fc621f04486349n,
        ),
        pathQuoteInMid: path3(
            0x0950b9332b6a71fdc2f4f1f0be6e4c0d980202a69e8ff86c2606822d9159aa32n,
            0x147b79842149c314f71a2829596bec827fc36941a82e4f82aa45643a7c90a7b0n,
        ),
    },
    sideA: 0,
    baseToken: 11n,
    quoteToken: 22n,
    commitmentA: "0x153657ffb2ddce11ef88f4d7500e6961bdb6afe935b54062fb94175cfa82dc73",
    commitmentB: "0x204aa3af7ab7b8d868f8db24bb0454458a5197f6036e6c0dac03ec36f0fcd5f2",
    fillAmount: 30n,
    matchNonce: 999n,
    oldRoot: "0x1b053cb9bb022cd92962cae97a6d5024a85c57f605d42654b3cc32b1c6b7b3d4",
    midRoot: "0x00e411346b24e0c2e6133750b12225b03cb4ae473b5dd697418a4a0373412eca",
    newRoot: "0x2845b0eb1d49aefe2dfb9202cb0dbb013bbaf3f095dab9e50cf6fd4ae4bcef2d",
    fillReceipt: "0x275199da460ce433549a6fbe4029dec282c10d69c6664cf681280f421556a621",
    settlementPrice: 100n,
};

/**
 * Run `bb verify` against a freshly-generated proof; returns true iff bb
 * accepts. Uses the exact `public_inputs` bytes bb itself emitted
 * (ProofBundle.publicInputsRaw) so there is no re-encoding mismatch.
 */
function verifyWithBb(circuit: string, proofBytes: Uint8Array, pubsRaw: Uint8Array): boolean {
    const tmp = mkdtempSync(join(tmpdir(), "darkbook-verify-"));
    try {
        const proofPath = join(tmp, "proof");
        const pubsPath = join(tmp, "public_inputs");
        writeFileSync(proofPath, proofBytes);
        writeFileSync(pubsPath, pubsRaw);

        const vkPath = join(VK_DIR, circuit, "vk");
        const result = spawnSync(
            BB,
            ["verify", "-k", vkPath, "-p", proofPath, "-i", pubsPath, "-t", "evm"],
            { encoding: "utf-8" },
        );
        // bb writes "Proof verified successfully" to stderr, not stdout.
        const out = (result.stdout || "") + (result.stderr || "");
        return result.status === 0 && /verified successfully/i.test(out);
    } finally {
        try { rmSync(tmp, { recursive: true, force: true }); } catch { /* ignore */ }
    }
}

describe("ProverService", () => {
    const prover = new ProverService();

    beforeAll(async () => {
        await prover.initialize();
    });

    it("generates a valid order_commitment proof for the canonical witness", async () => {
        const bundle = await prover.generateOrderCommitmentProof(ORDER_FIXTURE);

        // UltraHonk proofs for this circuit are 8384 bytes (constant across
        // runs because the circuit size is fixed).
        expect(bundle.proof.length).toBe(8384);
        expect(bundle.publicInputs).toHaveLength(7);
        expect(bundle.publicInputs[0]).toBe(ORDER_FIXTURE.commitment);
        expect(bundle.publicInputs[1]).toBe(ORDER_FIXTURE.nullifier);
        expect(bundle.publicInputs[2]).toBe(ORDER_FIXTURE.balanceRoot);
        expect(bundle.publicInputs[3]).toBe(ORDER_FIXTURE.ownerId);

        expect(verifyWithBb("darkbook_order_commitment", bundle.proof, bundle.publicInputsRaw))
            .toBe(true);
    }, 60_000);

    it("rejects mismatched public inputs by producing nothing useful", async () => {
        // If the prover is asked to prove against a public commitment that
        // doesn't match the private witness, nargo execute fails inside
        // the circuit (the `commitment == hash(...)` assertion fires).
        const tampered = { ...ORDER_FIXTURE, commitment: "0xdeadbeef" + "00".repeat(28) as `0x${string}` };
        await expect(prover.generateOrderCommitmentProof(tampered)).rejects.toThrow();
    }, 30_000);

    it("generates a valid match_proof for the canonical match", async () => {
        const bundle = await prover.generateMatchProof(MATCH_FIXTURE);
        expect(bundle.proof.length).toBe(8000);
        expect(bundle.publicInputs).toHaveLength(6);
        expect(bundle.publicInputs[0]).toBe(MATCH_FIXTURE.commitmentA);
        expect(bundle.publicInputs[1]).toBe(MATCH_FIXTURE.commitmentB);
        expect(bundle.publicInputs[2]).toBe(MATCH_FIXTURE.fillReceipt);

        expect(verifyWithBb("darkbook_match_proof", bundle.proof, bundle.publicInputsRaw))
            .toBe(true);
    }, 60_000);

    it("generates a valid balance_update proof for the canonical settlement", async () => {
        const bundle = await prover.generateBalanceUpdateProof(BALANCE_FIXTURE);
        expect(bundle.proof.length).toBe(9536);
        expect(bundle.publicInputs).toHaveLength(5);
        expect(bundle.publicInputs[0]).toBe(BALANCE_FIXTURE.oldRoot);
        expect(bundle.publicInputs[2]).toBe(BALANCE_FIXTURE.newRoot);
        expect(bundle.publicInputs[3]).toBe(BALANCE_FIXTURE.fillReceipt);

        expect(verifyWithBb("darkbook_balance_update", bundle.proof, bundle.publicInputsRaw))
            .toBe(true);
    }, 60_000);
});
