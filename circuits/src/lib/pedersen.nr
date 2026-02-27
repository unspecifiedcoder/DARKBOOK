// Pedersen commitment scheme wrappers for DarkBook
// Domain-separated commitments to prevent cross-circuit malleability

use dep::std;

// Domain separation tags (constants mixed into hash to prevent cross-context collisions)
global ORDER_COMMITMENT_DST: Field = 1;
global NULLIFIER_DST: Field = 2;
global BALANCE_LEAF_DST: Field = 3;

/// Compute an order commitment: H(DST, price, amount, side, salt)
/// This binds the order parameters with domain separation.
pub fn compute_order_commitment(
    price: Field,
    amount: Field,
    side: Field,
    salt: Field,
) -> Field {
    std::hash::pedersen_hash([ORDER_COMMITMENT_DST, price, amount, side, salt])
}

/// Compute a nullifier: H(DST, salt, sender_secret)
/// Prevents double-submission of the same order.
pub fn compute_nullifier(
    salt: Field,
    sender_secret: Field,
) -> Field {
    std::hash::pedersen_hash([NULLIFIER_DST, salt, sender_secret])
}

/// Compute a fill amount hash for match proofs
pub fn compute_fill_hash(
    fill_amount: Field,
    settlement_price: Field,
) -> Field {
    std::hash::pedersen_hash([fill_amount, settlement_price])
}
