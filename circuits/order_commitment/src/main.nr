// DarkBook -- Circuit 1 of 3: Order Commitment
//
// Proves to the on-chain engine that a trader is submitting a well-formed,
// fully-funded order without revealing any of its parameters. The verifier
// learns only:
//   * `commitment`      -- the opaque order handle
//   * `nullifier`       -- a per-order tag that prevents resubmission
//   * `balance_root`    -- the vault Merkle root the proof is bound to
//   * `market_id`       -- the trading pair (public so the engine can route)
//   * `chain_id`        -- prevents cross-chain replay
//   * `expiry_block`    -- after this block, on-chain logic rejects the order
//   * `owner_id`        -- the trader's pseudonymous identity (hash of secret)
//
// What is hidden: price, amount, side, salt, the underlying balance, the
// secret used to derive owner_id, and the trader's position in the tree.
//
// Bindings:
//   * The commitment binds (chain_id, market_id, owner_id, price, amount,
//     side, expiry_block, salt). Re-using a commitment in a different market
//     or chain is impossible by construction.
//   * The nullifier binds (chain_id, market_id, sender_secret, salt). The
//     same salt can be safely reused across markets; replays inside one
//     market are blocked.
//   * The balance leaf binds (owner_id, token_id, balance, leaf_nonce).
//     Anyone proving spend of a leaf must know the secret behind owner_id.
//
// Side-specific liquidity:
//   * Buy  (side = 0): collateral_token = quote_token, required = amount * price.
//   * Sell (side = 1): collateral_token = base_token,  required = amount.

use darkbook_lib::constants::TREE_DEPTH;
use darkbook_lib::hash::{
    order_commitment as hash_order_commitment,
    nullifier as hash_nullifier,
    balance_leaf as hash_balance_leaf,
};
use darkbook_lib::identity::derive_owner_id;
use darkbook_lib::merkle::assert_inclusion;
use darkbook_lib::order::{assert_valid_side, collateral_amount, collateral_token};
use darkbook_lib::utils::{
    assert_positive_amount,
    assert_positive_price,
    assert_gte_balance_product,
    safe_mul_amount_price,
    assert_in_amount_range,
};

fn main(
    // ----- Private inputs (witness only) -----
    price: Field,
    amount: Field,
    side: Field,
    salt: Field,
    sender_secret: Field,
    base_token: Field,
    quote_token: Field,
    balance: Field,
    balance_leaf_nonce: Field,
    balance_leaf_index: Field,
    balance_merkle_path: [Field; TREE_DEPTH],

    // ----- Public inputs (visible on-chain) -----
    commitment: pub Field,
    nullifier: pub Field,
    balance_root: pub Field,
    owner_id: pub Field,
    chain_id: pub Field,
    market_id: pub Field,
    expiry_block: pub Field,
) {
    // 1. Side is strictly 0 or 1. Downstream helpers assume this.
    assert_valid_side(side);

    // 2. Price and amount are non-zero and fit in the configured range.
    assert_positive_price(price);
    assert_positive_amount(amount);

    // 3. Market and chain ids are non-zero. (A market_id of 0 is reserved
    //    for "no market"; submitting one would let the engine route nowhere.)
    assert(market_id != 0, "market_id must be non-zero");
    assert(chain_id != 0, "chain_id must be non-zero");

    // 4. Owner id is the public commitment to the sender's secret.
    assert(derive_owner_id(sender_secret) == owner_id, "owner_id mismatch");

    // 5. Order commitment is correctly formed and binds every public field
    //    plus the hidden order parameters.
    let computed_commitment = hash_order_commitment(
        chain_id, market_id, owner_id, price, amount, side, expiry_block, salt,
    );
    assert(computed_commitment == commitment, "commitment mismatch");

    // 6. Nullifier binds (chain_id, market_id, sender_secret, salt). It is
    //    public so the engine can mark it spent; it does not reveal salt
    //    or secret individually.
    let computed_nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    assert(computed_nullifier == nullifier, "nullifier mismatch");

    // 7. Balance leaf is bound to the prover's owner_id + the token that
    //    will collateralise this order (quote for buys, base for sells).
    //    This prevents leaf-spoofing: even if an attacker observes a leaf's
    //    hash, they cannot use it to back an order without knowing the
    //    underlying secret.
    let coll_token = collateral_token(side, base_token, quote_token);
    let leaf = hash_balance_leaf(owner_id, coll_token, balance, balance_leaf_nonce);
    assert_inclusion(leaf, balance_leaf_index, balance_merkle_path, balance_root);

    // 8. Balance suffices for the order's collateral requirement. Note that
    //    `collateral_amount` returns amount*price for buys (which can be
    //    up to PRODUCT_BITS wide), so we compare in the wider range.
    assert_in_amount_range(balance);
    let required = collateral_amount(side, amount, price);
    // For buys, `required` is a product up to 120 bits; for sells it's an
    // amount up to 60 bits. The wider-range comparator handles both.
    let _ = safe_mul_amount_price(amount, price); // explicit overflow check for buy case
    assert_gte_balance_product(balance, required);
}

// ---------- Tests ----------
//
// Each test constructs a valid witness, runs `main`, and asserts the public
// inputs match. Negative tests use `should_fail_with` to confirm that
// tampering with any input causes the constraint system to reject.

#[test]
fn test_valid_buy_order() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let sender_secret: Field = 0xDEADBEEF;
    let owner_id = derive_owner_id(sender_secret);
    let price: Field = 100;
    let amount: Field = 50;
    let side: Field = 0; // buy
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 10_000; // need 100 * 50 = 5_000
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let commitment = hash_order_commitment(
        chain_id, market_id, owner_id, price, amount, side, expiry_block, salt,
    );
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);

    // Compute the expected balance root by walking up an all-zero tree.
    let leaf = hash_balance_leaf(owner_id, quote_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        commitment, nullifier, balance_root, owner_id, chain_id, market_id, expiry_block,
    );
}

#[test]
fn test_valid_sell_order() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let sender_secret: Field = 0xDEADBEEF;
    let owner_id = derive_owner_id(sender_secret);
    let price: Field = 100;
    let amount: Field = 50;
    let side: Field = 1; // sell
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 50; // need amount = 50
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let commitment = hash_order_commitment(
        chain_id, market_id, owner_id, price, amount, side, expiry_block, salt,
    );
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    let leaf = hash_balance_leaf(owner_id, base_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        commitment, nullifier, balance_root, owner_id, chain_id, market_id, expiry_block,
    );
}

#[test(should_fail_with = "commitment mismatch")]
fn test_rejects_tampered_commitment() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let sender_secret: Field = 0xDEADBEEF;
    let owner_id = derive_owner_id(sender_secret);
    let price: Field = 100;
    let amount: Field = 50;
    let side: Field = 0;
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 10_000;
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let bad_commitment: Field = 0x1234;
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    let leaf = hash_balance_leaf(owner_id, quote_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        bad_commitment, nullifier, balance_root, owner_id, chain_id, market_id, expiry_block,
    );
}

#[test(should_fail)]
fn test_rejects_insufficient_balance_buy() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let sender_secret: Field = 0xDEADBEEF;
    let owner_id = derive_owner_id(sender_secret);
    let price: Field = 100;
    let amount: Field = 50;
    let side: Field = 0;
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 100; // need 5_000; insufficient
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let commitment = hash_order_commitment(
        chain_id, market_id, owner_id, price, amount, side, expiry_block, salt,
    );
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    let leaf = hash_balance_leaf(owner_id, quote_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        commitment, nullifier, balance_root, owner_id, chain_id, market_id, expiry_block,
    );
}

#[test(should_fail_with = "owner_id mismatch")]
fn test_rejects_wrong_owner_id() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let sender_secret: Field = 0xDEADBEEF;
    let true_owner = derive_owner_id(sender_secret);
    let claimed_owner: Field = 0xCAFE; // attacker claims a different owner
    let price: Field = 100;
    let amount: Field = 50;
    let side: Field = 0;
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 10_000;
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let commitment = hash_order_commitment(
        chain_id, market_id, true_owner, price, amount, side, expiry_block, salt,
    );
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    let leaf = hash_balance_leaf(true_owner, quote_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        commitment, nullifier, balance_root, claimed_owner, chain_id, market_id, expiry_block,
    );
}

#[test(should_fail_with = "market_id must be non-zero")]
fn test_rejects_zero_market_id() {
    let chain_id: Field = 10143;
    let market_id: Field = 0;
    let sender_secret: Field = 0xDEADBEEF;
    let owner_id = derive_owner_id(sender_secret);
    let price: Field = 100;
    let amount: Field = 50;
    let side: Field = 0;
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 10_000;
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let commitment = hash_order_commitment(
        chain_id, market_id, owner_id, price, amount, side, expiry_block, salt,
    );
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    let leaf = hash_balance_leaf(owner_id, quote_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        commitment, nullifier, balance_root, owner_id, chain_id, market_id, expiry_block,
    );
}

#[test(should_fail_with = "amount must be non-zero")]
fn test_rejects_zero_amount() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let sender_secret: Field = 0xDEADBEEF;
    let owner_id = derive_owner_id(sender_secret);
    let price: Field = 100;
    let amount: Field = 0;
    let side: Field = 0;
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 10_000;
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let commitment = hash_order_commitment(
        chain_id, market_id, owner_id, price, amount, side, expiry_block, salt,
    );
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    let leaf = hash_balance_leaf(owner_id, quote_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        commitment, nullifier, balance_root, owner_id, chain_id, market_id, expiry_block,
    );
}

#[test(should_fail_with = "value must be 0 or 1")]
fn test_rejects_invalid_side() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let sender_secret: Field = 0xDEADBEEF;
    let owner_id = derive_owner_id(sender_secret);
    let price: Field = 100;
    let amount: Field = 50;
    let side: Field = 2; // invalid
    let salt: Field = 0xABC123;
    let expiry_block: Field = 100_000;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let balance: Field = 10_000;
    let leaf_nonce: Field = 1;
    let leaf_index: Field = 0;
    let path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];

    let commitment = hash_order_commitment(
        chain_id, market_id, owner_id, price, amount, side, expiry_block, salt,
    );
    let nullifier = hash_nullifier(chain_id, market_id, sender_secret, salt);
    let leaf = hash_balance_leaf(owner_id, quote_token, balance, leaf_nonce);
    let balance_root = darkbook_lib::merkle::compute_root(leaf, leaf_index, path);

    main(
        price, amount, side, salt, sender_secret,
        base_token, quote_token, balance, leaf_nonce, leaf_index, path,
        commitment, nullifier, balance_root, owner_id, chain_id, market_id, expiry_block,
    );
}
