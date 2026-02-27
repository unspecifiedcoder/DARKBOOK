"use client";

import { useOrderStore } from "@/lib/stores/orderStore";
import { truncateHash, formatNumber, timeAgo } from "@/lib/utils";

export default function HistoryPage() {
  const { settlements } = useOrderStore();

  return (
    <div className="max-w-5xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-8">Trade History</h1>

      <div className="glass-panel overflow-hidden">
        {settlements.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20">
            <p className="text-muted-foreground text-sm mb-1">
              No settlements yet
            </p>
            <p className="text-muted-foreground/60 text-xs">
              Your matched trades will appear here
            </p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border/50 bg-muted/30">
                  <th className="text-left px-4 py-3 text-muted-foreground font-medium">
                    Commitment A
                  </th>
                  <th className="text-left px-4 py-3 text-muted-foreground font-medium">
                    Commitment B
                  </th>
                  <th className="text-right px-4 py-3 text-muted-foreground font-medium">
                    Fill Amount
                  </th>
                  <th className="text-right px-4 py-3 text-muted-foreground font-medium">
                    Price
                  </th>
                  <th className="text-right px-4 py-3 text-muted-foreground font-medium">
                    Time
                  </th>
                </tr>
              </thead>
              <tbody>
                {settlements.map((s, i) => (
                  <tr
                    key={`${s.commitmentA}-${s.commitmentB}-${i}`}
                    className="border-b border-border/30 last:border-0 hover:bg-muted/20 transition-colors"
                  >
                    <td className="px-4 py-3 font-mono text-xs">
                      {truncateHash(s.commitmentA)}
                    </td>
                    <td className="px-4 py-3 font-mono text-xs">
                      {truncateHash(s.commitmentB)}
                    </td>
                    <td className="px-4 py-3 text-right font-mono">
                      {formatNumber(s.fillAmount, 4)}
                    </td>
                    <td className="px-4 py-3 text-right font-mono">
                      {formatNumber(s.settlementPrice, 2)}
                    </td>
                    <td className="px-4 py-3 text-right text-muted-foreground">
                      {timeAgo(s.timestamp)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
