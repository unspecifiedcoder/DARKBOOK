// ============================================================
// DarkBook Matcher — Event Indexer
// ============================================================
// Listens to on-chain DarkBook contract events and maintains
// a shadow state. Serves data to the frontend via WebSocket.

import {
  createPublicClient,
  http,
  type PublicClient,
  type Chain,
  type Transport,
  type Log,
  parseAbiItem,
} from "viem";
import { WebSocketServer, WebSocket } from "ws";
import type {
  MatcherConfig,
  OrderSubmittedEvent,
  MatchSettledEvent,
} from "./types.js";

// Event ABIs
const ORDER_SUBMITTED_EVENT = parseAbiItem(
  "event OrderSubmitted(bytes32 indexed commitment, address indexed owner, uint256 indexed tokenPairId, uint256 epoch, uint256 timestamp)"
);
const ORDER_CANCELLED_EVENT = parseAbiItem(
  "event OrderCancelled(bytes32 indexed commitment, address indexed owner, uint256 timestamp)"
);
const MATCH_SETTLED_EVENT = parseAbiItem(
  "event MatchSettled(bytes32 indexed commitmentA, bytes32 indexed commitmentB, uint256 fillAmount, uint256 settlementPrice, uint256 timestamp)"
);

const monadTestnet: Chain = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://testnet-rpc.monad.xyz"] },
  },
};

interface IndexerState {
  /** Active commitments by token pair */
  activeCommitments: Map<number, Set<string>>;
  /** All commitments with metadata */
  commitmentDetails: Map<
    string,
    {
      owner: string;
      tokenPairId: number;
      epoch: number;
      timestamp: number;
      status: "active" | "cancelled" | "filled";
    }
  >;
  /** Settlement history */
  settlements: MatchSettledEvent[];
  /** Latest processed block */
  lastBlock: bigint;
  /** Current balance root */
  balanceRoot: string;
}

export class IndexerService {
  private client: PublicClient<Transport, Chain>;
  private config: MatcherConfig;
  private state: IndexerState;
  private wss: WebSocketServer | null = null;
  private subscribers: Set<WebSocket> = new Set();

  constructor(config: MatcherConfig) {
    this.config = config;

    this.client = createPublicClient({
      chain: monadTestnet,
      transport: http(config.rpcUrl),
    });

    this.state = {
      activeCommitments: new Map(),
      commitmentDetails: new Map(),
      settlements: [],
      lastBlock: 0n,
      balanceRoot: "",
    };
  }

  /**
   * Start the indexer: begin listening to events and serving WebSocket API
   */
  async start(): Promise<void> {
    console.log("[Indexer] Starting event indexer...");

    // Start WebSocket server
    this.startWebSocketServer();

    // Start polling for events (fallback for chains without WS support)
    this.pollEvents();

    console.log(`[Indexer] WebSocket server started on port ${this.config.wsPort}`);
  }

  /**
   * Start the WebSocket server for frontend connections
   */
  private startWebSocketServer(): void {
    this.wss = new WebSocketServer({ port: this.config.wsPort });

    this.wss.on("connection", (ws: WebSocket) => {
      console.log("[Indexer] New WebSocket client connected");
      this.subscribers.add(ws);

      // Send current state snapshot
      ws.send(
        JSON.stringify({
          type: "snapshot",
          data: this.getStateSnapshot(),
        })
      );

      ws.on("close", () => {
        this.subscribers.delete(ws);
        console.log("[Indexer] WebSocket client disconnected");
      });

      ws.on("message", (message: Buffer) => {
        try {
          const msg = JSON.parse(message.toString());
          this.handleClientMessage(ws, msg);
        } catch {
          ws.send(JSON.stringify({ type: "error", message: "Invalid message" }));
        }
      });
    });
  }

  /**
   * Handle incoming client WebSocket messages
   */
  private handleClientMessage(
    ws: WebSocket,
    msg: { type: string; data?: unknown }
  ): void {
    switch (msg.type) {
      case "getCommitments": {
        const tokenPairId = (msg.data as { tokenPairId: number })?.tokenPairId;
        const commitments = this.getCommitmentsForPair(tokenPairId);
        ws.send(
          JSON.stringify({ type: "commitments", data: commitments })
        );
        break;
      }
      case "getSettlements": {
        ws.send(
          JSON.stringify({
            type: "settlements",
            data: this.state.settlements.slice(-100),
          })
        );
        break;
      }
      case "getStats": {
        ws.send(
          JSON.stringify({ type: "stats", data: this.getStats() })
        );
        break;
      }
      default:
        ws.send(
          JSON.stringify({ type: "error", message: `Unknown type: ${msg.type}` })
        );
    }
  }

  /**
   * Poll for new events (runs continuously)
   */
  private async pollEvents(): Promise<void> {
    const pollInterval = 2000; // 2 seconds (Monad block time)

    const poll = async () => {
      try {
        const latestBlock = await this.client.getBlockNumber();

        if (latestBlock > this.state.lastBlock) {
          const fromBlock = this.state.lastBlock + 1n;
          const toBlock = latestBlock;

          // Fetch order submitted events
          await this.fetchOrderSubmittedEvents(fromBlock, toBlock);

          // Fetch match settled events
          await this.fetchMatchSettledEvents(fromBlock, toBlock);

          // Fetch cancellation events
          await this.fetchCancellationEvents(fromBlock, toBlock);

          this.state.lastBlock = latestBlock;
        }
      } catch (error) {
        console.error("[Indexer] Poll error:", error);
      }

      setTimeout(poll, pollInterval);
    };

    poll();
  }

  /**
   * Fetch and process OrderSubmitted events
   */
  private async fetchOrderSubmittedEvents(
    fromBlock: bigint,
    toBlock: bigint
  ): Promise<void> {
    try {
      const logs = await this.client.getLogs({
        address: this.config.engineAddress,
        event: ORDER_SUBMITTED_EVENT,
        fromBlock,
        toBlock,
      });

      for (const log of logs) {
        const commitment = log.args.commitment as string;
        const owner = log.args.owner as string;
        const tokenPairId = Number(log.args.tokenPairId);
        const epoch = Number(log.args.epoch);
        const timestamp = Number(log.args.timestamp);

        // Update state
        if (!this.state.activeCommitments.has(tokenPairId)) {
          this.state.activeCommitments.set(tokenPairId, new Set());
        }
        this.state.activeCommitments.get(tokenPairId)!.add(commitment);

        this.state.commitmentDetails.set(commitment, {
          owner,
          tokenPairId,
          epoch,
          timestamp,
          status: "active",
        });

        // Broadcast to subscribers
        this.broadcast({
          type: "orderSubmitted",
          data: { commitment, owner, tokenPairId, epoch, timestamp },
        });
      }
    } catch (error) {
      console.error("[Indexer] Error fetching OrderSubmitted events:", error);
    }
  }

  /**
   * Fetch and process MatchSettled events
   */
  private async fetchMatchSettledEvents(
    fromBlock: bigint,
    toBlock: bigint
  ): Promise<void> {
    try {
      const logs = await this.client.getLogs({
        address: this.config.engineAddress,
        event: MATCH_SETTLED_EVENT,
        fromBlock,
        toBlock,
      });

      for (const log of logs) {
        const settlement: MatchSettledEvent = {
          commitmentA: log.args.commitmentA as `0x${string}`,
          commitmentB: log.args.commitmentB as `0x${string}`,
          fillAmount: log.args.fillAmount as bigint,
          settlementPrice: log.args.settlementPrice as bigint,
          timestamp: log.args.timestamp as bigint,
        };

        this.state.settlements.push(settlement);

        // Update commitment statuses
        const detailsA = this.state.commitmentDetails.get(settlement.commitmentA);
        const detailsB = this.state.commitmentDetails.get(settlement.commitmentB);
        if (detailsA) {
          detailsA.status = "filled";
          const pairCommitments = this.state.activeCommitments.get(detailsA.tokenPairId);
          pairCommitments?.delete(settlement.commitmentA);
        }
        if (detailsB) {
          detailsB.status = "filled";
          const pairCommitments = this.state.activeCommitments.get(detailsB.tokenPairId);
          pairCommitments?.delete(settlement.commitmentB);
        }

        this.broadcast({
          type: "matchSettled",
          data: {
            ...settlement,
            fillAmount: settlement.fillAmount.toString(),
            settlementPrice: settlement.settlementPrice.toString(),
            timestamp: settlement.timestamp.toString(),
          },
        });
      }
    } catch (error) {
      console.error("[Indexer] Error fetching MatchSettled events:", error);
    }
  }

  /**
   * Fetch and process OrderCancelled events
   */
  private async fetchCancellationEvents(
    fromBlock: bigint,
    toBlock: bigint
  ): Promise<void> {
    try {
      const logs = await this.client.getLogs({
        address: this.config.engineAddress,
        event: ORDER_CANCELLED_EVENT,
        fromBlock,
        toBlock,
      });

      for (const log of logs) {
        const commitment = log.args.commitment as string;
        const details = this.state.commitmentDetails.get(commitment);
        if (details) {
          details.status = "cancelled";
          const pairCommitments = this.state.activeCommitments.get(details.tokenPairId);
          pairCommitments?.delete(commitment);
        }

        this.broadcast({
          type: "orderCancelled",
          data: { commitment },
        });
      }
    } catch (error) {
      console.error("[Indexer] Error fetching OrderCancelled events:", error);
    }
  }

  /**
   * Broadcast a message to all WebSocket subscribers
   */
  private broadcast(message: object): void {
    const payload = JSON.stringify(message);
    for (const ws of this.subscribers) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(payload);
      }
    }
  }

  /**
   * Get a snapshot of the current indexer state
   */
  private getStateSnapshot(): object {
    const commitmentsByPair: Record<number, string[]> = {};
    for (const [pairId, commitments] of this.state.activeCommitments) {
      commitmentsByPair[pairId] = Array.from(commitments);
    }

    return {
      activeCommitments: commitmentsByPair,
      recentSettlements: this.state.settlements.slice(-20).map((s) => ({
        ...s,
        fillAmount: s.fillAmount.toString(),
        settlementPrice: s.settlementPrice.toString(),
        timestamp: s.timestamp.toString(),
      })),
      lastBlock: this.state.lastBlock.toString(),
      stats: this.getStats(),
    };
  }

  /**
   * Get commitments for a specific trading pair
   */
  private getCommitmentsForPair(tokenPairId: number): object[] {
    const commitments = this.state.activeCommitments.get(tokenPairId);
    if (!commitments) return [];

    return Array.from(commitments).map((c) => ({
      commitment: c,
      ...this.state.commitmentDetails.get(c),
    }));
  }

  /**
   * Get protocol statistics
   */
  private getStats(): object {
    let totalActive = 0;
    for (const commitments of this.state.activeCommitments.values()) {
      totalActive += commitments.size;
    }

    return {
      totalActiveCommitments: totalActive,
      totalSettlements: this.state.settlements.length,
      pairsTracked: this.state.activeCommitments.size,
      lastBlock: this.state.lastBlock.toString(),
    };
  }

  /**
   * Stop the indexer
   */
  async stop(): Promise<void> {
    if (this.wss) {
      this.wss.close();
    }
    console.log("[Indexer] Stopped");
  }
}
