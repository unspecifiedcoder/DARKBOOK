use crate::constants::{
    DST_ORDER_COMMITMENT,
    DST_NULLIFIER,
    DST_FILL_RECEIPT,
    DST_MATCH_ID,
    DST_BALANCE_LEAF,
    DST_OWNER_ID,
    DST_INTERNAL_NODE,
};

// The only hash we use is `pedersen_hash`. It is the same primitive used by
// the Solidity-side verifier, and Noir's `to_le_bits`/range-checks make it
// safe to feed bounded field elements. Each typed helper prepends a unique
// domain separation tag so commitments in one context can never collide
// with commitments in another (e.g., order != nullifier != fill receipt).

pub fn order_commitment(
    chain_id: Field,
    market_id: Field,
    owner_id: Field,
    price: Field,
    amount: Field,
    side: Field,
    expiry_block: Field,
    salt: Field,
) -> Field {
    std::hash::pedersen_hash([
        DST_ORDER_COMMITMENT,
        chain_id,
        market_id,
        owner_id,
        price,
        amount,
        side,
        expiry_block,
        salt,
    ])
}

pub fn nullifier(
    chain_id: Field,
    market_id: Field,
    sender_secret: Field,
    salt: Field,
) -> Field {
    std::hash::pedersen_hash([
        DST_NULLIFIER,
        chain_id,
        market_id,
        sender_secret,
        salt,
    ])
}

// Match-id binds a specific match instance. By including both commitments,
// the fill amount, the settlement price, and an externally-provided match
// nonce (typically the chain block number at which the match was constructed),
// no two distinct matches can ever produce the same match_id, preventing the
// "submit the same match proof twice" double-settlement attack at the circuit
// level.
pub fn match_id(
    commitment_a: Field,
    commitment_b: Field,
    fill_amount: Field,
    settlement_price: Field,
    match_nonce: Field,
) -> Field {
    std::hash::pedersen_hash([
        DST_MATCH_ID,
        commitment_a,
        commitment_b,
        fill_amount,
        settlement_price,
        match_nonce,
    ])
}

// Public fill receipt -- committed to in the match proof and re-derived by
// the contract from public inputs. Includes the match_id so each settlement
// is uniquely identifiable on-chain.
pub fn fill_receipt(
    match_id_val: Field,
    fill_amount: Field,
    settlement_price: Field,
) -> Field {
    std::hash::pedersen_hash([
        DST_FILL_RECEIPT,
        match_id_val,
        fill_amount,
        settlement_price,
    ])
}

// Balance leaf: bound to (owner_id, token_id, balance, nonce).
// Including a nonce lets the vault rotate a leaf when balance changes
// without revealing whether the new balance is higher or lower (every
// update produces a fresh leaf hash even if the balance is the same).
pub fn balance_leaf(
    owner_id: Field,
    token_id: Field,
    balance: Field,
    leaf_nonce: Field,
) -> Field {
    std::hash::pedersen_hash([
        DST_BALANCE_LEAF,
        owner_id,
        token_id,
        balance,
        leaf_nonce,
    ])
}

// Owner identity commitment: derived from the user's secret. The contract
// stores owner_id only; the secret is never revealed. To prove ownership of
// a balance leaf the user proves knowledge of the preimage.
pub fn owner_id(sender_secret: Field) -> Field {
    std::hash::pedersen_hash([DST_OWNER_ID, sender_secret])
}

// Internal Merkle node hash -- kept distinct from leaves via DST so an
// attacker cannot present a leaf value as an internal node or vice versa.
pub fn internal_node(left: Field, right: Field) -> Field {
    std::hash::pedersen_hash([DST_INTERNAL_NODE, left, right])
}

#[test]
fn test_order_commitment_deterministic() {
    let a = order_commitment(10143, 1, 7, 100, 50, 0, 1000, 42);
    let b = order_commitment(10143, 1, 7, 100, 50, 0, 1000, 42);
    assert(a == b);
}

#[test]
fn test_order_commitment_distinct_for_distinct_inputs() {
    let a = order_commitment(10143, 1, 7, 100, 50, 0, 1000, 42);
    let b = order_commitment(10143, 1, 7, 100, 50, 0, 1000, 43); // different salt
    assert(a != b);
}

#[test]
fn test_dst_separation_order_vs_nullifier() {
    // Same arguments under different DSTs must produce different outputs.
    let oc = order_commitment(0, 0, 0, 0, 0, 0, 0, 0);
    let nl = nullifier(0, 0, 0, 0);
    assert(oc != nl);
}

#[test]
fn test_dst_separation_balance_vs_internal() {
    let bl = balance_leaf(1, 2, 3, 4);
    let nd = internal_node(1, 2);
    assert(bl != nd);
}

#[test]
fn test_owner_id_deterministic() {
    let a = owner_id(0xdeadbeef);
    let b = owner_id(0xdeadbeef);
    assert(a == b);
}

#[test]
fn test_owner_id_distinct() {
    let a = owner_id(1);
    let b = owner_id(2);
    assert(a != b);
}

#[test]
fn test_match_id_binds_all_inputs() {
    let base = match_id(11, 22, 5, 100, 999);
    assert(match_id(11, 22, 5, 100, 999) == base);
    assert(match_id(11, 22, 5, 100, 1000) != base);   // different nonce
    assert(match_id(11, 22, 5, 101, 999) != base);    // different price
    assert(match_id(11, 22, 6, 100, 999) != base);    // different fill
    assert(match_id(11, 23, 5, 100, 999) != base);    // different commitment
}
