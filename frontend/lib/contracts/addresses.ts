// ============================================================
// DarkBook Contract Addresses
// ============================================================

export const CONTRACT_ADDRESSES = {
  // Monad Testnet
  10143: {
    verifier: "0x94De85a9737dba2f2C470Be46D0F77D3E9f3eb40" as `0x${string}`,
    vault: "0xAe76085867146f76932A0711059450a01CE7e4A3" as `0x${string}`,
    engine: "0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d" as `0x${string}`,
  },
} as const;

export type SupportedChainId = keyof typeof CONTRACT_ADDRESSES;

export function getContractAddresses(chainId: number) {
  const addresses = CONTRACT_ADDRESSES[chainId as SupportedChainId];
  if (!addresses) {
    throw new Error(`Unsupported chain ID: ${chainId}`);
  }
  return addresses;
}
