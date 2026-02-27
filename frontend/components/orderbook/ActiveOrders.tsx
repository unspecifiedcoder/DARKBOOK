"use client";

// ============================================================
// Active Orders — Shows the user's own decrypted orders
// ============================================================
// The user knows their own order params (price, amount, side),
// so we can display them in cleartext locally.

import { cn, formatNumber, truncateHash, timeAgo } from "@/lib/utils";
import {
  useOrderStore,
  type LocalOrder,
  type OrderStatus,
} from "@/lib/stores/orderStore";
import { ProofStatusIndicator } from "@/components/shared/ProofStatusIndicator";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const STATUS_LABEL: Record<OrderStatus, string> = {
  pending: "Pending",
  proving: "Proving",
  submitting: "Submitting",
  active: "Active",
  filled: "Filled",
  cancelled: "Cancelled",
  failed: "Failed",
};

const STATUS_STYLE: Record<OrderStatus, string> = {
  pending: "text-muted-foreground",
  proving: "text-primary",
  submitting: "text-primary",
  active: "text-bid",
  filled: "text-bid",
  cancelled: "text-muted-foreground",
  failed: "text-ask",
};

function isCancellable(status: OrderStatus): boolean {
  return status === "active" || status === "pending";
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

function OrderRow({
  order,
  onCancel,
}: {
  order: LocalOrder;
  onCancel: (id: string) => void;
}) {
  const isBuy = order.side === "buy";

  return (
    <tr className="border-b border-border/20 last:border-0 hover:bg-muted/20 transition-colors">
      {/* Side */}
      <td className="py-2.5 px-3">
        <span
          className={cn(
            "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-bold uppercase",
            isBuy ? "bg-bid/15 text-bid" : "bg-ask/15 text-ask"
          )}
        >
          {order.side}
        </span>
      </td>

      {/* Price */}
      <td className="py-2.5 px-3 font-mono text-xs text-foreground">
        {formatNumber(order.price, 2)}
      </td>

      {/* Amount */}
      <td className="py-2.5 px-3 font-mono text-xs text-foreground">
        {formatNumber(order.amount, 4)}
      </td>

      {/* Commitment (truncated) */}
      <td className="py-2.5 px-3 font-mono text-[11px] text-muted-foreground">
        {truncateHash(order.commitment, 6, 4)}
      </td>

      {/* Proof Status */}
      <td className="py-2.5 px-3">
        <ProofStatusIndicator status={order.proofStatus} />
      </td>

      {/* Order Status */}
      <td className={cn("py-2.5 px-3 text-xs font-medium", STATUS_STYLE[order.status])}>
        {STATUS_LABEL[order.status]}
      </td>

      {/* Time */}
      <td className="py-2.5 px-3 text-xs text-muted-foreground text-right">
        {timeAgo(order.timestamp)}
      </td>

      {/* Actions */}
      <td className="py-2.5 px-3 text-right">
        {isCancellable(order.status) ? (
          <button
            type="button"
            onClick={() => onCancel(order.id)}
            className="text-[11px] font-medium text-ask/80 hover:text-ask transition-colors"
          >
            Cancel
          </button>
        ) : (
          <span className="text-[11px] text-muted-foreground/40">—</span>
        )}
      </td>
    </tr>
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function ActiveOrders() {
  const { localOrders, updateLocalOrder } = useOrderStore();

  const handleCancel = (orderId: string) => {
    updateLocalOrder(orderId, { status: "cancelled", proofStatus: "idle" });
  };

  // Show most recent first
  const sorted = [...localOrders].sort((a, b) => b.timestamp - a.timestamp);

  return (
    <div className="rounded-xl border border-border/50 bg-card/30 backdrop-blur-md flex flex-col overflow-hidden">
      {/* Header */}
      <div className="px-4 py-3 border-b border-border/30 flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold text-muted-foreground tracking-wide uppercase">
            Your Orders
          </h3>
          <p className="text-[11px] text-muted-foreground/60 mt-0.5">
            Decrypted locally — only you can see price &amp; amount
          </p>
        </div>
        {localOrders.length > 0 && (
          <span className="text-[11px] text-muted-foreground bg-muted/30 rounded-full px-2 py-0.5">
            {localOrders.length}
          </span>
        )}
      </div>

      {/* Table */}
      {sorted.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-12 text-muted-foreground/50 gap-2">
          <svg
            className="w-8 h-8"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            strokeWidth={1.5}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M3.75 12h16.5m-16.5 3.75h16.5M3.75 19.5h16.5M5.625 4.5h12.75a1.875 1.875 0 010 3.75H5.625a1.875 1.875 0 010-3.75z"
            />
          </svg>
          <span className="text-xs">No orders yet</span>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="border-b border-border/30 bg-muted/10">
                {["Side", "Price", "Amount", "Commitment", "Proof", "Status", "Time", ""].map(
                  (h) => (
                    <th
                      key={h}
                      className="py-2 px-3 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider"
                    >
                      {h}
                    </th>
                  )
                )}
              </tr>
            </thead>
            <tbody>
              {sorted.map((order) => (
                <OrderRow key={order.id} order={order} onCancel={handleCancel} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
