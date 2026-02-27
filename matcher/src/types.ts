// ============================================================
// DarkBook Matcher — Type Definitions
// ============================================================

export type Side = 0 | 1; // 0 = buy, 1 = sell

export interface PlaintextOrder {
  /** Unique order identifier (commitment hash) */
  commitment: `0x${string}`;
  /** Limit price (scaled integer, e.g., 1e6 = 1 USDC) */
  price: bigint;
  /** Order size in base token units */
  amount: bigint;
  /** 0 = buy, 1 = sell */
  side: Side;
  /** Random salt for commitment hiding */
  salt: bigint;
  /** Owner address */
  owner: `0x${string}`;
  /** Trading pair identifier */
  tokenPairId: number;
  /** Submission timestamp */
  timestamp: number;
  /** On-chain submission tx hash */
  txHash: `0x${string}`;
}

export interface OrderBookEntry {
  order: PlaintextOrder;
  /** Remaining amount after partial fills */
  remainingAmount: bigint;
  /** Whether this order has been matched */
  isMatched: boolean;
}

export interface Match {
  /** Buy-side order */
  buyOrder: OrderBookEntry;
  /** Sell-side order */
  sellOrder: OrderBookEntry;
  /** Amount to fill */
  fillAmount: bigint;
  /** Settlement price (midpoint) */
  settlementPrice: bigint;
  /** Timestamp of match */
  timestamp: number;
}

export interface SettlementBatch {
  /** Matches to settle in this batch */
  matches: Match[];
  /** Batch identifier */
  batchId: number;
  /** Timestamp */
  timestamp: number;
}

export interface EncryptedOrder {
  /** Ciphertext of the order details */
  ciphertext: Uint8Array;
  /** Nonce/IV for AES-GCM */
  nonce: Uint8Array;
  /** Ephemeral public key for ECDH */
  ephemeralPubKey: Uint8Array;
  /** On-chain commitment hash for verification */
  commitment: `0x${string}`;
  /** Sender's address */
  sender: `0x${string}`;
}

export interface ProofResult {
  proof: Uint8Array;
  publicInputs: string[];
}

export interface SettlementResult {
  txHash: `0x${string}`;
  commitmentA: `0x${string}`;
  commitmentB: `0x${string}`;
  fillAmount: bigint;
  settlementPrice: bigint;
  success: boolean;
  gasUsed: bigint;
}

export interface MatcherConfig {
  /** RPC URL for Monad */
  rpcUrl: string;
  /** Private key for the matcher's wallet */
  privateKey: `0x${string}`;
  /** DarkBookEngine contract address */
  engineAddress: `0x${string}`;
  /** Vault contract address */
  vaultAddress: `0x${string}`;
  /** Batch interval in milliseconds */
  batchIntervalMs: number;
  /** Maximum matches per batch */
  maxMatchesPerBatch: number;
  /** Matcher's ECDH private key for encrypted order relay */
  ecdhPrivateKey: Uint8Array;
  /** WebSocket port for the indexer/API */
  wsPort: number;
}

export interface OrderSubmittedEvent {
  commitment: `0x${string}`;
  owner: `0x${string}`;
  tokenPairId: bigint;
  epoch: bigint;
  timestamp: bigint;
}

export interface MatchSettledEvent {
  commitmentA: `0x${string}`;
  commitmentB: `0x${string}`;
  fillAmount: bigint;
  settlementPrice: bigint;
  timestamp: bigint;
}
