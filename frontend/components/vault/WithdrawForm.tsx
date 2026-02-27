"use client";

import { useState, useCallback } from "react";
import { useAccount } from "wagmi";
import { useVaultStore, type TokenBalance } from "@/lib/stores/vaultStore";
import { formatNumber } from "@/lib/utils";

export function WithdrawForm() {
  const { address } = useAccount();
  const { balances, isWithdrawing, setWithdrawing } = useVaultStore();

  const [selectedToken, setSelectedToken] = useState<TokenBalance | null>(
    balances[0] ?? null
  );
  const [amount, setAmount] = useState("");
  const [proofStatus, setProofStatus] = useState<
    "idle" | "generating" | "submitting"
  >("idle");

  const handleWithdraw = useCallback(async () => {
    if (!selectedToken || !amount || parseFloat(amount) <= 0) return;

    try {
      setWithdrawing(true);
      setProofStatus("generating");

      // ZK proof generation would happen here via the Noir WASM prover
      // For now this is a placeholder for the proof generation flow
      await new Promise((resolve) => setTimeout(resolve, 1500));

      setProofStatus("submitting");

      // The actual withdrawal contract call with the ZK proof would go here
      // writeContract({ address: vault, abi: VAULT_ABI, functionName: "withdraw", args: [...] })
      await new Promise((resolve) => setTimeout(resolve, 1500));

      setAmount("");
      setProofStatus("idle");
    } catch (error) {
      console.error("Withdrawal failed:", error);
      setProofStatus("idle");
    } finally {
      setWithdrawing(false);
    }
  }, [selectedToken, amount, setWithdrawing]);

  const isLoading = isWithdrawing || proofStatus !== "idle";
  const canWithdraw =
    !!address &&
    !!selectedToken &&
    !!amount &&
    parseFloat(amount) > 0 &&
    parseFloat(amount) <= parseFloat(selectedToken.vaultBalance || "0");

  return (
    <div className="glass-panel p-6">
      <h2 className="text-lg font-semibold mb-4">Withdraw</h2>

      {/* ZK Proof Notice */}
      <div className="mb-4 p-3 rounded-md bg-primary/5 border border-primary/20">
        <div className="flex items-start gap-2">
          <span className="text-primary text-sm mt-0.5">&#9670;</span>
          <div>
            <p className="text-xs font-medium text-primary">
              ZK Proof Required
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">
              Withdrawals generate a ZK proof client-side to verify your balance
              without revealing it on-chain.
            </p>
          </div>
        </div>
      </div>

      {/* Token Selector */}
      <div className="mb-4">
        <label className="block text-sm text-muted-foreground mb-1.5">
          Token
        </label>
        <select
          value={selectedToken?.token ?? ""}
          onChange={(e) => {
            const token = balances.find((b) => b.token === e.target.value);
            setSelectedToken(token ?? null);
            setAmount("");
          }}
          className="w-full bg-background border border-border rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
          disabled={isLoading}
        >
          {balances.length === 0 && (
            <option value="" disabled>
              No tokens available
            </option>
          )}
          {balances.map((b) => (
            <option key={b.token} value={b.token}>
              {b.symbol}
            </option>
          ))}
        </select>
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <label className="block text-sm text-muted-foreground mb-1.5">
          Amount
        </label>
        <div className="relative">
          <input
            type="number"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            placeholder="0.00"
            className="w-full bg-background border border-border rounded-md px-3 py-2 pr-16 text-sm focus:outline-none focus:ring-1 focus:ring-primary"
            disabled={!selectedToken || isLoading}
          />
          <button
            type="button"
            onClick={() => {
              if (selectedToken) setAmount(selectedToken.vaultBalance);
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs font-medium text-primary hover:text-primary/80 transition-colors px-2 py-0.5 rounded bg-primary/10"
            disabled={!selectedToken || isLoading}
          >
            Max
          </button>
        </div>
        {selectedToken && (
          <p className="text-xs text-muted-foreground mt-1">
            Vault balance: {formatNumber(selectedToken.vaultBalance, 4)}{" "}
            {selectedToken.symbol}
          </p>
        )}
      </div>

      {/* Submit Button */}
      <button
        onClick={handleWithdraw}
        disabled={!canWithdraw || isLoading}
        className="w-full py-2.5 rounded-md text-sm font-medium bg-primary text-primary-foreground hover:bg-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {isLoading ? (
          <span className="flex items-center justify-center gap-2">
            <span className="h-3 w-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
            {proofStatus === "generating"
              ? "Generating ZK Proof..."
              : proofStatus === "submitting"
              ? "Submitting Withdrawal..."
              : "Processing..."}
          </span>
        ) : (
          "Withdraw with ZK Proof"
        )}
      </button>

      {/* Validation Messages */}
      {selectedToken &&
        amount &&
        parseFloat(amount) > parseFloat(selectedToken.vaultBalance || "0") && (
          <p className="mt-2 text-xs text-ask text-center">
            Insufficient vault balance
          </p>
        )}

      {!address && (
        <p className="mt-3 text-xs text-muted-foreground text-center">
          Connect your wallet to withdraw
        </p>
      )}
    </div>
  );
}
