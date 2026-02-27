"use client";

import { BalanceDisplay } from "@/components/vault/BalanceDisplay";
import { DepositForm } from "@/components/vault/DepositForm";
import { WithdrawForm } from "@/components/vault/WithdrawForm";

export default function VaultPage() {
  return (
    <div className="max-w-5xl mx-auto px-4 py-8">
      {/* Page Title */}
      <h1 className="text-3xl font-bold mb-8">Vault</h1>

      {/* Balance Display */}
      <div className="mb-8">
        <BalanceDisplay />
      </div>

      {/* Deposit & Withdraw Side by Side */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <DepositForm />
        <WithdrawForm />
      </div>
    </div>
  );
}
