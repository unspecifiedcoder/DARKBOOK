# DarkBook — ZK Dark Pool on Monad

## Implementation Plan

---

## 1. Overview

DarkBook is a privacy-preserving on-chain orderbook DEX on Monad. Traders submit encrypted orders (price, size, direction) backed by ZK proofs that attest to order validity and balance sufficiency — without revealing order parameters. Orders are matched in a shared commitment pool, and settlement occurs via a reveal-and-verify mechanism. All ZK circuits are written in **Noir** (Aztec's DSL), verified on-chain via Solidity UltraPlonk verifiers, with a **Next.js** frontend.

### Why Monad

- 10k+ TPS and 1s finality makes on-chain proof verification economically viable
- Parallel execution allows concurrent proof verification across multiple order settlements
- Sub-cent verification costs vs $5–15 on Ethereum L1
- EVM-compatible — deploy existing Solidity verifier infrastructure directly

### Architecture at a Glance

```
┌─────────────────────────────────────────────────────────┐
│                    Next.js Frontend                      │
│  Wallet Connect · Order Entry · Book Visualization       │
└──────────────┬──────────────────────┬───────────────────┘
               │ submit commitment    │ query state
               ▼                      ▼
┌──────────────────────┐   ┌─────────────────────────────┐
│  Off-Chain Prover    │   │  Indexer / Event Listener    │
│  (Noir + nargo)      │   │  (WebSocket + Subgraph)      │
└──────────┬───────────┘   └─────────────────────────────┘
           │ proof + commitment
           ▼
┌─────────────────────────────────────────────────────────┐
│                 Monad (EVM)                              │
│  ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐  │
│  │ DarkBook     │ │ Settlement   │ │ Vault /         │  │
│  │ Engine       │ │ Verifier     │ │ Escrow          │  │
│  │ (commitments │ │ (UltraPlonk) │ │ (balance mgmt)  │  │
│  │  + matching) │ │              │ │                 │  │
│  └──────────────┘ └──────────────┘ └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 2. System Components

### 2.1 Noir ZK Circuits

All privacy logic lives in Noir circuits compiled to UltraPlonk proofs.

#### Circuit 1: `order_commitment`

Proves an order is valid and funded without revealing parameters.

```
Private Inputs:
  - price: Field            // limit price (scaled integer)
  - amount: Field           // order size
  - side: Field             // 0 = buy, 1 = sell
  - balance: Field          // user's deposited balance in vault
  - salt: Field             // randomness for commitment
  - balance_proof: Field    // Merkle path into balance tree

Public Inputs:
  - commitment: Field       // Pedersen(price, amount, side, salt)
  - balance_root: Field     // current vault Merkle root
  - nullifier: Field        // Hash(salt, user_address) — prevents double-submit
  - token_pair_id: Field    // which market this order targets

Constraints:
  1. commitment == pedersen([price, amount, side, salt])
  2. nullifier == pedersen([salt, sender_secret])
  3. balance >= amount * price  (if buy)
     balance >= amount          (if sell)
  4. verify_merkle(balance, balance_proof, balance_root)
  5. side ∈ {0, 1}
  6. price > 0, amount > 0
```

#### Circuit 2: `match_proof`

Proves two commitments form a valid match (executed by the matcher/relayer).

```
Private Inputs:
  - price_a, amount_a, side_a, salt_a   // order A
  - price_b, amount_b, side_b, salt_b   // order B
  - fill_amount: Field                   // how much is filled

Public Inputs:
  - commitment_a: Field
  - commitment_b: Field
  - fill_amount_hash: Field
  - settlement_price: Field

Constraints:
  1. Recompute and verify both commitments
  2. side_a != side_b (one buy, one sell)
  3. price_a >= settlement_price >= price_b  (if A=buy, B=sell)
     OR price_b >= settlement_price >= price_a (if A=sell, B=buy)
  4. fill_amount <= min(amount_a, amount_b)
  5. fill_amount > 0
  6. settlement_price == (price_a + price_b) / 2  // midpoint execution
```

#### Circuit 3: `balance_update`

Proves post-settlement balances are correct without revealing individual balances.

```
Private Inputs:
  - old_balance_a, old_balance_b: Field
  - fill_amount, settlement_price: Field
  - side_a: Field
  - merkle_path_a, merkle_path_b: Field[]

Public Inputs:
  - old_root: Field
  - new_root: Field
  - commitment_a, commitment_b: Field

Constraints:
  1. Verify old balances in old_root
  2. Compute new balances based on fill
  3. Verify new balances produce new_root
  4. No underflow (balances >= 0)
```

### 2.2 Smart Contracts (Solidity on Monad)

#### `DarkBookEngine.sol`

Core orderbook logic — stores commitments, manages the order lifecycle.

```
State:
  - mapping(bytes32 => OrderCommitment) public commitments;
  - mapping(bytes32 => bool) public nullifiers;
  - bytes32 public balanceRoot;  // Merkle root of all vault balances
  - uint256 public epochCounter;

Structs:
  - OrderCommitment { bytes32 commitment, address owner, uint256 tokenPairId, uint256 epoch, Status status }

Functions:
  - submitOrder(bytes32 commitment, bytes32 nullifier, uint256 tokenPairId, bytes proof)
      → verify order_commitment proof against on-chain balance root
      → store commitment, mark nullifier used
      → emit OrderSubmitted(commitment, tokenPairId, epoch)

  - cancelOrder(bytes32 commitment, bytes32 salt, bytes proof)
      → prove ownership via salt knowledge (small circuit or signature)
      → mark commitment as cancelled, free nullifier

  - settleMatch(bytes32 commitA, bytes32 commitB, uint256 fillAmount, uint256 price, bytes matchProof, bytes balanceProof)
      → verify match_proof
      → verify balance_update proof
      → update balanceRoot to new_root
      → emit MatchSettled(commitA, commitB, fillAmount, price)
```

#### `Vault.sol`

Handles deposits/withdrawals with Merkle-tree balance tracking.

```
State:
  - Incremental Merkle tree of balances (leaf = hash(address, token, amount))
  - mapping(address => mapping(address => uint256)) public pendingDeposits;

Functions:
  - deposit(address token, uint256 amount)
      → transferFrom user, update Merkle leaf, emit DepositProcessed

  - withdraw(uint256 amount, address token, bytes32[] merkleProof, bytes zkProof)
      → verify user has balance via ZK proof (don't reveal full balance)
      → update Merkle tree, transfer tokens

  - getBalanceRoot() → bytes32
```

#### `UltraPlonkVerifier.sol`

Auto-generated from Noir circuit compilation via `nargo codegen-verifier`. One verifier per circuit (or a dispatcher pattern).

```
Functions:
  - verifyOrderCommitment(bytes proof, bytes32[] publicInputs) → bool
  - verifyMatch(bytes proof, bytes32[] publicInputs) → bool
  - verifyBalanceUpdate(bytes proof, bytes32[] publicInputs) → bool
```

### 2.3 Off-Chain Components

#### Matcher / Relayer Service

A permissioned (initially) or decentralized (later) off-chain service that:

1. Listens for `OrderSubmitted` events
2. Has access to the encrypted order details (shared via encrypted channel or TEE)
3. Runs matching algorithm (price-time priority)
4. Generates `match_proof` and `balance_update` proofs
5. Submits `settleMatch` transactions to Monad

**Key design decision:** The matcher sees plaintext orders to perform matching. Privacy is from *other traders and on-chain observers*, not from the matcher. Future upgrade path → MPC-based matching or FHE.

```
Architecture:
  - Node.js/Rust service
  - Encrypted order submission via ECDH shared secret (user ↔ matcher)
  - In-memory orderbook (price-time priority, per pair)
  - Proof generation via nargo CLI or Noir.js WASM prover
  - Batched settlement every N seconds or M matches
```

#### Indexer

- Listens to all DarkBook contract events
- Maintains a shadow state of:
  - Active commitments (by token pair)
  - Settlement history
  - Vault balance roots
- Serves API to frontend via REST/WebSocket
- Can use a subgraph (The Graph) or custom indexer

---

## 3. Frontend — Next.js Application

### 3.1 Stack

| Layer | Tech |
|---|---|
| Framework | Next.js 14+ (App Router) |
| Styling | Tailwind CSS + shadcn/ui |
| Wallet | wagmi v2 + viem + RainbowKit |
| State | Zustand (orderbook state, user state) |
| ZK Prover | Noir.js (WASM in-browser proving) |
| Data | WebSocket for live orderbook, REST for history |
| Chain | Monad RPC via viem custom chain config |

### 3.2 Pages & Components

```
/app
  /page.tsx                    — Landing / hero
  /trade/[pair]/page.tsx       — Main trading interface
  /vault/page.tsx              — Deposit / withdraw
  /history/page.tsx            — User's trade history (decrypted locally)
  /stats/page.tsx              — Protocol stats (TVL, volume, matches)

/components
  /orderbook
    CommitmentBook.tsx         — Shows hashed commitments (no price/size visible)
    DepthVisualization.tsx     — Aggregated depth hints (optional, partial reveal)
    OrderEntryForm.tsx         — Price, amount, side → generates proof client-side
    ActiveOrders.tsx           — User's own orders (decrypted locally)
  /vault
    DepositForm.tsx
    WithdrawForm.tsx
    BalanceDisplay.tsx         — Shows user's private balance (local decryption)
  /shared
    ProofStatusIndicator.tsx   — Proving... / Verified / Failed
    TransactionTracker.tsx     — Tracks on-chain tx status
    WalletButton.tsx
  /layout
    Navbar.tsx
    Footer.tsx
```

### 3.3 Client-Side Proving Flow

```
User enters order (price, amount, side)
  → Frontend generates random salt
  → Computes commitment = Pedersen(price, amount, side, salt)
  → Computes nullifier = Pedersen(salt, user_secret)
  → Fetches current balance_root from Vault contract
  → Fetches user's Merkle proof from indexer API
  → Invokes Noir.js WASM prover with all private/public inputs
  → Receives proof (UltraPlonk, ~2-5s in browser)
  → Submits (commitment, nullifier, tokenPairId, proof) to DarkBookEngine
  → Simultaneously sends encrypted order details to Matcher via API
  → UI shows "Order Committed" with proof status
```

### 3.4 Encrypted Communication (User ↔ Matcher)

```
1. Matcher publishes an ephemeral ECDH public key
2. User derives shared secret: ECDH(user_privkey, matcher_pubkey)
3. User encrypts {price, amount, side, salt} with AES-256-GCM(shared_secret)
4. Sends ciphertext to Matcher API alongside on-chain commitment tx hash
5. Matcher decrypts, verifies commitment matches, adds to internal book
```

---

## 4. Noir Circuit Implementation Details

### 4.1 Project Structure

```
darkbook-circuits/
├── Nargo.toml
├── src/
│   ├── main.nr                  — entry point (selector for circuit type)
│   ├── order_commitment.nr      — order validity circuit
│   ├── match_proof.nr           — match verification circuit
│   ├── balance_update.nr        — post-settlement balance circuit
│   └── lib/
│       ├── merkle.nr            — Merkle tree verification helpers
│       ├── pedersen.nr          — commitment scheme wrappers
│       └── utils.nr             — field arithmetic, range checks
├── provers/
│   └── Prover.toml
└── verifiers/                   — auto-generated Solidity verifiers
```

### 4.2 Pseudocode — `order_commitment.nr`

```noir
use dep::std;

fn main(
    // Private
    price: Field,
    amount: Field,
    side: Field,
    balance: Field,
    salt: Field,
    balance_leaf_index: Field,
    balance_merkle_path: [Field; TREE_DEPTH],

    // Public
    commitment: pub Field,
    balance_root: pub Field,
    nullifier: pub Field,
    token_pair_id: pub Field,
) {
    // 1. Verify commitment
    let computed_commitment = std::hash::pedersen([price, amount, side, salt]);
    assert(computed_commitment[0] == commitment);

    // 2. Verify nullifier
    let computed_nullifier = std::hash::pedersen([salt, balance_leaf_index]);
    assert(computed_nullifier[0] == nullifier);

    // 3. Side must be 0 or 1
    assert((side == 0) | (side == 1));

    // 4. Price and amount must be positive
    // (range check: ensure < 2^126 to prevent overflow)
    assert(price as u126 > 0);
    assert(amount as u126 > 0);

    // 5. Balance sufficiency
    if side == 0 {
        // Buy: need balance >= amount * price
        let required = amount * price;
        assert(balance as u126 >= required as u126);
    } else {
        // Sell: need balance >= amount
        assert(balance as u126 >= amount as u126);
    }

    // 6. Verify balance in Merkle tree
    let leaf = std::hash::pedersen([balance_leaf_index, balance]);
    let computed_root = compute_merkle_root(leaf[0], balance_leaf_index, balance_merkle_path);
    assert(computed_root == balance_root);
}
```

### 4.3 Compilation & Verifier Generation

```bash
# Compile circuit
nargo compile

# Generate Solidity verifier
nargo codegen-verifier

# Run prover (for testing)
nargo prove

# Verify proof locally
nargo verify
```

---

## 5. Matching Engine Design

### 5.1 Algorithm

```
Price-Time Priority (continuous matching):

For each token pair:
  - Maintain sorted buy orders (descending by price, then ascending by timestamp)
  - Maintain sorted sell orders (ascending by price, then ascending by timestamp)

On new order arrival:
  1. Check if crossing orders exist on the opposite side
  2. If buy_price >= best_ask OR sell_price <= best_bid → match
  3. Settlement price = midpoint of the two limit prices
  4. Fill amount = min(buy_amount, sell_amount)
  5. Generate match_proof + balance_update proofs
  6. Submit settlement batch to Monad
  7. Update remaining quantities, re-insert partial fills
```

### 5.2 Batching Strategy

- Batch settlements every **2 seconds** (aligns with Monad block time)
- Max **16 matches per batch** (gas optimization)
- Priority: largest fill amounts first (maximize volume)
- Each batch = 1 transaction with multiple proof verifications
- Monad's parallel execution handles concurrent batch verification

---

## 6. Build Phases

### Phase 1 — Foundation (Week 1–2)

**Goal:** Noir circuits compile, Solidity verifiers deploy on Monad testnet, basic vault works.

- [ ] Initialize Noir project, implement `order_commitment` circuit
- [ ] Implement Pedersen commitment and Merkle tree helpers in Noir
- [ ] Compile circuit, generate UltraPlonk Solidity verifier
- [ ] Write `Vault.sol` with deposit/withdraw and Merkle root tracking
- [ ] Write `DarkBookEngine.sol` with `submitOrder` (verify proof on-chain)
- [ ] Deploy to Monad devnet/testnet
- [ ] Unit tests: circuit constraints, contract logic, proof verification gas costs
- [ ] Benchmark: proof verification gas on Monad vs Ethereum estimates

### Phase 2 — Matching & Settlement (Week 3–4)

**Goal:** Off-chain matcher runs, matches settle on-chain with ZK proofs.

- [ ] Implement `match_proof` circuit in Noir
- [ ] Implement `balance_update` circuit in Noir
- [ ] Build matcher service (Node.js or Rust)
  - ECDH key exchange for encrypted order relay
  - In-memory orderbook with price-time priority
  - Proof generation pipeline (nargo CLI or Noir.js)
- [ ] Implement `settleMatch` in `DarkBookEngine.sol`
- [ ] Batched settlement transactions
- [ ] Integration tests: full flow from order submission → match → settlement
- [ ] Event indexer (basic) for tracking commitments and settlements

### Phase 3 — Frontend (Week 5–6)

**Goal:** Functional Next.js trading interface with client-side proving.

- [ ] Scaffold Next.js app with wagmi, viem, RainbowKit
- [ ] Monad chain configuration in viem
- [ ] Vault pages: deposit, withdraw, balance display
- [ ] Order entry form → client-side Noir.js WASM proof generation
- [ ] Commitment book display (hashed commitments, no plaintext)
- [ ] Active orders panel (user's own, decrypted locally)
- [ ] Proof status indicator (generating / submitted / verified)
- [ ] WebSocket connection to indexer for live updates
- [ ] ECDH encrypted order relay to matcher API
- [ ] Trade history page

### Phase 4 — Hardening & UX (Week 7–8)

**Goal:** Production-grade reliability, gas optimization, polished UX.

- [ ] Gas optimization: batched verifier, calldata compression
- [ ] Order cancellation flow (with ZK proof of ownership)
- [ ] Partial fill handling in UI and matcher
- [ ] Error handling: failed proofs, reverted txs, matcher downtime
- [ ] Rate limiting and anti-spam (commitment bonds)
- [ ] Loading states, animations, dark-mode polish
- [ ] Mobile responsive layout
- [ ] Proof generation progress bar (WASM proving takes 2-5s)

### Phase 5 — Advanced Features (Week 9+)

**Goal:** Competitive feature set, decentralization path.

- [ ] Multiple trading pairs
- [ ] Market orders (taker orders that match immediately at best price)
- [ ] Aggregated depth visualization (partial privacy: reveal aggregate volume at price bands without revealing individual orders)
- [ ] MEV protection: encrypted mempool via threshold decryption
- [ ] Matcher decentralization: multiple matchers with stake-based selection
- [ ] Governance token and fee distribution
- [ ] Audit preparation (circuits + contracts)

---

## 7. Security Considerations

### ZK Circuit Risks

| Risk | Mitigation |
|---|---|
| Soundness bugs in Noir circuits | Formal verification where possible, extensive fuzzing, audit |
| Commitment malleability | Use Pedersen with domain separation tags |
| Nullifier reuse / replay | On-chain nullifier set, per-epoch scoping |
| Balance proof staleness | Enforce balance_root freshness (must match latest on-chain root) |
| Prover-side info leaks (timing) | Constant-time Noir operations, pad proof generation time |

### Matcher Trust Model

- **Current:** Trusted matcher sees plaintext orders. Trust assumption is no front-running.
- **Mitigation v1:** Matcher posts a bond; slashable if proven to front-run (via fraud proofs).
- **Mitigation v2:** Threshold decryption — order encrypted to N-of-M committee, matcher only sees plaintext after K confirmations.
- **Mitigation v3:** MPC-based matching (long-term) — no single party sees plaintext.

### Contract Risks

- Re-entrancy on settlement → use checks-effects-interactions + ReentrancyGuard
- Merkle root manipulation → only updateable via verified proofs
- Front-running of settlement txs → Monad's parallel execution + matcher-submitted txs with flashbots-style private submission if available

---

## 8. Testing Strategy

```
Unit Tests:
  - Noir circuits: nargo test (constraint satisfaction, edge cases, overflow)
  - Solidity contracts: Foundry (forge test)
  - Matcher: Jest/Vitest (matching logic, batching, edge cases)

Integration Tests:
  - Full flow on local Monad fork (Anvil-compatible)
  - Submit order → verify on-chain → match → settle → check balances
  - Concurrent order submission stress test
  - Proof verification gas benchmarks

E2E Tests:
  - Playwright/Cypress for frontend flows
  - Client-side proving → on-chain submission → UI update
  - Wallet connection, deposit, trade, withdraw cycle

Fuzzing:
  - Noir circuit fuzzing with random inputs
  - Foundry fuzz tests for contract edge cases
  - Matcher: random order streams, adversarial pricing
```

---

## 9. Repository Structure

```
darkbook/
├── circuits/                    — Noir ZK circuits
│   ├── Nargo.toml
│   ├── src/
│   │   ├── order_commitment.nr
│   │   ├── match_proof.nr
│   │   ├── balance_update.nr
│   │   └── lib/
│   └── tests/
├── contracts/                   — Solidity smart contracts
│   ├── foundry.toml
│   ├── src/
│   │   ├── DarkBookEngine.sol
│   │   ├── Vault.sol
│   │   ├── verifiers/           — auto-generated from Noir
│   │   └── libraries/
│   ├── test/
│   └── script/                  — deployment scripts
├── matcher/                     — Off-chain matching engine
│   ├── src/
│   │   ├── orderbook.ts
│   │   ├── prover.ts
│   │   ├── settler.ts
│   │   ├── encryption.ts        — ECDH + AES-GCM
│   │   └── indexer.ts
│   └── tests/
├── frontend/                    — Next.js application
│   ├── app/
│   ├── components/
│   ├── lib/
│   │   ├── noir/                — WASM prover integration
│   │   ├── contracts/           — ABIs + addresses
│   │   ├── encryption/          — Client-side ECDH
│   │   └── stores/              — Zustand stores
│   └── public/
│       └── circuits/            — Compiled circuit artifacts for WASM prover
├── docs/
│   ├── architecture.md
│   ├── circuits.md
│   └── api.md
└── README.md
```

---

## 10. Key Dependencies

| Component | Package | Version |
|---|---|---|
| ZK Circuits | Noir (nargo) | 0.30+ |
| Browser Prover | @noir-lang/noir_js | latest |
| WASM Backend | @noir-lang/backend_barretenberg | latest |
| Contracts | Foundry (forge) | latest |
| Frontend | Next.js | 14+ |
| Wallet | wagmi + viem | v2 |
| Wallet UI | RainbowKit | latest |
| Styling | Tailwind + shadcn/ui | latest |
| State | Zustand | 4+ |
| Matcher | Node.js / Bun | 20+ / 1+ |
| Encryption | @noble/ciphers, @noble/curves | latest |
| Indexer | ethers.js or viem | latest |

---

## 11. Success Metrics (Hackathon Demo)

- **Order submission:** < 5s total (prove + submit + confirm on Monad)
- **Proof verification gas:** < 300k gas per order proof on Monad
- **Match-to-settlement latency:** < 4s (matcher detects cross → settles on-chain)
- **Concurrent throughput:** 50+ orders/minute without degradation
- **Zero information leakage:** On-chain observer cannot determine price, size, or direction of any uncommitted order
- **Clean demo flow:** Deposit → Submit private order → See commitment appear → Counter-order matches → Settlement verified → Balances updated — all without revealing order details publicly
