// ============================================================
// Client-Side ECDH Encryption for Order Relay
// ============================================================
// Encrypts order details before sending to the matcher.
// Uses ECDH key exchange with the matcher's public key.

import { secp256k1 } from "@noble/curves/secp256k1";
import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha256";
import { gcm } from "@noble/ciphers/aes";
import { randomBytes } from "@noble/ciphers/webcrypto";

const HKDF_INFO = new TextEncoder().encode("darkbook-order-encryption-v1");
const HKDF_SALT = new TextEncoder().encode("darkbook-ecdh-salt");

/** Convert Uint8Array to hex string (browser-safe, no Buffer needed) */
function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export interface EncryptedOrderPayload {
  ciphertext: string; // hex
  nonce: string; // hex
  ephemeralPubKey: string; // hex
  commitment: string;
  sender: string;
}

/**
 * Encrypt order details for the matcher
 */
export async function encryptOrderForMatcher(
  order: {
    price: bigint;
    amount: bigint;
    side: 0 | 1;
    salt: bigint;
    tokenPairId: number;
    txHash: string;
  },
  senderPrivateKey: Uint8Array,
  matcherPublicKey: Uint8Array,
  commitment: string,
  sender: string
): Promise<EncryptedOrderPayload> {
  // Derive shared secret via ECDH
  const sharedPoint = secp256k1.getSharedSecret(senderPrivateKey, matcherPublicKey);
  const aesKey = hkdf(sha256, sharedPoint.slice(1), HKDF_SALT, HKDF_INFO, 32);

  // Serialize order to JSON
  const payload = JSON.stringify({
    price: order.price.toString(),
    amount: order.amount.toString(),
    side: order.side,
    salt: order.salt.toString(),
    tokenPairId: order.tokenPairId,
    txHash: order.txHash,
  });

  const plaintext = new TextEncoder().encode(payload);

  // Encrypt with AES-256-GCM
  const nonce = randomBytes(12);
  const aes = gcm(aesKey, nonce);
  const ciphertext = aes.encrypt(plaintext);

  // Get sender's ephemeral public key
  const ephemeralPubKey = secp256k1.getPublicKey(senderPrivateKey, true);

  return {
    ciphertext: bytesToHex(ciphertext),
    nonce: bytesToHex(nonce),
    ephemeralPubKey: bytesToHex(ephemeralPubKey),
    commitment,
    sender,
  };
}

/**
 * Generate a random salt for order commitment
 */
export function generateSalt(): bigint {
  const bytes = randomBytes(31); // 31 bytes to stay within field
  let salt = 0n;
  for (const byte of bytes) {
    salt = (salt << 8n) | BigInt(byte);
  }
  return salt;
}

/**
 * Generate a sender secret (deterministic from private key)
 */
export function deriveSenderSecret(privateKey: Uint8Array): bigint {
  const hash = sha256(privateKey);
  let secret = 0n;
  for (let i = 0; i < 31; i++) {
    secret = (secret << 8n) | BigInt(hash[i]);
  }
  return secret;
}
