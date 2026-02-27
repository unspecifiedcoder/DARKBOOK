// ============================================================
// DarkBook Matcher — Settlement Service
// ============================================================
// Submits batched settlement transactions to Monad.
// Manages the flow: match → proof generation → on-chain settlement.

import {
  createWalletClient,
  createPublicClient,
  http,
  type WalletClient,
  type PublicClient,
  type Chain,
  type Transport,
  type Account,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type {
  Match,
  MatcherConfig,
  SettlementResult,
  SettlementBatch,
} from "./types.js";
import { ProverService } from "./prover.js";

// DarkBookEngine ABI (minimal — only settleMatch)
const ENGINE_ABI = [
  {
    name: "settleMatch",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "commitA", type: "bytes32" },
      { name: "commitB", type: "bytes32" },
      { name: "fillAmount", type: "uint256" },
      { name: "settlementPrice", type: "uint256" },
      { name: "matchProof", type: "bytes" },
      { name: "balanceProof", type: "bytes" },
    ],
    outputs: [],
  },
  {
    name: "getActiveCommitmentCount",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "tokenPairId", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

const VAULT_ABI = [
  {
    name: "getBalanceRoot",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bytes32" }],
  },
] as const;

// Monad chain definition
const monadTestnet: Chain = {
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://testnet-rpc.monad.xyz"] },
  },
  blockExplorers: {
    default: { name: "Monad Explorer", url: "https://testnet.monadexplorer.com" },
  },
};

export class SettlerService {
  private walletClient: WalletClient<Transport, Chain, Account>;
  private publicClient: PublicClient<Transport, Chain>;
  private prover: ProverService;
  private config: MatcherConfig;
  private batchCounter: number = 0;
  private isSettling: boolean = false;

  constructor(config: MatcherConfig, prover: ProverService) {
    this.config = config;
    this.prover = prover;

    const account = privateKeyToAccount(config.privateKey);

    this.walletClient = createWalletClient({
      account,
      chain: monadTestnet,
      transport: http(config.rpcUrl),
    });

    this.publicClient = createPublicClient({
      chain: monadTestnet,
      transport: http(config.rpcUrl),
    });
  }

  /**
   * Process a batch of matches: generate proofs and submit settlement txs
   */
  async settleBatch(matches: Match[]): Promise<SettlementResult[]> {
    if (this.isSettling) {
      console.log("[Settler] Already settling a batch, skipping...");
      return [];
    }

    if (matches.length === 0) return [];

    this.isSettling = true;
    this.batchCounter++;

    const batch: SettlementBatch = {
      matches: matches.slice(0, this.config.maxMatchesPerBatch),
      batchId: this.batchCounter,
      timestamp: Date.now(),
    };

    console.log(
      `[Settler] Processing batch #${batch.batchId} with ${batch.matches.length} matches`
    );

    const results: SettlementResult[] = [];

    try {
      // Get current balance root
      const balanceRoot = await this.publicClient.readContract({
        address: this.config.vaultAddress,
        abi: VAULT_ABI,
        functionName: "getBalanceRoot",
      });

      // Process each match
      for (const match of batch.matches) {
        try {
          const result = await this.settleMatch(match, balanceRoot as `0x${string}`);
          results.push(result);
        } catch (error) {
          console.error(
            `[Settler] Failed to settle match ${match.buyOrder.order.commitment} <> ${match.sellOrder.order.commitment}:`,
            error
          );
          results.push({
            txHash: "0x0" as `0x${string}`,
            commitmentA: match.buyOrder.order.commitment,
            commitmentB: match.sellOrder.order.commitment,
            fillAmount: match.fillAmount,
            settlementPrice: match.settlementPrice,
            success: false,
            gasUsed: 0n,
          });
        }
      }
    } finally {
      this.isSettling = false;
    }

    console.log(
      `[Settler] Batch #${batch.batchId} complete: ${results.filter((r) => r.success).length}/${results.length} succeeded`
    );

    return results;
  }

  /**
   * Settle a single match on-chain
   */
  private async settleMatch(
    match: Match,
    currentRoot: `0x${string}`
  ): Promise<SettlementResult> {
    // Generate proofs
    const matchProof = await this.prover.generateMatchProof(match);
    const newRoot =
      `0x${Buffer.from("new_root_placeholder").toString("hex").padStart(64, "0")}` as `0x${string}`;
    const balanceProof = await this.prover.generateBalanceUpdateProof(
      match,
      currentRoot,
      newRoot
    );

    // Submit settlement transaction
    const txHash = await this.walletClient.writeContract({
      address: this.config.engineAddress,
      abi: ENGINE_ABI,
      functionName: "settleMatch",
      args: [
        match.buyOrder.order.commitment as `0x${string}`,
        match.sellOrder.order.commitment as `0x${string}`,
        match.fillAmount,
        match.settlementPrice,
        `0x${Buffer.from(matchProof.proof).toString("hex")}` as `0x${string}`,
        `0x${Buffer.from(balanceProof.proof).toString("hex")}` as `0x${string}`,
      ],
    });

    console.log(`[Settler] Settlement tx submitted: ${txHash}`);

    // Wait for confirmation
    const receipt = await this.publicClient.waitForTransactionReceipt({
      hash: txHash,
    });

    return {
      txHash,
      commitmentA: match.buyOrder.order.commitment,
      commitmentB: match.sellOrder.order.commitment,
      fillAmount: match.fillAmount,
      settlementPrice: match.settlementPrice,
      success: receipt.status === "success",
      gasUsed: receipt.gasUsed,
    };
  }

  /**
   * Get the matcher's current nonce
   */
  async getNonce(): Promise<number> {
    return await this.publicClient.getTransactionCount({
      address: this.walletClient.account.address,
    });
  }
}
