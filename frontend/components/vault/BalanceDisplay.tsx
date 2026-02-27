"use client";

import { useAccount } from "wagmi";
import { useVaultStore } from "@/lib/stores/vaultStore";
import { formatNumber } from "@/lib/utils";

export function BalanceDisplay() {
  const { address } = useAccount();
  const { balances } = useVaultStore();

  if (!address) {
    return (
      <div className="glass-panel p-6 text-center">
        <p className="text-muted-foreground text-sm">
          Connect your wallet to view balances
        </p>
      </div>
    );
  }

  return (
    <div className="glass-panel p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold">Balances</h2>
        <span className="text-xs text-muted-foreground px-2 py-1 rounded bg-primary/10 text-primary">
          Decrypted locally
        </span>
      </div>

      {balances.length === 0 ? (
        <div className="text-center py-8">
          <p className="text-muted-foreground text-sm">No token balances</p>
          <p className="text-muted-foreground text-xs mt-1">
            Deposit tokens to get started
          </p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border/50">
                <th className="text-left py-2 text-muted-foreground font-medium">
                  Token
                </th>
                <th className="text-right py-2 text-muted-foreground font-medium">
                  Wallet
                </th>
                <th className="text-right py-2 text-muted-foreground font-medium">
                  Vault
                </th>
                <th className="text-right py-2 text-muted-foreground font-medium">
                  Pending
                </th>
              </tr>
            </thead>
            <tbody>
              {balances.map((b) => (
                <tr
                  key={b.token}
                  className="border-b border-border/30 last:border-0"
                >
                  <td className="py-3 font-medium">{b.symbol}</td>
                  <td className="py-3 text-right font-mono text-muted-foreground">
                    {formatNumber(b.walletBalance, 4)}
                  </td>
                  <td className="py-3 text-right font-mono">
                    {formatNumber(b.vaultBalance, 4)}
                  </td>
                  <td className="py-3 text-right font-mono">
                    {parseFloat(b.pendingDeposit) > 0 ? (
                      <span className="text-primary">
                        +{formatNumber(b.pendingDeposit, 4)}
                      </span>
                    ) : (
                      <span className="text-muted-foreground">-</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
