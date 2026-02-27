// Circuit 1: Order Commitment
// Proves an order is valid and funded without revealing parameters.
//
// A trader submits a commitment to an order (price, amount, side) along with
// a ZK proof that:
//   1. The commitment is correctly formed
//   2. They have sufficient balance in the vault
//   3. The nullifier prevents double-submission
//   4. Order parameters are valid (positive price/amount, valid side)

use dep::std;

mod lib;
use lib::merkle::{TREE_DEPTH, compute_merkle_root};
use lib::pedersen::{compute_order_commitment, compute_nullifier};
use lib::utils::{assert_positive_u64, safe_mul, assert_gte};

/// Main entry point for the order commitment circuit
pub fn verify_order_commitment(
    // === Private Inputs ===
    price: Field,              // limit price (scaled integer, e.g., 1e6 = 1 USDC)
    amount: Field,             // order size in base token units
    side: Field,               // 0 = buy, 1 = sell
    balance: Field,            // user's deposited balance in vault
    salt: Field,               // random nonce for commitment hiding
    sender_secret: Field,      // secret known only to the user (for nullifier)
    balance_leaf_index: Field,  // position in the balance Merkle tree
    balance_merkle_path: [Field; TREE_DEPTH], // Merkle auth path

    // === Public Inputs ===
    commitment: pub Field,     // Pedersen(price, amount, side, salt)
    balance_root: pub Field,   // current vault Merkle root (verified on-chain)
    nullifier: pub Field,      // H(salt, sender_secret) — prevents double-submit
    token_pair_id: pub Field,  // which market this order targets (for routing)
) {
    // -------------------------------------------------------
    // 1. Verify the commitment is correctly computed
    // -------------------------------------------------------
    let computed_commitment = compute_order_commitment(price, amount, side, salt);
    assert(computed_commitment == commitment, "Commitment mismatch");

    // -------------------------------------------------------
    // 2. Verify the nullifier is correctly computed
    // -------------------------------------------------------
    let computed_nullifier = compute_nullifier(salt, sender_secret);
    assert(computed_nullifier == nullifier, "Nullifier mismatch");

    // -------------------------------------------------------
    // 3. Validate order side (must be 0 or 1)
    // -------------------------------------------------------
    assert((side == 0) | (side == 1), "Side must be 0 (buy) or 1 (sell)");

    // -------------------------------------------------------
    // 4. Validate price and amount are positive and in range
    // -------------------------------------------------------
    assert_positive_u64(price);
    assert_positive_u64(amount);

    // -------------------------------------------------------
    // 5. Verify balance sufficiency
    // -------------------------------------------------------
    if side == 0 {
        // Buy order: need balance >= amount * price (paying quote token)
        let required = safe_mul(amount, price);
        assert_gte(balance, required);
    } else {
        // Sell order: need balance >= amount (selling base token)
        assert_gte(balance, amount);
    }

    // -------------------------------------------------------
    // 6. Verify balance exists in Merkle tree
    // -------------------------------------------------------
    let balance_leaf = std::hash::pedersen_hash([balance_leaf_index, balance]);
    let computed_root = compute_merkle_root(
        balance_leaf,
        balance_leaf_index,
        balance_merkle_path,
    );
    assert(computed_root == balance_root, "Balance Merkle proof invalid");

    // -------------------------------------------------------
    // 7. Constrain token_pair_id to be non-zero (valid market)
    // -------------------------------------------------------
    assert(token_pair_id != 0, "Invalid token pair");
}
