"use client";

// ============================================================
// Commitment Book — Displays on-chain opaque commitments
// ============================================================
// Shows a list of commitment hashes posted on-chain. No price
// or size is visible — only the hash, owner, epoch, and time.

import { cn, truncateHash, timeAgo } from "@/lib/utils";
import { useOrderStore, type CommitmentEntry } from "@/lib/stores/orderStore";

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

const STATUS_STYLES: Record<CommitmentEntry["status"], string> = {
  active: "bg-primary/15 text-primary",
  filled: "bg-bid/15 text-bid",
  cancelled: "bg-muted text-muted-foreground",
};

function StatusBadge({ status }: { status: CommitmentEntry["status"] }) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold capitalize",
        STATUS_STYLES[status]
      )}
    >
      {status}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

function CommitmentRow({ entry }: { entry: CommitmentEntry }) {
  return (
    <tr className="border-b border-border/20 last:border-0 hover:bg-muted/20 transition-colors">
      <td className="py-2 px-3 font-mono text-xs text-foreground">
        {truncateHash(entry.commitment, 8, 6)}
      </td>
      <td className="py-2 px-3 font-mono text-xs text-muted-foreground">
        {truncateHash(entry.owner, 6, 4)}
      </td>
      <td className="py-2 px-3 text-xs text-muted-foreground text-center">
        {entry.epoch}
      </td>
      <td className="py-2 px-3 text-xs text-muted-foreground text-right">
        {timeAgo(entry.timestamp)}
      </td>
      <td className="py-2 px-3 text-right">
        <StatusBadge status={entry.status} />
      </td>
    </tr>
  );
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function CommitmentBook() {
  const { commitments } = useOrderStore();

  return (
    <div className="rounded-xl border border-border/50 bg-card/30 backdrop-blur-md flex flex-col overflow-hidden">
      {/* Header */}
      <div className="px-4 py-3 border-b border-border/30">
        <h3 className="text-sm font-semibold text-muted-foreground tracking-wide uppercase">
          Commitment Book
        </h3>
        <p className="text-[11px] text-muted-foreground/60 mt-0.5">
          On-chain commitments — price &amp; size hidden by ZK proofs
        </p>
      </div>

      {/* Table */}
      {commitments.length === 0 ? (
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
              d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          <span className="text-xs">No active commitments</span>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead>
              <tr className="border-b border-border/30 bg-muted/10">
                <th className="py-2 px-3 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
                  Commitment
                </th>
                <th className="py-2 px-3 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">
                  Owner
                </th>
                <th className="py-2 px-3 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider text-center">
                  Epoch
                </th>
                <th className="py-2 px-3 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider text-right">
                  Time
                </th>
                <th className="py-2 px-3 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider text-right">
                  Status
                </th>
              </tr>
            </thead>
            <tbody>
              {commitments.map((entry) => (
                <CommitmentRow key={entry.commitment} entry={entry} />
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
