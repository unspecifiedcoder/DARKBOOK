// ============================================================
// Zustand Store — Vault / Balance State
// ============================================================

import { create } from "zustand";

export interface TokenBalance {
  token: string;
  symbol: string;
  decimals: number;
  walletBalance: string;
  vaultBalance: string;
  pendingDeposit: string;
}

interface VaultStore {
  // User's token balances
  balances: TokenBalance[];
  
  // Current balance Merkle root
  balanceRoot: string;
  
  // Loading states
  isDepositing: boolean;
  isWithdrawing: boolean;
  
  // Actions
  setBalances: (balances: TokenBalance[]) => void;
  updateBalance: (token: string, updates: Partial<TokenBalance>) => void;
  setBalanceRoot: (root: string) => void;
  setDepositing: (loading: boolean) => void;
  setWithdrawing: (loading: boolean) => void;
}

export const useVaultStore = create<VaultStore>((set) => ({
  balances: [],
  balanceRoot: "",
  isDepositing: false,
  isWithdrawing: false,

  setBalances: (balances) => set({ balances }),

  updateBalance: (token, updates) =>
    set((state) => ({
      balances: state.balances.map((b) =>
        b.token === token ? { ...b, ...updates } : b
      ),
    })),

  setBalanceRoot: (root) => set({ balanceRoot: root }),
  setDepositing: (loading) => set({ isDepositing: loading }),
  setWithdrawing: (loading) => set({ isWithdrawing: loading }),
}));
