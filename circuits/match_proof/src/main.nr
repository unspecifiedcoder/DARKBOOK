// DarkBook -- Circuit 2 of 3: Match Proof
//
// The matcher proves to the on-chain engine that two committed orders
// genuinely cross at the proposed settlement price and fill amount. The
// engine learns only:
//   * `commitment_a`, `commitment_b` -- the two opaque orders
//   * `settlement_price`             -- the agreed-upon execution price
//   * `fill_receipt`                 -- H(match_id, fill_amount, settlement_price)
//   * `market_id`, `chain_id`        -- the routing context
//
// What is hidden: each order's price, amount, side, salt, owner, and the
// fill amount itself (only the receipt is public; the receipt is opened
// later inside balance_update where the amount is bound to specific leaves).
//
// Soundness guarantees:
//   * Both commitments are reconstructed from the exact same binding the
//     trader signed -- the matcher cannot swap a commitment to a different
//     order or chain.
//   * Orders are on opposite sides. We use a boolean trick rather than
//     `||`, which is cheaper and harder to get wrong.
//   * Prices cross strictly (the inequalities are non-strict: a marketable
//     order at exactly the limit is a valid match).
//   * Fill amount is positive and at most min(amount_a, amount_b).
//   * Settlement price lies between the two limit prices, inclusive. This
//     leaves the matcher free to choose midpoint, BBO, or any oracle-fed
//     fair value -- the constraint is fairness, not a specific rule.
//   * Self-trade prevention: owner_id_a != owner_id_b. Without this, a
//     trader can pre-cross their own quotes for free wash-trading.
//   * match_id binds to fill_receipt. Resubmitting the same proof with a
//     different match nonce changes the receipt and thus cannot reuse the
//     associated balance_update proof (which also binds the receipt).

use darkbook_lib::hash::{
    order_commitment as hash_order_commitment,
    fill_receipt as hash_fill_receipt,
    match_id as hash_match_id,
};
use darkbook_lib::order::assert_valid_side;
use darkbook_lib::utils::{
    assert_positive_amount,
    assert_positive_price,
    assert_gte_amount,
};

fn main(
    // ----- Private inputs: order A -----
    owner_id_a: Field,
    price_a: Field,
    amount_a: Field,
    side_a: Field,
    expiry_block_a: Field,
    salt_a: Field,

    // ----- Private inputs: order B -----
    owner_id_b: Field,
    price_b: Field,
    amount_b: Field,
    side_b: Field,
    expiry_block_b: Field,
    salt_b: Field,

    // ----- Private inputs: match parameters -----
    fill_amount: Field,
    match_nonce: Field,

    // ----- Public inputs -----
    commitment_a: pub Field,
    commitment_b: pub Field,
    fill_receipt: pub Field,
    settlement_price: pub Field,
    market_id: pub Field,
    chain_id: pub Field,
) {
    // 1. Routing context is non-zero (mirrors order_commitment's check).
    assert(market_id != 0, "market_id must be non-zero");
    assert(chain_id != 0, "chain_id must be non-zero");

    // 2. Validate sides and enforce opposite directions via a boolean
    //    identity. side_a + side_b == 1 iff exactly one of them is 1.
    assert_valid_side(side_a);
    assert_valid_side(side_b);
    assert(side_a + side_b == 1, "orders must be on opposite sides");

    // 3. Prices and amounts are well-formed.
    assert_positive_price(price_a);
    assert_positive_price(price_b);
    assert_positive_price(settlement_price);
    assert_positive_amount(amount_a);
    assert_positive_amount(amount_b);
    assert_positive_amount(fill_amount);

    // 4. Reconstruct both commitments under the *same public* (chain_id,
    //    market_id). This is the constraint that forces both orders to
    //    live in the same market -- if either was committed to a different
    //    market_id, this assertion fails.
    let computed_a = hash_order_commitment(
        chain_id, market_id, owner_id_a, price_a, amount_a, side_a, expiry_block_a, salt_a,
    );
    assert(computed_a == commitment_a, "commitment A mismatch");

    let computed_b = hash_order_commitment(
        chain_id, market_id, owner_id_b, price_b, amount_b, side_b, expiry_block_b, salt_b,
    );
    assert(computed_b == commitment_b, "commitment B mismatch");

    // 5. Self-trade prevention. A trader pre-crossing their own quotes is
    //    a wash trade and breaks the privacy story (the same owner appears
    //    on both sides of a fill).
    assert(owner_id_a != owner_id_b, "self-trade not allowed");

    // 6. Fill amount cannot exceed either order's remaining size.
    assert_gte_amount(amount_a, fill_amount);
    assert_gte_amount(amount_b, fill_amount);

    // 7. Settlement price lies within the crossing band. We let the
    //    matcher choose any point in [min_limit, max_limit], not just the
    //    midpoint -- this is friendlier for matching against external
    //    oracle prices while still being provably fair to both sides.
    //
    //    Let `buy_price` and `sell_price` be the buyer's and seller's
    //    limits respectively. Cross condition: buy_price >= sell_price.
    //    Settlement: sell_price <= settlement_price <= buy_price.
    //
    //    We avoid an `if` on a witness by computing both possible buy/sell
    //    prices using boolean selectors (1 - side, side) on each order.
    let buy_price = price_a * (1 - side_a) + price_b * (1 - side_b);
    let sell_price = price_a * side_a + price_b * side_b;
    assert_gte_amount(buy_price, settlement_price);
    assert_gte_amount(settlement_price, sell_price);

    // 8. Compute match_id and fill_receipt; bind to public receipt.
    let mid = hash_match_id(commitment_a, commitment_b, fill_amount, settlement_price, match_nonce);
    let receipt = hash_fill_receipt(mid, fill_amount, settlement_price);
    assert(receipt == fill_receipt, "fill_receipt mismatch");
}

// ---------- Fixture printer ----------
// Prints the canonical match_proof public-input vector used by
// `circuits/scripts/gen-fixtures.sh` to populate Prover.toml. Mirrors
// `print_fixture_values` in order_commitment.
#[test]
fn print_fixture_values() {
    let chain_id: Field = 31337;
    let market_id: Field = 1;

    let owner_id_a: Field = 100;
    let price_a: Field = 110;
    let amount_a: Field = 50;
    let side_a: Field = 0; // buy
    let expiry_block_a: Field = 100_000;
    let salt_a: Field = 1;

    let owner_id_b: Field = 200;
    let price_b: Field = 90;
    let amount_b: Field = 40;
    let side_b: Field = 1; // sell
    let expiry_block_b: Field = 100_000;
    let salt_b: Field = 2;

    let fill_amount: Field = 30;
    let settlement_price: Field = 100;
    let match_nonce: Field = 999;

    let commitment_a = hash_order_commitment(
        chain_id, market_id, owner_id_a, price_a, amount_a, side_a, expiry_block_a, salt_a,
    );
    let commitment_b = hash_order_commitment(
        chain_id, market_id, owner_id_b, price_b, amount_b, side_b, expiry_block_b, salt_b,
    );
    let mid = hash_match_id(commitment_a, commitment_b, fill_amount, settlement_price, match_nonce);
    let receipt = hash_fill_receipt(mid, fill_amount, settlement_price);

    println(f"FIXTURE:commitment_a={commitment_a}");
    println(f"FIXTURE:commitment_b={commitment_b}");
    println(f"FIXTURE:fill_receipt={receipt}");
    println(f"FIXTURE:settlement_price={settlement_price}");
    println(f"FIXTURE:market_id={market_id}");
    println(f"FIXTURE:chain_id={chain_id}");
}

// ---------- Tests ----------

// Helper to build a valid pair of orders + the matching public inputs.
fn make_witness(
    chain_id: Field,
    market_id: Field,
    owner_a: Field,
    price_a: Field,
    amount_a: Field,
    side_a: Field,
    owner_b: Field,
    price_b: Field,
    amount_b: Field,
    side_b: Field,
    fill_amount: Field,
    settlement_price: Field,
    match_nonce: Field,
) -> (Field, Field, Field) {
    let commitment_a = hash_order_commitment(
        chain_id, market_id, owner_a, price_a, amount_a, side_a, 1000, 1,
    );
    let commitment_b = hash_order_commitment(
        chain_id, market_id, owner_b, price_b, amount_b, side_b, 1000, 2,
    );
    let mid = hash_match_id(commitment_a, commitment_b, fill_amount, settlement_price, match_nonce);
    let receipt = hash_fill_receipt(mid, fill_amount, settlement_price);
    (commitment_a, commitment_b, receipt)
}

#[test]
fn test_valid_match_midpoint() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 110, 50, 0,   // owner 100, buy 50 @ 110
        200, 90, 40, 1,    // owner 200, sell 40 @ 90
        30, 100, 999,      // fill 30 @ 100, nonce 999
    );

    main(
        100, 110, 50, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 100, market_id, chain_id,
    );
}

#[test]
fn test_valid_match_at_buyer_limit() {
    // Settlement at exactly the buyer's limit price is allowed.
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 110, 50, 0,
        200, 90, 40, 1,
        30, 110, 999,
    );
    main(
        100, 110, 50, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 110, market_id, chain_id,
    );
}

#[test]
fn test_valid_match_at_seller_limit() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 110, 50, 0,
        200, 90, 40, 1,
        30, 90, 999,
    );
    main(
        100, 110, 50, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 90, market_id, chain_id,
    );
}

#[test(should_fail_with = "orders must be on opposite sides")]
fn test_rejects_same_side() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 110, 50, 0,
        200, 90, 40, 0,   // both buys
        30, 100, 999,
    );
    main(
        100, 110, 50, 0, 1000, 1,
        200, 90, 40, 0, 1000, 2,
        30, 999,
        ca, cb, receipt, 100, market_id, chain_id,
    );
}

#[test(should_fail_with = "self-trade not allowed")]
fn test_rejects_self_trade() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 110, 50, 0,
        100, 90, 40, 1,   // same owner on both sides
        30, 100, 999,
    );
    main(
        100, 110, 50, 0, 1000, 1,
        100, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 100, market_id, chain_id,
    );
}

#[test(should_fail)]
fn test_rejects_non_crossing_prices() {
    // Buyer at 80, seller at 90 -- prices don't cross.
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 80, 50, 0,
        200, 90, 40, 1,
        30, 85, 999,
    );
    main(
        100, 80, 50, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 85, market_id, chain_id,
    );
}

#[test(should_fail)]
fn test_rejects_settlement_above_buyer_limit() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 110, 50, 0,
        200, 90, 40, 1,
        30, 111, 999,   // settlement above buyer's limit
    );
    main(
        100, 110, 50, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 111, market_id, chain_id,
    );
}

#[test(should_fail)]
fn test_rejects_fill_exceeds_amount_a() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, receipt) = make_witness(
        chain_id, market_id,
        100, 110, 20, 0,   // buyer wants only 20
        200, 90, 40, 1,
        30, 100, 999,      // fill 30 > 20
    );
    main(
        100, 110, 20, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 100, market_id, chain_id,
    );
}

#[test(should_fail_with = "fill_receipt mismatch")]
fn test_rejects_tampered_receipt() {
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let (ca, cb, _receipt) = make_witness(
        chain_id, market_id,
        100, 110, 50, 0,
        200, 90, 40, 1,
        30, 100, 999,
    );
    let bad_receipt: Field = 0xBAD;
    main(
        100, 110, 50, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, bad_receipt, 100, market_id, chain_id,
    );
}

#[test(should_fail_with = "commitment A mismatch")]
fn test_rejects_wrong_market_binding() {
    // Order A was originally committed under market_id=1; matcher tries
    // to settle it under market_id=2 by changing the public input. The
    // recomputed commitment will not match.
    let chain_id: Field = 10143;
    let original_market_id: Field = 1;
    let other_market_id: Field = 2;
    let (ca, cb, receipt) = make_witness(
        chain_id, original_market_id,
        100, 110, 50, 0,
        200, 90, 40, 1,
        30, 100, 999,
    );
    main(
        100, 110, 50, 0, 1000, 1,
        200, 90, 40, 1, 1000, 2,
        30, 999,
        ca, cb, receipt, 100, other_market_id, chain_id,
    );
}
