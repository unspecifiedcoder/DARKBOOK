use crate::constants::{SIDE_BUY, SIDE_SELL};
use crate::utils::{assert_boolean, cond_select};

// Order side as a Field. We constrain to {0,1} at the boundary; downstream
// helpers can multiply by `side` or `1 - side` without re-checking.
pub fn assert_valid_side(side: Field) {
    assert_boolean(side);
}

pub fn is_buy(side: Field) -> Field {
    // Returns 1 if side == SIDE_BUY (0), else 0. Caller must have already
    // called assert_valid_side, so side in {0,1}. Then `1 - side` is the
    // buy-indicator.
    1 - side
}

pub fn is_sell(side: Field) -> Field {
    side
}

// Required collateral for an order, in *quote* token units for buys and
// *base* token units for sells. The vault stores balances per token, so
// `token_id` is selected by side: buys lock quote, sells lock base.
pub fn collateral_amount(side: Field, amount: Field, price: Field) -> Field {
    // Buy: collateral = amount * price. Sell: collateral = amount.
    // We compute both unconditionally and select to avoid divergent
    // constraint counts between branches.
    let buy_collateral = amount * price;
    let sell_collateral = amount;
    cond_select(is_buy(side), buy_collateral, sell_collateral)
}

pub fn collateral_token(side: Field, base_token: Field, quote_token: Field) -> Field {
    cond_select(is_buy(side), quote_token, base_token)
}

// Helper used by match_proof and balance_update: given a side, return the
// pair (delta_base, delta_quote) representing the signed change to a
// trader's balance for the *base* and *quote* tokens.
//
// Buy: base += fill_amount, quote -= fill_amount * settlement_price
// Sell: base -= fill_amount, quote += fill_amount * settlement_price
//
// Returns absolute values plus signs as a separate boolean each, so the
// caller can apply them with explicit underflow checks.
pub fn settlement_deltas(
    side: Field,
    fill_amount: Field,
    settlement_price: Field,
) -> (Field, Field, Field) {
    // (abs_base_delta, abs_quote_delta, base_increases_indicator)
    let trade_value = fill_amount * settlement_price;
    (fill_amount, trade_value, is_buy(side))
}

#[test]
fn test_valid_side_accepts_buy_sell() {
    assert_valid_side(SIDE_BUY);
    assert_valid_side(SIDE_SELL);
}

#[test(should_fail_with = "value must be 0 or 1")]
fn test_valid_side_rejects_two() {
    assert_valid_side(2);
}

#[test]
fn test_collateral_buy() {
    let c = collateral_amount(SIDE_BUY, 5, 100);
    assert(c == 500);
}

#[test]
fn test_collateral_sell() {
    let c = collateral_amount(SIDE_SELL, 5, 100);
    assert(c == 5);
}

#[test]
fn test_settlement_deltas_buy() {
    let (abs_base, abs_quote, base_up) = settlement_deltas(SIDE_BUY, 10, 20);
    assert(abs_base == 10);
    assert(abs_quote == 200);
    assert(base_up == 1);
}

#[test]
fn test_settlement_deltas_sell() {
    let (abs_base, abs_quote, base_up) = settlement_deltas(SIDE_SELL, 10, 20);
    assert(abs_base == 10);
    assert(abs_quote == 200);
    assert(base_up == 0);
}
