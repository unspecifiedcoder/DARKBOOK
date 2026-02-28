# DarkBook — ZK Dark Pool on Monad

A privacy-preserving on-chain orderbook DEX. Traders submit encrypted orders backed by ZK proofs that verify validity and balance sufficiency without revealing price, size, or direction. Orders are matched off-chain and settled on-chain via a reveal-and-verify mechanism.

Built with **Noir** (ZK circuits), **Solidity** (smart contracts on Monad), **Node.js** (matcher service), and **Next.js** (frontend).

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Next.js Frontend                      │
│  Wallet Connect · Order Entry · Book Visualization       │
└──────────────┬──────────────────────┬───────────────────┘
               │ submit commitment    │ query state
               ▼                      ▼
┌──────────────────────┐   ┌─────────────────────────────┐
│  Off-Chain Matcher    │   │  Indexer / Event Listener    │
│  (Node.js + Noir.js)  │   │  (WebSocket API)             │
└──────────┬───────────┘   └─────────────────────────────┘
           │ proof + settlement tx
           ▼
┌─────────────────────────────────────────────────────────┐
│                 Monad (EVM)                              │
│  ┌──────────────┐ ┌──────────────┐ ┌─────────────────┐  │
│  │ DarkBook     │ │ UltraPlonk   │ │ Vault /         │  │
│  │ Engine       │ │ Verifier     │ │ Escrow          │  │
│  │ (commitments │ │              │ │ (balance mgmt)  │  │
│  │  + matching) │ │              │ │                 │  │
│  └──────────────┘ └──────────────┘ └─────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## Deployed Contracts (Monad Testnet — Chain ID 10143)

| Contract | Address |
|---|---|
| UltraPlonkVerifier | `0x94De85a9737dba2f2C470Be46D0F77D3E9f3eb40` |
| Vault | `0xAe76085867146f76932A0711059450a01CE7e4A3` |
| DarkBookEngine | `0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d` |
| TestToken (dUSDC) | `0x79553F542e70d2Ef0F992cb86287e02ECa15D71b` |

---

## Prerequisites

- **Node.js** >= 20
- **Foundry** (forge, cast, anvil) — [Install guide](https://book.getfoundry.sh/getting-started/installation)
- **Noir / Nargo** >= 0.30 — [Install guide](https://noir-lang.org/docs/getting_started/installation/) (only needed for circuit compilation)
- **Git**

### Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Verify installations

```bash
forge --version
cast --version
node --version
```

---

## Repository Structure

```
darkbook/
├── circuits/                    # Noir ZK circuits
│   ├── Nargo.toml
│   └── src/
│       ├── main.nr              # Entry point (order commitment circuit)
│       ├── order_commitment.nr  # Order validity + balance sufficiency
│       ├── match_proof.nr       # Match verification circuit
│       ├── balance_update.nr    # Post-settlement balance circuit
│       └── lib/
│           ├── merkle.nr        # Merkle tree helpers (depth 20)
│           ├── pedersen.nr      # Domain-separated Pedersen commitments
│           └── utils.nr         # Range checks, safe arithmetic
├── contracts/                   # Solidity smart contracts (Foundry)
│   ├── foundry.toml
│   ├── src/
│   │   ├── DarkBookEngine.sol   # Core orderbook + settlement
│   │   ├── Vault.sol            # Deposits/withdrawals + Merkle tree
│   │   ├── verifiers/           # ZK proof verifiers
│   │   └── libraries/           # MerkleTree library
│   ├── test/                    # Unit + E2E + worst-case tests
│   └── script/                  # Deployment + test scripts
├── matcher/                     # Off-chain matching engine (Node.js)
│   ├── src/
│   │   ├── index.ts             # Orchestrator + entry point
│   │   ├── orderbook.ts         # Price-time priority orderbook
│   │   ├── prover.ts            # ZK proof generation service
│   │   ├── settler.ts           # On-chain settlement via viem
│   │   ├── encryption.ts        # ECDH + AES-GCM order encryption
│   │   ├── indexer.ts           # Event listener + WebSocket server
│   │   └── types.ts             # TypeScript type definitions
│   └── tests/                   # Orderbook matching tests
├── frontend/                    # Next.js 14 application
│   ├── app/                     # App Router pages
│   ├── components/              # React components
│   │   ├── orderbook/           # Trading interface
│   │   ├── vault/               # Deposit/withdraw
│   │   ├── shared/              # Proof status, tx tracker
│   │   └── layout/              # Navbar, footer
│   └── lib/
│       ├── contracts/           # ABIs + deployed addresses
│       ├── stores/              # Zustand state (orders, vault)
│       ├── noir/                # WASM prover integration
│       ├── encryption/          # Client-side ECDH
│       └── hooks/               # WebSocket hook
└── plan.md                      # Full implementation plan
```

---

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/your-username/DARKBOOK.git
cd DARKBOOK
```

### 2. Smart Contracts

```bash
cd contracts

# Install dependencies
forge install

# Create environment file
cp .env.example .env
# Edit .env with your private key and RPC URL:
#   PRIVATE_KEY=0x...
#   MONAD_TESTNET_RPC_URL=https://testnet-rpc.monad.xyz

# Compile
forge build

# Run all tests (42 tests: unit + E2E + worst-case)
forge test -vvv

# Deploy to Monad testnet
forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://testnet-rpc.monad.xyz \
  --broadcast \
  --private-key $PRIVATE_KEY

# Run E2E test on live testnet
forge script script/E2ETest.s.sol:E2ETest \
  --rpc-url https://testnet-rpc.monad.xyz \
  --broadcast \
  --private-key $PRIVATE_KEY

# Run worst-case scenario tests on live testnet
forge script script/WorstCase.s.sol:WorstCaseTest \
  --rpc-url https://testnet-rpc.monad.xyz \
  --broadcast \
  --private-key $PRIVATE_KEY
```

### 3. Matcher Service

```bash
cd matcher

# Install dependencies
npm install

# Create environment file
cp .env.example .env
# Edit .env:
#   MONAD_RPC_URL=https://testnet-rpc.monad.xyz
#   MATCHER_PRIVATE_KEY=0x...
#   ENGINE_ADDRESS=0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d
#   VAULT_ADDRESS=0xAe76085867146f76932A0711059450a01CE7e4A3

# Run tests (17 tests)
npx vitest run

# Start the matcher (dev mode)
npx tsx watch src/index.ts
```

### 4. Frontend

```bash
cd frontend

# Install dependencies
npm install

# Create environment file
cp .env.example .env
# Edit .env:
#   NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your_project_id
#   NEXT_PUBLIC_VAULT_ADDRESS=0xAe76085867146f76932A0711059450a01CE7e4A3
#   NEXT_PUBLIC_ENGINE_ADDRESS=0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d

# Start development server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) in your browser.

---

## Environment Variables

### contracts/.env

```
PRIVATE_KEY=0x...                                    # Deployer private key
MONAD_TESTNET_RPC_URL=https://testnet-rpc.monad.xyz  # Monad RPC
```

### matcher/.env

```
MONAD_RPC_URL=https://testnet-rpc.monad.xyz          # Monad RPC
MATCHER_PRIVATE_KEY=0x...                            # Matcher wallet key
ENGINE_ADDRESS=0x...                                 # DarkBookEngine address
VAULT_ADDRESS=0x...                                  # Vault address
BATCH_INTERVAL_MS=2000                               # Settlement batch interval
MAX_MATCHES_PER_BATCH=16                             # Max matches per batch
ECDH_PRIVATE_KEY=...                                 # 32-byte hex (no 0x prefix)
WS_PORT=8080                                         # WebSocket port
```

### frontend/.env

```
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=...             # WalletConnect project ID
NEXT_PUBLIC_MATCHER_WS_URL=ws://localhost:8080        # Matcher WebSocket
NEXT_PUBLIC_MATCHER_API_URL=http://localhost:3001      # Matcher API
NEXT_PUBLIC_VERIFIER_ADDRESS=0x...                    # UltraPlonkVerifier
NEXT_PUBLIC_VAULT_ADDRESS=0x...                       # Vault
NEXT_PUBLIC_ENGINE_ADDRESS=0x...                      # DarkBookEngine
```

---

## Running Tests

### Smart Contract Tests (Foundry)

```bash
cd contracts

# Run all 42 tests
forge test -vvv

# Run only unit tests
forge test --match-contract DarkBookEngineTest -vvv

# Run E2E happy-flow tests
forge test --match-contract E2EHappyFlowTest -vvv

# Run worst-case attack scenario tests
forge test --match-contract WorstCaseTest -vvv

# Run with gas report
forge test --gas-report
```

### Matcher Tests (Vitest)

```bash
cd matcher

# Run all 17 tests
npx vitest run

# Run in watch mode
npx vitest
```

---

## Test Coverage

### Foundry Tests — 42/42 passing

**Unit Tests (14):**
- Deposit, deposit reverts (unsupported token, zero amount)
- Order submission, reverts (duplicate nullifier, duplicate commitment, invalid pair)
- Cancellation, reverts (not owner)
- Settlement, reverts (unauthorized matcher)
- Admin: epoch advancement, matcher authorization/revocation

**E2E Happy Flow (5):**
- Full flow: deposit -> submit -> match -> settle -> verify
- Multiple deposits from same user
- Multiple orders + multiple matches in sequence
- Cancel and re-submit flow
- Epoch tracking across submissions

**Worst Case / Attack Scenarios (23):**
- Double-submit (same nullifier, same commitment)
- Unauthorized settlement, cancellation, admin access
- Invalid state transitions (settle filled/cancelled orders, double cancel)
- Vault edge cases (unsupported token, zero deposit, overflow, zero addresses)
- Token pair validation
- Matcher management (revoke, permissionless mode)
- Settlement record integrity
- Gas benchmarks (submitOrder: ~245k, settleMatch: ~155k)

### Matcher Tests — 17/17 passing

- Order insertion + sorting (buy descending, sell ascending)
- Crossing order matching + midpoint pricing
- Non-crossing orders stay in book
- Partial fills
- Multi-order sequential matching
- Cross-pair isolation
- Order removal (cancellation)
- Best bid/ask queries
- Pending match tracking + clearing

---

## How It Works

### Order Submission Flow

1. User enters order (price, amount, side) in the frontend
2. Frontend generates a random salt
3. Computes commitment = `Pedersen(price, amount, side, salt)`
4. Computes nullifier = `Pedersen(salt, sender_secret)`
5. Fetches balance root from Vault contract
6. Generates ZK proof in browser via Noir.js WASM (~2-5 seconds)
7. Submits `(commitment, nullifier, tokenPairId, proof)` to DarkBookEngine
8. Encrypts order details and sends to matcher via ECDH channel

### Matching Flow

1. Matcher decrypts order details
2. Adds to in-memory orderbook (price-time priority)
3. Checks for crossing orders on opposite side
4. If match found: computes fill amount and midpoint settlement price
5. Generates match_proof + balance_update proofs
6. Submits batched settlement to DarkBookEngine on Monad

### Settlement Flow

1. DarkBookEngine verifies match_proof (orders cross, valid fill)
2. Verifies balance_update proof (correct balance transitions)
3. Updates Vault balance root
4. Marks orders as Filled
5. Emits MatchSettled event

---

## Gas Costs (Monad Testnet)

| Operation | Gas | Estimated Cost |
|---|---|---|
| Deploy (all 3 contracts) | ~3.7M | ~0.75 MON |
| `submitOrder` | ~188-245k | ~0.05 MON |
| `settleMatch` | ~155k | ~0.03 MON |
| `cancelOrder` | ~30k | ~0.006 MON |
| `deposit` | ~250-310k | ~0.06 MON |

---

## Security Notes

- The **UltraPlonkVerifier** is currently a placeholder that returns `true` for all proofs. It **must** be replaced with the auto-generated verifier from `nargo codegen-verifier` before any mainnet deployment.
- The matcher sees plaintext orders (privacy is from other traders and on-chain observers, not from the matcher). Future upgrade path includes MPC-based matching.
- Nullifiers prevent double-submission of orders.
- Only authorized matchers can submit settlements (configurable via `setPermissionedMatching`).
- Balance root updates are restricted to the DarkBookEngine contract.

---

## Tech Stack

| Layer | Technology |
|---|---|
| ZK Circuits | Noir (nargo 0.30+) |
| Smart Contracts | Solidity 0.8.24 (Foundry) |
| Blockchain | Monad (EVM-compatible, 10k+ TPS) |
| Matcher | Node.js / TypeScript |
| Frontend | Next.js 14, Tailwind, shadcn/ui |
| Wallet | wagmi v2 + viem + RainbowKit |
| State Management | Zustand |
| ZK Browser Prover | @noir-lang/noir_js + @aztec/bb.js (WASM) |
| Encryption | @noble/curves (ECDH) + @noble/ciphers (AES-GCM) |
| Testing | Foundry (forge test), Vitest |
#   D A R K B O O K  
 