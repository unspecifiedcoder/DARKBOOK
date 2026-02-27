"use client";

import { CommitmentBook } from "@/components/orderbook/CommitmentBook";
import { OrderEntryForm } from "@/components/orderbook/OrderEntryForm";
import { ActiveOrders } from "@/components/orderbook/ActiveOrders";
import { useParams } from "next/navigation";

export default function TradePage() {
  const params = useParams<{ pair: string }>();
  const pair = params.pair ?? "ETH-USDC";
  const displayPair = pair.replace("-", " / ");

  return (
    <div className="max-w-7xl mx-auto px-4 py-6">
      {/* Trading Pair Header */}
      <div className="flex items-center gap-3 mb-6">
        <h1 className="text-2xl font-bold">{displayPair}</h1>
        <span className="text-xs text-muted-foreground px-2 py-1 rounded bg-primary/10 text-primary">
          Dark Pool
        </span>
      </div>

      {/* 3-Column Trading Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* Column 1: Commitment Book */}
        <div className="lg:col-span-3">
          <CommitmentBook />
        </div>

        {/* Column 2: Order Entry Form */}
        <div className="lg:col-span-5">
          <OrderEntryForm pair={pair} />
        </div>

        {/* Column 3: Active Orders */}
        <div className="lg:col-span-4">
          <ActiveOrders />
        </div>
      </div>
    </div>
  );
}
