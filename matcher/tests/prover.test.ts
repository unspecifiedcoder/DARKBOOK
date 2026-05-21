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

import { ProverService } from "../src/prover.js";
import type { OrderCommitmentInputs, MatchProofInputs } from "../src/prover.js";

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

/** Run `bb verify` against a freshly-generated proof; returns true iff bb accepts. */
function verifyWithBb(circuit: string, proofBytes: Uint8Array, pubs: `0x${string}`[]): boolean {
    const tmp = mkdtempSync(join(tmpdir(), "darkbook-verify-"));
    try {
        const proofPath = join(tmp, "proof");
        writeFileSync(proofPath, proofBytes);

        // bb wants public_inputs as a concatenation of 32-byte big-endian fields.
        const pubsPath = join(tmp, "public_inputs");
        const concat = Buffer.concat(
            pubs.map((p) => Buffer.from(p.slice(2).padStart(64, "0"), "hex")),
        );
        writeFileSync(pubsPath, concat);

        const vkPath = join(VK_DIR, circuit, "vk");
        const result = spawnSync(
            "bb",
            ["verify", "-k", vkPath, "-p", proofPath, "-i", pubsPath, "-t", "evm"],
            { encoding: "utf-8" },
        );
        return result.status === 0 && /verified successfully/i.test(result.stdout || "");
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

        expect(verifyWithBb("darkbook_order_commitment", bundle.proof, bundle.publicInputs))
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

        expect(verifyWithBb("darkbook_match_proof", bundle.proof, bundle.publicInputs))
            .toBe(true);
    }, 60_000);
});
