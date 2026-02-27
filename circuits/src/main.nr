// DarkBook ZK Circuits — Main Entry Point
//
// This module re-exports the three core circuits:
//   1. order_commitment — proves order validity and balance sufficiency
//   2. match_proof      — proves two orders form a valid match
//   3. balance_update   — proves post-settlement balances are correct

mod lib;
mod order_commitment;
mod match_proof;
mod balance_update;

// The main function serves as the default circuit entry point.
// In practice, each circuit is compiled separately via Nargo workspace
// or selector-based dispatch.
//
// For the order_commitment circuit (primary use case):
use lib::merkle::TREE_DEPTH;
use lib::pedersen::{compute_order_commitment, compute_nullifier};
use lib::merkle::compute_merkle_root;
use lib::utils::{assert_positive_u64, safe_mul, assert_gte};

fn main(
    // Private inputs
    price: Field,
    amount: Field,
    side: Field,
    balance: Field,
    salt: Field,
    sender_secret: Field,
    balance_leaf_index: Field,
    balance_merkle_path: [Field; TREE_DEPTH],

    // Public inputs
    commitment: pub Field,
    balance_root: pub Field,
    nullifier: pub Field,
    token_pair_id: pub Field,
) {
    // 1. Verify commitment
    let computed_commitment = compute_order_commitment(price, amount, side, salt);
    assert(computed_commitment == commitment, "Commitment mismatch");

    // 2. Verify nullifier
    let computed_nullifier = compute_nullifier(salt, sender_secret);
    assert(computed_nullifier == nullifier, "Nullifier mismatch");

    // 3. Side validation
    assert((side == 0) | (side == 1), "Side must be 0 (buy) or 1 (sell)");

    // 4. Price and amount range checks
    assert_positive_u64(price);
    assert_positive_u64(amount);

    // 5. Balance sufficiency
    if side == 0 {
        let required = safe_mul(amount, price);
        assert_gte(balance, required);
    } else {
        assert_gte(balance, amount);
    }

    // 6. Merkle proof verification
    let balance_leaf = std::hash::pedersen_hash([balance_leaf_index, balance]);
    let computed_root = compute_merkle_root(balance_leaf, balance_leaf_index, balance_merkle_path);
    assert(computed_root == balance_root, "Balance Merkle proof invalid");

    // 7. Valid token pair
    assert(token_pair_id != 0, "Invalid token pair");
}
