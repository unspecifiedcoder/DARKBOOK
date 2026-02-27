"use client";

import Link from "next/link";

export default function Home() {
  return (
    <div className="min-h-[calc(100vh-8rem)] flex flex-col items-center justify-center px-4">
      {/* Hero */}
      <div className="text-center max-w-3xl mx-auto">
        <h1 className="text-5xl md:text-7xl font-bold tracking-tight mb-6">
          <span className="text-foreground">Dark</span>
          <span className="text-primary">Book</span>
        </h1>
        <p className="text-xl md:text-2xl text-muted-foreground mb-4">
          Privacy-Preserving Dark Pool on Monad
        </p>
        <p className="text-muted-foreground max-w-xl mx-auto mb-8">
          Trade with zero information leakage. Submit encrypted orders backed by
          ZK proofs — no one sees your price, size, or direction until settlement.
        </p>

        <div className="flex gap-4 justify-center">
          <Link
            href="/trade/ETH-USDC"
            className="px-8 py-3 bg-primary text-primary-foreground rounded-lg font-medium hover:bg-primary/90 transition-colors"
          >
            Start Trading
          </Link>
          <Link
            href="/vault"
            className="px-8 py-3 bg-secondary text-secondary-foreground rounded-lg font-medium hover:bg-secondary/80 transition-colors"
          >
            Deposit Funds
          </Link>
        </div>
      </div>

      {/* Feature Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-4xl mx-auto mt-20">
        <div className="glass-panel p-6">
          <h3 className="text-lg font-semibold mb-2">ZK Privacy</h3>
          <p className="text-sm text-muted-foreground">
            Orders are submitted as opaque commitments. ZK proofs verify validity
            without revealing price, size, or direction.
          </p>
        </div>
        <div className="glass-panel p-6">
          <h3 className="text-lg font-semibold mb-2">Monad Speed</h3>
          <p className="text-sm text-muted-foreground">
            10k+ TPS and 1s finality. Proof verification costs sub-cent vs $5-15
            on Ethereum L1.
          </p>
        </div>
        <div className="glass-panel p-6">
          <h3 className="text-lg font-semibold mb-2">Client-Side Proving</h3>
          <p className="text-sm text-muted-foreground">
            Generate ZK proofs directly in your browser using Noir WASM. Your
            secrets never leave your device.
          </p>
        </div>
      </div>

      {/* Stats Preview */}
      <div className="grid grid-cols-3 gap-8 max-w-2xl mx-auto mt-16 text-center">
        <div>
          <p className="text-2xl font-bold text-primary">{"<"}5s</p>
          <p className="text-xs text-muted-foreground mt-1">Order Submission</p>
        </div>
        <div>
          <p className="text-2xl font-bold text-primary">{"<"}300k</p>
          <p className="text-xs text-muted-foreground mt-1">Gas per Proof</p>
        </div>
        <div>
          <p className="text-2xl font-bold text-primary">100%</p>
          <p className="text-xs text-muted-foreground mt-1">Private Orders</p>
        </div>
      </div>
    </div>
  );
}
