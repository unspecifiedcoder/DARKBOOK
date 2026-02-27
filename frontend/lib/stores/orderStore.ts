// ============================================================
// Zustand Store — Orderbook State
// ============================================================

import { create } from "zustand";

export type OrderSide = "buy" | "sell";
export type OrderStatus = "pending" | "proving" | "submitting" | "active" | "filled" | "cancelled" | "failed";
export type ProofStatus = "idle" | "generating" | "generated" | "submitting" | "verified" | "failed";

export interface LocalOrder {
  id: string;
  commitment: string;
  nullifier: string;
  price: string;
  amount: string;
  side: OrderSide;
  salt: string;
  tokenPairId: number;
  status: OrderStatus;
  proofStatus: ProofStatus;
  txHash?: string;
  timestamp: number;
  error?: string;
}

export interface CommitmentEntry {
  commitment: string;
  owner: string;
  tokenPairId: number;
  epoch: number;
  timestamp: number;
  status: "active" | "filled" | "cancelled";
}

export interface Settlement {
  commitmentA: string;
  commitmentB: string;
  fillAmount: string;
  settlementPrice: string;
  timestamp: number;
}

interface OrderStore {
  // User's own orders (decrypted locally)
  localOrders: LocalOrder[];
  
  // On-chain commitments (opaque, from indexer)
  commitments: CommitmentEntry[];
  
  // Settlement history
  settlements: Settlement[];
  
  // Active trading pair
  activePairId: number;
  
  // Connection state
  isConnected: boolean;
  
  // Actions
  addLocalOrder: (order: LocalOrder) => void;
  updateLocalOrder: (id: string, updates: Partial<LocalOrder>) => void;
  removeLocalOrder: (id: string) => void;
  setCommitments: (commitments: CommitmentEntry[]) => void;
  addCommitment: (commitment: CommitmentEntry) => void;
  removeCommitment: (commitmentHash: string) => void;
  addSettlement: (settlement: Settlement) => void;
  setSettlements: (settlements: Settlement[]) => void;
  setActivePairId: (pairId: number) => void;
  setConnected: (connected: boolean) => void;
}

export const useOrderStore = create<OrderStore>((set) => ({
  localOrders: [],
  commitments: [],
  settlements: [],
  activePairId: 1,
  isConnected: false,

  addLocalOrder: (order) =>
    set((state) => ({
      localOrders: [...state.localOrders, order],
    })),

  updateLocalOrder: (id, updates) =>
    set((state) => ({
      localOrders: state.localOrders.map((o) =>
        o.id === id ? { ...o, ...updates } : o
      ),
    })),

  removeLocalOrder: (id) =>
    set((state) => ({
      localOrders: state.localOrders.filter((o) => o.id !== id),
    })),

  setCommitments: (commitments) => set({ commitments }),

  addCommitment: (commitment) =>
    set((state) => ({
      commitments: [...state.commitments, commitment],
    })),

  removeCommitment: (commitmentHash) =>
    set((state) => ({
      commitments: state.commitments.filter(
        (c) => c.commitment !== commitmentHash
      ),
    })),

  addSettlement: (settlement) =>
    set((state) => ({
      settlements: [...state.settlements, settlement],
    })),

  setSettlements: (settlements) => set({ settlements }),

  setActivePairId: (pairId) => set({ activePairId: pairId }),

  setConnected: (connected) => set({ isConnected: connected }),
}));
