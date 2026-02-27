"use client";

import { useState, useCallback } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { parseUnits } from "viem";
import { useVaultStore, type TokenBalance } from "@/lib/stores/vaultStore";
import { VAULT_ABI, ERC20_ABI } from "@/lib/contracts/abis";
import { getContractAddresses } from "@/lib/contracts/addresses";
import { formatNumber } from "@/lib/utils";

type Step = "idle" | "approving" | "depositing";

export function DepositForm() {
  const { address, chainId } = useAccount();
  const { balances, setDepositing } = useVaultStore();

  const [selectedToken, setSelectedToken] = useState<TokenBalance | null>(
    balances[0] ?? null
  );
  const [amount, setAmount] = useState("");
  const [step, setStep] = useState<Step>("idle");

  const {
    writeContract: writeApprove,
    data: approveTxHash,
    isPending: isApprovePending,
  } = useWriteContract();

  const {
    writeContract: writeDeposit,
    data: depositTxHash,
    isPending: isDepositPending,
  } = useWriteContract();

  const { isPending: isApproveConfirming, isSuccess: isApproveConfirmed } =
    useWaitForTransactionReceipt({ hash: approveTxHash });

  const { isPending: isDepositConfirming, isSuccess: isDepositConfirmed } =
    useWaitForTransactionReceipt({ hash: depositTxHash });

  const addresses = chainId ? getContractAddresses(chainId) : null;

  const handleMaxClick = useCallback(() => {
    if (selectedToken) {
      setAmount(selectedToken.walletBalance);
    }
  }, [selectedToken]);

  const handleApprove = useCallback(() => {
    if (!selectedToken || !addresses || !amount) return;

    const parsedAmount = parseUnits(amount, selectedToken.decimals);
    setStep("approving");
    setDepositing(true);

    writeApprove(
      {
        address: selectedToken.token as `0x${string}`,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [addresses.vault, parsedAmount],
      },
      {
        onError: () => {
          setStep("idle");
          setDepositing(false);
        },
      }
    );
  }, [selectedToken, addresses, amount, writeApprove, setDepositing]);

  const handleDeposit = useCallback(() => {
    if (!selectedToken || !addresses || !amount) return;

    const parsedAmount = parseUnits(amount, selectedToken.decimals);
    setStep("depositing");

    writeDeposit(
      {
        address: addresses.vault,
        abi: VAULT_ABI,
        functionName: "deposit",
        args: [selectedToken.token as `0x${string}`, parsedAmount],
      },
      {
        onSuccess: () => {
          setAmount("");
          setStep("idle");
          setDepositing(false);
        },
        onError: () => {
          setStep("idle");
          setDepositing(false);
        },
      }
    );
  }, [selectedToken, addresses, amount, writeDeposit, setDepositing]);

  const isLoading =
    isApprovePending ||
    isApproveConfirming ||
    isDepositPending ||
    isDepositConfirming;

  const canApprove =
    !!address && !!selectedToken && !!amount && parseFloat(amount) > 0;

  const canDeposit = canApprove && (isApproveConfirmed || step === "depositing");

  return (
    <div className="glass-panel p-6">
      <h2 className="text-lg font-semibold mb-4">Deposit</h2>

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
            onClick={handleMaxClick}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs font-medium text-primary hover:text-primary/80 transition-colors px-2 py-0.5 rounded bg-primary/10"
            disabled={!selectedToken || isLoading}
          >
            Max
          </button>
        </div>
        {selectedToken && (
          <p className="text-xs text-muted-foreground mt-1">
            Wallet balance: {formatNumber(selectedToken.walletBalance, 4)}{" "}
            {selectedToken.symbol}
          </p>
        )}
      </div>

      {/* Two-Step Buttons */}
      <div className="flex gap-3">
        {/* Step 1: Approve */}
        <button
          onClick={handleApprove}
          disabled={!canApprove || isLoading || isApproveConfirmed}
          className={`flex-1 py-2.5 rounded-md text-sm font-medium transition-colors ${
            isApproveConfirmed
              ? "bg-bid/20 text-bid border border-bid/30"
              : "bg-secondary text-secondary-foreground hover:bg-secondary/80 disabled:opacity-50 disabled:cursor-not-allowed"
          }`}
        >
          {isApprovePending || isApproveConfirming ? (
            <span className="flex items-center justify-center gap-2">
              <span className="h-3 w-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
              {isApproveConfirming ? "Confirming..." : "Approving..."}
            </span>
          ) : isApproveConfirmed ? (
            "Approved"
          ) : (
            "1. Approve"
          )}
        </button>

        {/* Step 2: Deposit */}
        <button
          onClick={handleDeposit}
          disabled={!canDeposit || isDepositPending || isDepositConfirming}
          className="flex-1 py-2.5 rounded-md text-sm font-medium bg-primary text-primary-foreground hover:bg-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {isDepositPending || isDepositConfirming ? (
            <span className="flex items-center justify-center gap-2">
              <span className="h-3 w-3 border-2 border-current border-t-transparent rounded-full animate-spin" />
              {isDepositConfirming ? "Confirming..." : "Depositing..."}
            </span>
          ) : (
            "2. Deposit"
          )}
        </button>
      </div>

      {/* Status Messages */}
      {isDepositConfirmed && (
        <p className="mt-3 text-xs text-bid text-center">
          Deposit successful! Your vault balance will update shortly.
        </p>
      )}

      {!address && (
        <p className="mt-3 text-xs text-muted-foreground text-center">
          Connect your wallet to deposit
        </p>
      )}
    </div>
  );
}
