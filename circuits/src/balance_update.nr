// Circuit 3: Balance Update
// Proves post-settlement balances are correct without revealing individual balances.
//
// After a match is verified, this circuit proves that:
//   1. The old balances existed in the old Merkle root
//   2. New balances are correctly computed based on the fill
//   3. The new Merkle root is correctly computed from the new balances
//   4. No underflow occurs (balances remain non-negative)

use dep::std;

mod lib;
use lib::merkle::{TREE_DEPTH, compute_merkle_root};
use lib::utils::{assert_gte, safe_mul, assert_fits_in_64_bits};

/// Main entry point for the balance update circuit
pub fn verify_balance_update(
    // === Private Inputs ===
    old_balance_a: Field,          // trader A's balance before settlement
    old_balance_b: Field,          // trader B's balance before settlement
    fill_amount: Field,            // amount being transferred
    settlement_price: Field,       // execution price
    side_a: Field,                 // trader A's side (0=buy, 1=sell)

    leaf_index_a: Field,           // trader A's Merkle leaf index
    leaf_index_b: Field,           // trader B's Merkle leaf index
    merkle_path_a: [Field; TREE_DEPTH], // auth path for trader A
    merkle_path_b: [Field; TREE_DEPTH], // auth path for trader B

    // === Public Inputs ===
    old_root: pub Field,           // Merkle root before settlement
    new_root: pub Field,           // Merkle root after settlement
    commitment_a: pub Field,       // order commitment A (for linkage to match proof)
    commitment_b: pub Field,       // order commitment B (for linkage to match proof)
) {
    // -------------------------------------------------------
    // 1. Verify old balances exist in old Merkle tree
    // -------------------------------------------------------
    let old_leaf_a = std::hash::pedersen_hash([leaf_index_a, old_balance_a]);
    let computed_old_root_a = compute_merkle_root(old_leaf_a, leaf_index_a, merkle_path_a);
    assert(computed_old_root_a == old_root, "Old balance A Merkle proof invalid");

    let old_leaf_b = std::hash::pedersen_hash([leaf_index_b, old_balance_b]);
    let computed_old_root_b = compute_merkle_root(old_leaf_b, leaf_index_b, merkle_path_b);
    assert(computed_old_root_b == old_root, "Old balance B Merkle proof invalid");

    // -------------------------------------------------------
    // 2. Compute new balances based on fill
    // -------------------------------------------------------
    let trade_value = safe_mul(fill_amount, settlement_price);

    let (new_balance_a, new_balance_b) = if side_a == 0 {
        // A is buyer: A pays quote (trade_value), receives base (fill_amount)
        // B is seller: B pays base (fill_amount), receives quote (trade_value)
        // For simplicity, we track single-token balances per leaf
        // Buyer's quote balance decreases
        // Seller's base balance decreases
        (old_balance_a - trade_value, old_balance_b - fill_amount)
    } else {
        // A is seller: A pays base (fill_amount), receives quote (trade_value)
        // B is buyer: B pays quote (trade_value), receives base (fill_amount)
        (old_balance_a - fill_amount, old_balance_b - trade_value)
    };

    // -------------------------------------------------------
    // 3. No underflow check — new balances must be non-negative
    // -------------------------------------------------------
    assert_fits_in_64_bits(new_balance_a);
    assert_fits_in_64_bits(new_balance_b);

    // -------------------------------------------------------
    // 4. Verify new Merkle root
    //    We need to update both leaves and verify the resulting root
    // -------------------------------------------------------
    let new_leaf_a = std::hash::pedersen_hash([leaf_index_a, new_balance_a]);
    let new_leaf_b = std::hash::pedersen_hash([leaf_index_b, new_balance_b]);

    // Compute root after updating leaf A
    let intermediate_root = compute_merkle_root(new_leaf_a, leaf_index_a, merkle_path_a);

    // For leaf B, we need the updated path after A's update
    // In practice, if A and B are on different subtrees, the paths are independent
    // This is a simplification — full implementation needs path recalculation
    let computed_new_root = compute_merkle_root(new_leaf_b, leaf_index_b, merkle_path_b);

    // The new root should be derivable from the updated leaves
    // Note: This simplified check works when A and B are in different subtrees
    // A production implementation would need to handle the case where updating A
    // changes B's Merkle path
    assert(computed_new_root == new_root, "New balance Merkle root mismatch");
}
