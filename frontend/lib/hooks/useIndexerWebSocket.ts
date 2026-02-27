// ============================================================
// WebSocket Hook — Indexer Connection
// ============================================================
// Connects to the matcher's indexer WebSocket for live updates
// on commitments, settlements, and protocol state.

"use client";

import { useEffect, useRef, useCallback } from "react";
import { useOrderStore } from "@/lib/stores/orderStore";
import type { CommitmentEntry, Settlement } from "@/lib/stores/orderStore";

const WS_URL = process.env.NEXT_PUBLIC_MATCHER_WS_URL || "ws://localhost:8080";
const RECONNECT_INTERVAL = 3000;

export function useIndexerWebSocket() {
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const {
    setCommitments,
    addCommitment,
    removeCommitment,
    addSettlement,
    setSettlements,
    setConnected,
  } = useOrderStore();

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    try {
      const ws = new WebSocket(WS_URL);
      wsRef.current = ws;

      ws.onopen = () => {
        console.log("[WS] Connected to indexer");
        setConnected(true);

        // Request initial state
        ws.send(JSON.stringify({ type: "getCommitments", data: { tokenPairId: 1 } }));
        ws.send(JSON.stringify({ type: "getSettlements" }));
      };

      ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          handleMessage(msg);
        } catch (error) {
          console.error("[WS] Failed to parse message:", error);
        }
      };

      ws.onclose = () => {
        console.log("[WS] Disconnected from indexer");
        setConnected(false);
        scheduleReconnect();
      };

      ws.onerror = (error) => {
        console.error("[WS] Error:", error);
        ws.close();
      };
    } catch (error) {
      console.error("[WS] Connection failed:", error);
      scheduleReconnect();
    }
  }, [setConnected]);

  const handleMessage = useCallback(
    (msg: { type: string; data: unknown }) => {
      switch (msg.type) {
        case "snapshot": {
          const snapshot = msg.data as {
            activeCommitments: Record<string, string[]>;
            recentSettlements: Settlement[];
          };
          // Convert snapshot commitments to CommitmentEntry array
          const allCommitments: CommitmentEntry[] = [];
          for (const [pairId, hashes] of Object.entries(
            snapshot.activeCommitments
          )) {
            for (const hash of hashes) {
              allCommitments.push({
                commitment: hash,
                owner: "",
                tokenPairId: parseInt(pairId),
                epoch: 0,
                timestamp: Date.now(),
                status: "active",
              });
            }
          }
          setCommitments(allCommitments);
          setSettlements(snapshot.recentSettlements || []);
          break;
        }

        case "orderSubmitted": {
          const data = msg.data as CommitmentEntry;
          addCommitment(data);
          break;
        }

        case "orderCancelled": {
          const data = msg.data as { commitment: string };
          removeCommitment(data.commitment);
          break;
        }

        case "matchSettled": {
          const data = msg.data as Settlement;
          addSettlement(data);
          break;
        }

        case "commitments": {
          const data = msg.data as CommitmentEntry[];
          setCommitments(data);
          break;
        }

        case "settlements": {
          const data = msg.data as Settlement[];
          setSettlements(data);
          break;
        }
      }
    },
    [setCommitments, addCommitment, removeCommitment, addSettlement, setSettlements]
  );

  const scheduleReconnect = useCallback(() => {
    if (reconnectTimerRef.current) return;
    reconnectTimerRef.current = setTimeout(() => {
      reconnectTimerRef.current = null;
      connect();
    }, RECONNECT_INTERVAL);
  }, [connect]);

  useEffect(() => {
    connect();

    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
      if (reconnectTimerRef.current) {
        clearTimeout(reconnectTimerRef.current);
      }
    };
  }, [connect]);

  const sendMessage = useCallback((type: string, data?: unknown) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type, data }));
    }
  }, []);

  return { sendMessage };
}
