// ============================================================
// DarkBook Matcher — Main Entry Point
// ============================================================
// Orchestrates all matcher components: orderbook, prover,
// settler, encryption, and indexer.

import { config } from "dotenv";
import { OrderBook } from "./orderbook.js";
import { ProverService } from "./prover.js";
import { SettlerService } from "./settler.js";
import { EncryptionService } from "./encryption.js";
import { IndexerService } from "./indexer.js";
import type { MatcherConfig, PlaintextOrder, EncryptedOrder, Match } from "./types.js";

config(); // Load .env

class DarkBookMatcher {
  private orderBook: OrderBook;
  private prover: ProverService;
  private settler: SettlerService;
  private encryption: EncryptionService;
  private indexer: IndexerService;
  private config: MatcherConfig;
  private batchTimer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    // Load configuration from environment
    this.config = {
      rpcUrl: process.env.MONAD_RPC_URL || "https://testnet-rpc.monad.xyz",
      privateKey: (process.env.MATCHER_PRIVATE_KEY || "0x") as `0x${string}`,
      engineAddress: (process.env.ENGINE_ADDRESS || "0x") as `0x${string}`,
      vaultAddress: (process.env.VAULT_ADDRESS || "0x") as `0x${string}`,
      batchIntervalMs: parseInt(process.env.BATCH_INTERVAL_MS || "2000"),
      maxMatchesPerBatch: parseInt(process.env.MAX_MATCHES_PER_BATCH || "16"),
      ecdhPrivateKey: Buffer.from(
        process.env.ECDH_PRIVATE_KEY || "0".repeat(64),
        "hex"
      ),
      wsPort: parseInt(process.env.WS_PORT || "8080"),
    };

    // Initialize components
    this.orderBook = new OrderBook();
    this.prover = new ProverService();
    this.encryption = new EncryptionService(this.config.ecdhPrivateKey);
    this.settler = new SettlerService(this.config, this.prover);
    this.indexer = new IndexerService(this.config);
  }

  /**
   * Start the matcher service
   */
  async start(): Promise<void> {
    console.log("========================================");
    console.log("  DarkBook Matcher Service Starting...");
    console.log("========================================");

    // Initialize prover
    await this.prover.initialize();

    // Start indexer
    await this.indexer.start();

    // Start batch settlement loop
    this.startBatchLoop();

    console.log("[Matcher] Service started successfully");
    console.log(`[Matcher] ECDH Public Key: ${this.encryption.getPublicKeyHex()}`);
    console.log(`[Matcher] Batch interval: ${this.config.batchIntervalMs}ms`);
    console.log(`[Matcher] Max matches per batch: ${this.config.maxMatchesPerBatch}`);
    console.log("========================================");
  }

  /**
   * Handle an incoming encrypted order from a user
   */
  async handleEncryptedOrder(encrypted: EncryptedOrder): Promise<{
    success: boolean;
    matches: Match[];
    error?: string;
  }> {
    try {
      // Decrypt the order
      const order = this.encryption.decryptOrder(encrypted);

      console.log(
        `[Matcher] Received order: ${order.side === 0 ? "BUY" : "SELL"} ${order.amount} @ ${order.price} (pair ${order.tokenPairId})`
      );

      // Add to orderbook and check for matches
      const matches = this.orderBook.addOrder(order);

      if (matches.length > 0) {
        console.log(
          `[Matcher] Found ${matches.length} match(es) for order ${order.commitment}`
        );
      }

      return { success: true, matches };
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      console.error(`[Matcher] Error processing order:`, message);
      return { success: false, matches: [], error: message };
    }
  }

  /**
   * Handle a plaintext order (for testing/development)
   */
  handlePlaintextOrder(order: PlaintextOrder): Match[] {
    console.log(
      `[Matcher] Received plaintext order: ${order.side === 0 ? "BUY" : "SELL"} ${order.amount} @ ${order.price}`
    );

    return this.orderBook.addOrder(order);
  }

  /**
   * Cancel an order
   */
  cancelOrder(commitment: string): boolean {
    const removed = this.orderBook.removeOrder(commitment);
    if (removed) {
      console.log(`[Matcher] Order cancelled: ${commitment}`);
    }
    return removed;
  }

  /**
   * Start the batch settlement loop
   */
  private startBatchLoop(): void {
    this.batchTimer = setInterval(async () => {
      const pendingMatches = this.orderBook.getPendingMatches();

      if (pendingMatches.length === 0) return;

      console.log(
        `[Matcher] Batch tick: ${pendingMatches.length} pending matches`
      );

      try {
        const results = await this.settler.settleBatch(pendingMatches);

        // Clear settled matches
        const settledCount = results.filter((r) => r.success).length;
        this.orderBook.clearPendingMatches(settledCount);

        console.log(
          `[Matcher] Batch settled: ${settledCount}/${results.length} successful`
        );
      } catch (error) {
        console.error("[Matcher] Batch settlement error:", error);
      }
    }, this.config.batchIntervalMs);
  }

  /**
   * Get orderbook state for a pair
   */
  getOrderBookState(tokenPairId: number): {
    bids: { price: string; amount: string }[];
    asks: { price: string; amount: string }[];
    bestBid: string | null;
    bestAsk: string | null;
  } {
    const buyOrders = this.orderBook.getBuyOrders(tokenPairId);
    const sellOrders = this.orderBook.getSellOrders(tokenPairId);

    return {
      bids: buyOrders.map((o) => ({
        price: o.order.price.toString(),
        amount: o.remainingAmount.toString(),
      })),
      asks: sellOrders.map((o) => ({
        price: o.order.price.toString(),
        amount: o.remainingAmount.toString(),
      })),
      bestBid: this.orderBook.getBestBid(tokenPairId)?.toString() || null,
      bestAsk: this.orderBook.getBestAsk(tokenPairId)?.toString() || null,
    };
  }

  /**
   * Stop the matcher service
   */
  async stop(): Promise<void> {
    if (this.batchTimer) {
      clearInterval(this.batchTimer);
    }
    await this.indexer.stop();
    console.log("[Matcher] Service stopped");
  }
}

// ============================================================
// Main execution
// ============================================================

const matcher = new DarkBookMatcher();

matcher.start().catch((error) => {
  console.error("Failed to start matcher:", error);
  process.exit(1);
});

// Graceful shutdown
process.on("SIGINT", async () => {
  console.log("\nShutting down...");
  await matcher.stop();
  process.exit(0);
});

process.on("SIGTERM", async () => {
  await matcher.stop();
  process.exit(0);
});

export { DarkBookMatcher };
