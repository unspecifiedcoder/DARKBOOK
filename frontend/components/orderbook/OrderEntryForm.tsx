"use client";

// ============================================================
// Order Entry Form — Submit orders with ZK proof generation
// ============================================================

import { useState, useCallback, useRef, useEffect } from "react";
import { cn, formatNumber } from "@/lib/utils";
import { ClientProver, getProver, type OrderProofInputs } from "@/lib/noir/prover";
import {
  useOrderStore,
  type OrderSide,
  type ProofStatus,
  type LocalOrder,
} from "@/lib/stores/orderStore";
import { ProofStatusIndicator } from "@/components/shared/ProofStatusIndicator";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function generateSalt(): string {
  const buf = new Uint8Array(32);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function generateId(): string {
  return `order_${Date.now()}_${Math.random().toString(36).slice(2, 9)}`;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

interface OrderEntryFormProps {
  pair?: string;
}

export function OrderEntryForm({ pair }: OrderEntryFormProps) {
  // --- Local form state ---
  const [side, setSide] = useState<OrderSide>("buy");
  const [price, setPrice] = useState("");
  const [amount, setAmount] = useState("");
  const [proofStatus, setProofStatus] = useState<ProofStatus>("idle");
  const [error, setError] = useState<string | null>(null);

  // --- Store ---
  const { addLocalOrder, updateLocalOrder, activePairId } = useOrderStore();

  // --- Prover singleton (ref so it survives re-renders) ---
  const proverRef = useRef<ClientProver | null>(null);

  useEffect(() => {
    const prover = getProver();
    proverRef.current = prover;
    prover.initialize().catch((err) => {
      console.error("[OrderEntryForm] Prover init failed:", err);
    });
  }, []);

  // --- Derived values ---
  const priceNum = parseFloat(price) || 0;
  const amountNum = parseFloat(amount) || 0;
  const estimatedTotal = priceNum * amountNum;
  const isFormValid = priceNum > 0 && amountNum > 0;

  // --- Submit handler ---
  const handleSubmit = useCallback(async () => {
    if (!isFormValid) return;

    const orderId = generateId();
    const salt = generateSalt();
    // Placeholder commitment / nullifier — real values come from the circuit
    const commitment = `0x${salt.slice(0, 64)}`;
    const nullifier = `0x${salt.slice(32, 96).padEnd(64, "0")}`;

    const localOrder: LocalOrder = {
      id: orderId,
      commitment,
      nullifier,
      price,
      amount,
      side,
      salt,
      tokenPairId: activePairId,
      status: "proving",
      proofStatus: "generating",
      timestamp: Date.now(),
    };

    addLocalOrder(localOrder);
    setProofStatus("generating");
    setError(null);

    try {
      // --- 1. Generate ZK proof ---
      const prover = proverRef.current;
      if (!prover) throw new Error("Prover not initialized");

      const inputs: OrderProofInputs = {
        price,
        amount,
        side: side === "buy" ? "0" : "1",
        balance: "1000000000000000000000", // placeholder
        salt,
        senderSecret: salt.slice(0, 32),
        balanceLeafIndex: "0",
        balanceMerklePath: Array(16).fill("0x00"),
        commitment,
        balanceRoot: "0x00",
        nullifier,
        tokenPairId: activePairId.toString(),
      };

      await prover.generateOrderProof(inputs);

      updateLocalOrder(orderId, { proofStatus: "generated", status: "submitting" });
      setProofStatus("submitting");

      // --- 2. Submit on-chain (simulated) ---
      await new Promise((resolve) => setTimeout(resolve, 1500));

      updateLocalOrder(orderId, {
        proofStatus: "verified",
        status: "active",
        txHash: `0x${Array.from({ length: 64 }, () => Math.floor(Math.random() * 16).toString(16)).join("")}`,
      });
      setProofStatus("verified");

      // Reset form after success
      setTimeout(() => {
        setPrice("");
        setAmount("");
        setProofStatus("idle");
      }, 2000);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown error";
      updateLocalOrder(orderId, { proofStatus: "failed", status: "failed", error: message });
      setProofStatus("failed");
      setError(message);
    }
  }, [isFormValid, price, amount, side, activePairId, addLocalOrder, updateLocalOrder]);

  // --- Render ---
  return (
    <div className="rounded-xl border border-border/50 bg-card/30 backdrop-blur-md p-4 flex flex-col gap-4">
      {/* Header */}
      <h3 className="text-sm font-semibold text-muted-foreground tracking-wide uppercase">
        Place Order
      </h3>

      {/* Buy / Sell Toggle */}
      <div className="grid grid-cols-2 gap-1 rounded-lg bg-muted/30 p-1">
        <button
          type="button"
          onClick={() => setSide("buy")}
          className={cn(
            "py-2 rounded-md text-sm font-semibold transition-colors",
            side === "buy"
              ? "bg-bid/20 text-bid shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          )}
        >
          Buy
        </button>
        <button
          type="button"
          onClick={() => setSide("sell")}
          className={cn(
            "py-2 rounded-md text-sm font-semibold transition-colors",
            side === "sell"
              ? "bg-ask/20 text-ask shadow-sm"
              : "text-muted-foreground hover:text-foreground"
          )}
        >
          Sell
        </button>
      </div>

      {/* Price Input */}
      <div className="flex flex-col gap-1.5">
        <label className="text-xs text-muted-foreground font-medium">Price</label>
        <input
          type="number"
          min="0"
          step="any"
          placeholder="0.00"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          className={cn(
            "w-full rounded-lg border border-border/50 bg-background/50 px-3 py-2",
            "text-sm font-mono text-foreground placeholder:text-muted-foreground/50",
            "focus:outline-none focus:ring-1 focus:ring-primary/50"
          )}
        />
      </div>

      {/* Amount Input */}
      <div className="flex flex-col gap-1.5">
        <label className="text-xs text-muted-foreground font-medium">Amount</label>
        <input
          type="number"
          min="0"
          step="any"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className={cn(
            "w-full rounded-lg border border-border/50 bg-background/50 px-3 py-2",
            "text-sm font-mono text-foreground placeholder:text-muted-foreground/50",
            "focus:outline-none focus:ring-1 focus:ring-primary/50"
          )}
        />
      </div>

      {/* Estimated Total */}
      <div className="flex items-center justify-between text-xs text-muted-foreground px-1">
        <span>Est. Total</span>
        <span className="font-mono">
          {estimatedTotal > 0 ? formatNumber(estimatedTotal, 4) : "—"}
        </span>
      </div>

      {/* Proof Status */}
      {proofStatus !== "idle" && (
        <div className="flex items-center gap-2 px-1">
          <ProofStatusIndicator status={proofStatus} />
          <span className="text-xs text-muted-foreground capitalize">
            {proofStatus === "generating" && "Generating ZK proof..."}
            {proofStatus === "generated" && "Proof generated"}
            {proofStatus === "submitting" && "Submitting on-chain..."}
            {proofStatus === "verified" && "Order confirmed"}
            {proofStatus === "failed" && "Proof failed"}
          </span>
        </div>
      )}

      {/* Error */}
      {error && (
        <p className="text-xs text-ask px-1">{error}</p>
      )}

      {/* Submit Button */}
      <button
        type="button"
        disabled={!isFormValid || (proofStatus !== "idle" && proofStatus !== "failed" && proofStatus !== "verified")}
        onClick={handleSubmit}
        className={cn(
          "w-full py-2.5 rounded-lg text-sm font-semibold transition-all",
          "disabled:opacity-40 disabled:cursor-not-allowed",
          side === "buy"
            ? "bg-bid hover:bg-bid/90 text-black"
            : "bg-ask hover:bg-ask/90 text-white"
        )}
      >
        {proofStatus === "generating"
          ? "Generating Proof..."
          : proofStatus === "submitting"
            ? "Submitting..."
            : `Submit ${side === "buy" ? "Buy" : "Sell"} Order`}
      </button>
    </div>
  );
}
