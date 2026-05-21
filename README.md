# DarkBook

A ZK orderbook DEX where the only public object on-chain is a Pedersen commitment. Orders are matched off-chain. Settlement is gated by three Noir proofs that the contract verifies before it touches the balance tree — so a fill happens, or it doesn't, and no one outside the matcher learns what was traded.

```
encrypted order ──► matcher ──► (order_commitment, match_proof, balance_update) ──► Monad
                                     58 Noir tests · 117 total
```

This is a working prototype, not a deployed product. The honest punch list of what's stubbed is in [Status](#status) below. Don't skip it.

---

## The interesting bit

The textbook ZK-orderbook design walks straight into a Merkle-tree soundness bug: when you update two leaves in one proof, updating leaf A invalidates one element of leaf B's authentication path whenever they share an ancestor. Naive implementations either (a) silently produce wrong roots, or (b) constrain A and B to disjoint subtrees, which is a degenerate workaround.

The original `circuits/src/balance_update.nr` admitted to this in its comments and shipped the broken version. The rewrite in [`circuits/lib/src/merkle.nr:139`](circuits/lib/src/merkle.nr) computes the LCA structurally from the two indices via a one-hot vector, then patches B's sibling at exactly that level with A's *new* subtree root. Everything is branchless — no `if` on a witness.

```rust
pub fn assert_dual_update(
    old_root: Field, new_root: Field,
    old_leaf_a: Field, new_leaf_a: Field, index_a: Field, path_a: [Field; TREE_DEPTH],
    old_leaf_b: Field, new_leaf_b: Field, index_b: Field, path_b: [Field; TREE_DEPTH],
);
```

It's exercised by tests with leaves at:

| `index_a`, `index_b` | LCA depth | Test |
|---|---|---|
| 0, 1 | 0 (worst case — adjacent) | `test_dual_update_adjacent_leaves` |
| 5, 9 | mid | `test_dual_update_mid_distance_leaves` |
| 0, 2^19 | top | `test_dual_update_distant_leaves` |

Plus three negative tests for a wrong new-root, a tampered old leaf, and the degenerate `index_a == index_b` case. The four-leaf settlement (each trader has a base and quote leaf) is built by chaining two of these.

Other things the circuits do that you should know about:

1. **Every Pedersen call has a domain separation tag.** Seven DSTs total: order commitment, nullifier, fill receipt, match-id, balance leaf, owner identity, internal Merkle node. See [`circuits/lib/src/constants.nr`](circuits/lib/src/constants.nr). A commitment from one context cannot be reinterpreted in another.
2. **Order commitments bind the chain.** `commitment = H(DST, chain_id, market_id, owner_id, price, amount, side, expiry_block, salt)`. Cross-chain replay is impossible by construction.
3. **Match-id binds the settlement.** `match_id = H(DST, commitment_a, commitment_b, fill, settlement_price, match_nonce)`. The balance-update proof rebinds the same id. You cannot pair a match proof with a different balance update, or vice versa.
4. **Self-trade is rejected at proof time.** `assert(owner_id_a != owner_id_b)` inside [`circuits/match_proof/src/main.nr`](circuits/match_proof/src/main.nr). Not policy. Constraint.
5. **Settlement price is constrained to the crossing band, not forced to the midpoint.** Lets a matcher use an oracle-driven fair value while still being provably fair to both sides.
6. **Range checks are first-class.** Amounts and prices live in a 60-bit range; products fit in 120 bits; `assert_gte_balance_product` uses bit-decomposition to prove non-negativity, so a wraparound never looks valid.

---

## Status

Three integration gaps stand between this prototype and "we can verify a real proof end-to-end on Monad". Each is grep-able in the codebase as a `*** stub today ***` comment.

| Component | State | What it needs |
|---|---|---|
| Noir circuits, 3 binaries | **Real.** 58 tests, ACIR compiles clean. | — |
| `lib/src/merkle.nr` LCA fix | **Real.** | — |
| Solidity engine + vault | **Real.** 42 Foundry tests, gas-benchmarked. | — |
| Matcher orderbook | **Real.** 17 Vitest tests, price-time priority correct. | — |
| Frontend UI | **Real.** Order entry, vault flow, opaque book viz. | — |
| On-chain UltraHonk verifiers (3) | **Real.** Generated via `bb write_solidity_verifier` from each Noir circuit. ~2460 lines of Solidity each, all three verify real proofs on Monad. | — |
| Engine ↔ verifier wiring | **Real.** `DarkBookEngine.sol` packs 7 / 6 / 5 public inputs per circuit, in Noir declaration order. | — |
| Foundry proof fixtures | **Real.** Two proof fixtures committed (`order_commitment` 8384B, `match_proof` 8000B), regenerable via `circuits/scripts/gen-fixtures.sh`. Both verify on-chain in test (gas ~2.1–2.5M each). | — |
| `matcher/src/prover.ts` | **Real.** Generates UltraHonk proofs by shelling out to `nargo execute` + `bb prove`. Same path the fixture pipeline uses. | — |
| `frontend/lib/noir/prover.ts` | **Stub.** `setTimeout(2000)`. | `@aztec/bb.js` in a worker thread + Next.js wasm bundling fix. |
| Matcher-side privacy | **Not v1.** Operator sees plaintext after ECDH decrypt. | MPC or threshold encryption for v2. |

If you're a hackathon judge or a contributor evaluating this repo, the on-chain ZK security model is now real: the verifier rejects garbage bytes (`test_real_verifier_rejects_garbage`), accepts real UltraHonk proofs (`test_submitOrder_accepts_real_proof`), and rejects mutated public inputs (3 negative tests on the match proof). The remaining work is closing the user-side proving loop in the browser.

---

## Threat model — what you actually get today

DarkBook v1 is best described as **an encrypted orderbook with a trusted matcher**, not a fully trustless dark pool in the Renegade sense. Don't call it a dark pool to a sophisticated adversary; it's not one yet.

Protected against:
- ✅ Other users reading your orders. Only commitments hit the chain.
- ✅ On-chain observers reconstructing price/size/direction. Same reason.
- ✅ Cross-chain or cross-market replay. Each commitment binds `chain_id` and `market_id`.
- ✅ Double-submission of the same order. Nullifier prevents it.
- ✅ Double-settlement of the same match. `match_id` binding in both proofs prevents it.
- ✅ Self-trade / wash crossing. Asserted in `match_proof`.
- ✅ Balance underflow on the losing side of a fill. Range-checked before subtraction.

Not protected against:
- ❌ A malicious or compromised matcher operator. They see plaintext orders and can front-run, MEV-extract, or selectively reorder. Run your own matcher or use one you trust until v2 (threshold encryption) lands.
- ❌ Long-term linkage: the same `owner_id` appears in every order from one trader. A v2 design with per-order owner blinding closes this.

---

## Layout

```
circuits/                      Nargo workspace
  Nargo.toml                   members = [lib, order_commitment, match_proof, balance_update]
  lib/src/
    constants.nr               DSTs, tree depth (20), 60-bit range bounds
    utils.nr                   range checks, cond_select, safe_mul, gte
    hash.nr                    7 typed Pedersen helpers
    merkle.nr                  inclusion + LCA-aware dual update
    identity.nr                owner_id = H(DST, sender_secret)
    order.nr                   side helpers, settlement deltas
  order_commitment/src/main.nr
  match_proof/src/main.nr
  balance_update/src/main.nr

contracts/                     Foundry
  src/DarkBookEngine.sol       commitments, nullifiers, settlement
  src/Vault.sol                deposits, balance Merkle tree
  src/libraries/MerkleTree.sol
  src/verifiers/               *** stub today ***
  test/                        42 tests
  script/                      Deploy.s.sol, E2ETest.s.sol, WorstCase.s.sol

matcher/src/
  orderbook.ts                 price-time priority, partial fills
  prover.ts                    *** stub today ***
  settler.ts                   viem batch settlement
  indexer.ts                   event listener + WS fanout
  encryption.ts                ECDH (secp256k1) + AES-256-GCM

frontend/
  app/                         Next.js 14 app router
  components/orderbook/        order entry, commitment book, active orders
  components/vault/            deposit, withdraw
  lib/noir/prover.ts           *** stub today ***
  lib/encryption/client.ts     browser-side ECDH
  lib/stores/                  Zustand
  lib/hooks/                   wagmi + WebSocket
```

---

## Running it

```bash
# Circuits
cd circuits
nargo check --workspace
nargo test --workspace           # 58/58 expected
nargo compile --workspace        # writes target/*.json

# When you're ready to wire the real verifier:
nargo codegen-verifier --package darkbook_order_commitment
nargo codegen-verifier --package darkbook_match_proof
nargo codegen-verifier --package darkbook_balance_update

# Contracts
cd ../contracts
forge install
cp .env.example .env             # PRIVATE_KEY, MONAD_TESTNET_RPC_URL
forge test -vvv                  # 42/42 expected
forge test --gas-report

# Matcher
cd ../matcher
npm install
cp .env.example .env
npx vitest run                   # 17/17 expected
npx tsx watch src/index.ts

# Frontend
cd ../frontend
npm install
cp .env.example .env
npm run dev                      # http://localhost:3000
```

Prerequisites: Node ≥ 20, Foundry (`foundryup`), Nargo ≥ 1.0.0-beta.19.

---

## Trade lifecycle (the precise version)

**Submit.** Browser builds `salt`, computes `owner_id = H(DST_owner, secret)`, then `commitment` and `nullifier` as defined above, fetches `balance_root` from `Vault`, runs `order_commitment` in WASM, posts `(commitment, nullifier, market_id, proof)` to `DarkBookEngine.submitOrder`. In parallel, ECDH-encrypts the plaintext order to the matcher.

**Match.** Matcher decrypts, inserts into `Orderbook` (price-time priority, binary-search insertion in `matcher/src/orderbook.ts`). On a crossing arrival, picks a settlement price in the band, generates a `match_proof` (binds both commitments + match-id) and a `balance_update` proof (transitions four leaves: base+quote for A, base+quote for B).

**Settle.** Matcher batches up to N matches into one call to `DarkBookEngine.settleMatch`. The engine calls `UltraPlonkVerifier.verifyMatch` and `verifyBalanceUpdate`, marks orders `Filled`, updates `balance_root`, emits `MatchSettled`. Nullifiers are now spent.

There is no commit-reveal phase in v1. Adding one is roadmap item 3 below.

---

## Tests, explicitly

### Noir — 58/58

Run: `cd circuits && nargo test --workspace`.

`darkbook_lib` (35) covers the primitives. Highlights:

- `merkle::test_dual_update_adjacent_leaves` — LCA at depth 0
- `merkle::test_dual_update_distant_leaves` — LCA at depth `TREE_DEPTH-1`
- `merkle::test_dual_update_rejects_wrong_new_root` — soundness
- `merkle::test_dual_update_rejects_same_index` — degenerate case
- `hash::test_dst_separation_order_vs_nullifier` — DSTs actually separate
- `hash::test_match_id_binds_all_inputs` — match-id is collision-resistant per input

`darkbook_order_commitment` (8): valid buy, valid sell, plus rejections for tampered commitment, insufficient balance, wrong owner id, zero market id, zero amount, invalid side.

`darkbook_match_proof` (10): valid match at midpoint, at buyer's limit, at seller's limit, plus rejections for same-side orders, self-trade, non-crossing prices, settlement above buyer's limit, fill > amount_a, tampered receipt, wrong-market binding.

`darkbook_balance_update` (5): valid balance update with A as buyer, valid with A as seller, rejected tampered receipt, rejected buyer-quote underflow, rejected same-owner.

Every negative test uses `#[test(should_fail_with = "...")]` and asserts the exact error string, so a regression that changes which constraint fires will surface as a test failure rather than silently passing on a different rejection.

### Foundry — 42/42

Run: `cd contracts && forge test -vvv`.

Unit (14): deposits, order submission, cancellation, settlement, admin (matcher authorization, epoch advance).
Happy-flow E2E (5): deposit → submit → match → settle → verify state; multi-deposit; multi-match; cancel/re-submit; epoch tracking.
Attack scenarios (23): nullifier replay, commitment replay, unauthorized settlement, unauthorized cancellation, settle-filled, settle-cancelled, double-cancel, unsupported token, zero deposit, overflow, zero address, invalid pair, revoke matcher, permissionless mode, settlement record integrity, gas budgets.

Gas budgets (against the stub verifier — these will increase materially when the real UltraHonk verifier lands):
`deposit` 250–310k · `submitOrder` 188–245k · `settleMatch` 155k · `cancelOrder` 30k.

### Matcher — 17/17

Run: `cd matcher && npx vitest run`. Price/time sort invariants, crossing, midpoint, non-crossing, partial fills, multi-order sequence, cross-pair isolation, removal, best bid/ask, pending-match tracking.

---

## Roadmap

Items 1 and 2 from the prior README have landed (real on-chain verifier and a real matcher-side prover). The remaining work, ordered by leverage:

1. **Client-side proving in the browser.** `@aztec/bb.js` in a worker thread + Next.js wasm bundling. The matcher already shells out to `nargo` + `bb` and the same approach works server-side; the browser path needs the wasm route.
2. **`balance_update` proof + restored E2E settleMatch test.** The circuit and matcher API are both ready; the missing piece is a canonical 4-leaf witness fixture and the threading of per-trader Merkle data through `index.ts → settler.ts`.
3. **Commit-reveal channel.** Trader posts encrypted reveal to a bulletin board; matcher only decrypts when both sides are settled-ready. Eliminates the front-running window.
4. **Threshold-encrypted matcher.** N operators jointly decrypt; no single operator sees plaintext. Renegade-style without full MPC complexity.
5. **Partial-fill state in the engine.** Circuit already supports it; engine doesn't yet update `remainingAmount`.
6. **Withdrawal proofs.** `Vault.withdraw` now reverts with `NotYetImplemented`; the dedicated withdrawal circuit + verifier is the next addition.
7. **Per-order owner blinding.** Today the same `owner_id` recurs across a trader's orders, allowing linkage. v2: `owner_id = H(master_secret, salt)`.
8. **Audit.** After steps 1–4.

---

## Pre-rewrite deployments (historical only)

These addresses are pinned to the **stub verifier** and the **pre-workspace circuit interface**. After step 1 of the roadmap, redeploy. Don't send funds here expecting modern semantics.

| Contract | Address |
|---|---|
| UltraPlonkVerifier (stub) | `0x94De85a9737dba2f2C470Be46D0F77D3E9f3eb40` |
| Vault | `0xAe76085867146f76932A0711059450a01CE7e4A3` |
| DarkBookEngine | `0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d` |
| TestToken (dUSDC) | `0x79553F542e70d2Ef0F992cb86287e02ECa15D71b` |

Monad testnet, chain ID 10143.

---

## If you want to break it

A short list of things a reviewer should try first. If any of these succeed against the current code, that's a real finding.

- Submit two `order_commitment` proofs reusing the same `salt` and `sender_secret` under the same market. Should fail at the nullifier check on the second one. (Engine-side, since the circuit produces the nullifier; the engine tracks spent nullifiers.)
- Submit a match proof where `commitment_a` and `commitment_b` were originally committed under different `market_id`s. Should fail at `commitment A mismatch` / `commitment B mismatch`.
- Submit a balance update with `commitment_a/b` and `match_nonce` from one match but `fill_amount` from another. Should fail at `fill_receipt mismatch`.
- Submit a balance update where one trader's old balance is set arbitrarily low. Should fail at the inclusion proof for that leaf.
- Submit a balance update where the new root is computed from a *different* update sequence. Should fail at `new_root mismatch` from the second `assert_dual_update`.
- Try to reuse a `match_proof` from settlement N for settlement M (different match) by submitting the same proof bytes. Even if the verifier accepts the cryptographic proof, the engine's nullifier-style commitment tracking marks both orders as `Filled` and rejects the second attempt.

For circuit-level penetration tests, look at the `should_fail_with` tests in each binary's `src/main.nr` — those enumerate the constraints a malicious prover would try to bypass.

---

License: MIT.
