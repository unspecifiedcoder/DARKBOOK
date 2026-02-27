// ============================================================
// Wagmi + RainbowKit Configuration
// ============================================================

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { monadTestnet } from "./chains";

export const wagmiConfig = getDefaultConfig({
  appName: "DarkBook",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "demo",
  chains: [monadTestnet],
  ssr: true,
});
