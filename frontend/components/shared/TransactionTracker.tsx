"use client";

// ============================================================
// Transaction Tracker — On-chain transaction status display
// ============================================================

import { cn, truncateHash } from "@/lib/utils";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type TransactionStatus = "pending" | "confirmed" | "failed";

interface TransactionTrackerProps {
  txHash: string;
  status: TransactionStatus;
  /** Override explorer base URL (defaults to Monad testnet explorer) */
  explorerUrl?: string;
  className?: string;
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const DEFAULT_EXPLORER = "https://testnet.monadexplorer.com";

const STATUS_CONFIG: Record<
  TransactionStatus,
  { dotColor: string; textColor: string; label: string; pulse: boolean }
> = {
  pending: {
    dotColor: "bg-yellow-400",
    textColor: "text-yellow-400",
    label: "Pending",
    pulse: true,
  },
  confirmed: {
    dotColor: "bg-bid",
    textColor: "text-bid",
    label: "Confirmed",
    pulse: false,
  },
  failed: {
    dotColor: "bg-ask",
    textColor: "text-ask",
    label: "Failed",
    pulse: false,
  },
};

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function TransactionTracker({
  txHash,
  status,
  explorerUrl = DEFAULT_EXPLORER,
  className,
}: TransactionTrackerProps) {
  const config = STATUS_CONFIG[status];
  const txUrl = `${explorerUrl}/tx/${txHash}`;

  return (
    <div
      className={cn(
        "inline-flex items-center gap-2 rounded-lg border border-border/40 bg-card/40 backdrop-blur-sm px-3 py-2",
        className
      )}
    >
      {/* Status dot */}
      <span className="relative flex h-2.5 w-2.5">
        {config.pulse && (
          <span
            className={cn(
              "absolute inset-0 rounded-full opacity-75 animate-ping",
              config.dotColor
            )}
          />
        )}
        <span className={cn("relative inline-flex h-2.5 w-2.5 rounded-full", config.dotColor)} />
      </span>

      {/* Status label */}
      <span className={cn("text-xs font-semibold", config.textColor)}>
        {config.label}
      </span>

      {/* Separator */}
      <span className="w-px h-3.5 bg-border/40" />

      {/* Transaction hash link */}
      <a
        href={txUrl}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-flex items-center gap-1 text-xs font-mono text-muted-foreground hover:text-foreground transition-colors"
      >
        {truncateHash(txHash, 6, 4)}
        {/* External link icon */}
        <svg
          className="w-3 h-3"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
          strokeWidth={2}
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-4.5-6h6m0 0v6m0-6L9.75 14.25"
          />
        </svg>
      </a>
    </div>
  );
}
