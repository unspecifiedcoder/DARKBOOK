"use client";

// ============================================================
// Proof Status Indicator — ZK proof generation progress
// ============================================================

import { cn } from "@/lib/utils";
import type { ProofStatus } from "@/lib/stores/orderStore";

interface ProofStatusIndicatorProps {
  status: ProofStatus;
  /** Optional extra class names */
  className?: string;
}

const STATUS_CONFIG: Record<
  ProofStatus,
  { color: string; bg: string; label: string; pulse: boolean }
> = {
  idle: {
    color: "bg-muted-foreground/50",
    bg: "",
    label: "Idle",
    pulse: false,
  },
  generating: {
    color: "bg-primary",
    bg: "bg-primary/15",
    label: "Generating",
    pulse: true,
  },
  generated: {
    color: "bg-primary",
    bg: "bg-primary/15",
    label: "Generated",
    pulse: false,
  },
  submitting: {
    color: "bg-yellow-400",
    bg: "bg-yellow-400/15",
    label: "Submitting",
    pulse: true,
  },
  verified: {
    color: "bg-bid",
    bg: "bg-bid/15",
    label: "Verified",
    pulse: false,
  },
  failed: {
    color: "bg-ask",
    bg: "bg-ask/15",
    label: "Failed",
    pulse: false,
  },
};

export function ProofStatusIndicator({ status, className }: ProofStatusIndicatorProps) {
  const config = STATUS_CONFIG[status];

  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[10px] font-semibold",
        config.bg || "bg-muted/30",
        className
      )}
      title={config.label}
    >
      {/* Dot */}
      <span className="relative flex h-2 w-2">
        {config.pulse && (
          <span
            className={cn(
              "absolute inset-0 rounded-full opacity-75 animate-ping",
              config.color
            )}
          />
        )}
        <span className={cn("relative inline-flex h-2 w-2 rounded-full", config.color)} />
      </span>

      {/* Label */}
      <span
        className={cn(
          "leading-none",
          status === "verified" && "text-bid",
          status === "failed" && "text-ask",
          status === "generating" && "text-primary",
          status === "generated" && "text-primary",
          status === "submitting" && "text-yellow-400",
          status === "idle" && "text-muted-foreground"
        )}
      >
        {config.label}
      </span>
    </span>
  );
}
