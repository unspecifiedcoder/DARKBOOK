// ============================================================
// DarkBook Matcher — ECDH Encryption for Order Relay
// ============================================================
// Implements the encrypted communication channel between users
// and the matcher using ECDH key exchange + AES-256-GCM.
//
// Flow:
// 1. Matcher publishes an ephemeral ECDH public key
// 2. User derives shared secret: ECDH(user_privkey, matcher_pubkey)
// 3. User encrypts order details with AES-256-GCM(shared_secret)
// 4. Matcher decrypts using its private key

import { secp256k1 } from "@noble/curves/secp256k1";
import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha256";
import { gcm } from "@noble/ciphers/aes";
import { randomBytes } from "@noble/ciphers/webcrypto";
import type { EncryptedOrder, PlaintextOrder } from "./types.js";

const HKDF_INFO = new TextEncoder().encode("darkbook-order-encryption-v1");
const HKDF_SALT = new TextEncoder().encode("darkbook-ecdh-salt");

export class EncryptionService {
  private privateKey: Uint8Array;
  private publicKey: Uint8Array;

  constructor(privateKey: Uint8Array) {
    this.privateKey = privateKey;
    this.publicKey = secp256k1.getPublicKey(privateKey, true); // compressed
  }

  /**
   * Get the matcher's public key (shared with users)
   */
  getPublicKey(): Uint8Array {
    return this.publicKey;
  }

  /**
   * Get the matcher's public key as hex string
   */
  getPublicKeyHex(): string {
    return Buffer.from(this.publicKey).toString("hex");
  }

  /**
   * Derive a shared AES-256 key from ECDH shared secret
   */
  private deriveSharedKey(
    otherPublicKey: Uint8Array
  ): Uint8Array {
    // Perform ECDH
    const sharedPoint = secp256k1.getSharedSecret(
      this.privateKey,
      otherPublicKey
    );

    // Derive AES key using HKDF
    const aesKey = hkdf(sha256, sharedPoint.slice(1), HKDF_SALT, HKDF_INFO, 32);
    return aesKey;
  }

  /**
   * Decrypt an encrypted order from a user
   */
  decryptOrder(encrypted: EncryptedOrder): PlaintextOrder {
    // Derive shared key from user's ephemeral public key
    const sharedKey = this.deriveSharedKey(encrypted.ephemeralPubKey);

    // Decrypt with AES-256-GCM
    const aes = gcm(sharedKey, encrypted.nonce);
    const plaintext = aes.decrypt(encrypted.ciphertext);

    // Parse the decrypted JSON
    const decoded = new TextDecoder().decode(plaintext);
    const parsed = JSON.parse(decoded);

    return {
      commitment: encrypted.commitment,
      price: BigInt(parsed.price),
      amount: BigInt(parsed.amount),
      side: parsed.side as 0 | 1,
      salt: BigInt(parsed.salt),
      owner: encrypted.sender,
      tokenPairId: parsed.tokenPairId,
      timestamp: Date.now(),
      txHash: parsed.txHash,
    };
  }

  /**
   * Encrypt order details (used by the frontend/client side)
   * This is a utility for testing; in production, the frontend encrypts.
   */
  static encryptForMatcher(
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
    commitment: `0x${string}`,
    sender: `0x${string}`
  ): EncryptedOrder {
    // Derive shared secret
    const sharedPoint = secp256k1.getSharedSecret(
      senderPrivateKey,
      matcherPublicKey
    );
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
    const nonce = randomBytes(12); // 96-bit nonce for GCM
    const aes = gcm(aesKey, nonce);
    const ciphertext = aes.encrypt(plaintext);

    // Get sender's ephemeral public key
    const ephemeralPubKey = secp256k1.getPublicKey(senderPrivateKey, true);

    return {
      ciphertext,
      nonce,
      ephemeralPubKey,
      commitment,
      sender,
    };
  }
}
