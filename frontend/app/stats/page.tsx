"use client";

interface StatCard {
  label: string;
  value: string;
  subtext: string;
}

const STATS: StatCard[] = [
  {
    label: "Total Value Locked",
    value: "$0.00",
    subtext: "Across all vaults",
  },
  {
    label: "Total Volume",
    value: "$0.00",
    subtext: "All-time traded",
  },
  {
    label: "Total Settlements",
    value: "0",
    subtext: "Matched orders",
  },
  {
    label: "Active Commitments",
    value: "0",
    subtext: "Open on-chain",
  },
];

export default function StatsPage() {
  return (
    <div className="max-w-5xl mx-auto px-4 py-8">
      <h1 className="text-3xl font-bold mb-8">Protocol Statistics</h1>

      {/* Stat Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        {STATS.map((stat) => (
          <div key={stat.label} className="glass-panel p-6">
            <p className="text-xs text-muted-foreground uppercase tracking-wider mb-2">
              {stat.label}
            </p>
            <p className="text-2xl font-bold">{stat.value}</p>
            <p className="text-xs text-muted-foreground mt-1">{stat.subtext}</p>
          </div>
        ))}
      </div>

      {/* Additional Info */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="glass-panel p-6">
          <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider mb-4">
            Network
          </h2>
          <div className="space-y-3">
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Chain</span>
              <span>Monad Testnet</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Chain ID</span>
              <span className="font-mono">10143</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Block Time</span>
              <span>~1s</span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-muted-foreground">Proof System</span>
              <span>Noir / UltraPlonk</span>
            </div>
          </div>
        </div>

        <div className="glass-panel p-6">
          <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider mb-4">
            Trading Pairs
          </h2>
          <div className="space-y-3">
            <div className="flex justify-between items-center text-sm">
              <span>ETH / USDC</span>
              <span className="text-xs text-muted-foreground px-2 py-0.5 rounded bg-bid/10 text-bid">
                Active
              </span>
            </div>
            <div className="flex justify-between items-center text-sm">
              <span>WBTC / USDC</span>
              <span className="text-xs text-muted-foreground px-2 py-0.5 rounded bg-muted">
                Coming Soon
              </span>
            </div>
            <div className="flex justify-between items-center text-sm">
              <span>MON / USDC</span>
              <span className="text-xs text-muted-foreground px-2 py-0.5 rounded bg-muted">
                Coming Soon
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
