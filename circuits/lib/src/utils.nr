use crate::constants::{AMOUNT_BITS, PRICE_BITS, PRODUCT_BITS};

// Range check: `value` must fit in `N` bits. Implemented via `to_le_bits`,
// which witness-decomposes the field and constrains each bit to {0,1}.
// If the value is out of range the witness cannot be satisfied and proving fails.
//
// We expose a generic helper so callers pick the bound at call site rather
// than copying `to_le_bits` and forgetting the constraint.
pub fn assert_fits_in_bits<let N: u32>(value: Field) {
    let _: [u1; N] = value.to_le_bits();
}

// Assert the value is a strictly positive amount (0 < value < 2^AMOUNT_BITS).
pub fn assert_positive_amount(value: Field) {
    assert(value != 0, "amount must be non-zero");
    assert_fits_in_bits::<AMOUNT_BITS>(value);
}

// Assert the value is a strictly positive price.
pub fn assert_positive_price(value: Field) {
    assert(value != 0, "price must be non-zero");
    assert_fits_in_bits::<PRICE_BITS>(value);
}

// Assert that an unsigned amount fits in AMOUNT_BITS (zero is allowed --
// used for balances which can legitimately be zero after a settlement).
pub fn assert_in_amount_range(value: Field) {
    assert_fits_in_bits::<AMOUNT_BITS>(value);
}

// Safe multiplication. Inputs must already fit in AMOUNT_BITS / PRICE_BITS.
// We additionally bound the product so it cannot wrap the field.
pub fn safe_mul_amount_price(amount: Field, price: Field) -> Field {
    assert_fits_in_bits::<AMOUNT_BITS>(amount);
    assert_fits_in_bits::<PRICE_BITS>(price);
    let product = amount * price;
    assert_fits_in_bits::<PRODUCT_BITS>(product);
    product
}

// Constrain `a >= b` over non-negative field elements bounded by AMOUNT_BITS.
// Proof: if `a` and `b` both fit in K bits, then `a - b` fits in K+1 bits
// iff `a >= b` (otherwise the difference wraps the field and the witness
// cannot be decomposed into K+1 bits with the high bit being a sign bit).
// We use AMOUNT_BITS+1 to leave one bit of slack for the comparison.
pub fn assert_gte_amount(a: Field, b: Field) {
    assert_fits_in_bits::<AMOUNT_BITS>(a);
    assert_fits_in_bits::<AMOUNT_BITS>(b);
    assert_fits_in_bits::<AMOUNT_BITS>(a - b);
}

// Same as assert_gte_amount but tolerates the larger product range
// (used when comparing balances to amount*price).
pub fn assert_gte_balance_product(balance: Field, required: Field) {
    assert_fits_in_bits::<PRODUCT_BITS>(balance);
    assert_fits_in_bits::<PRODUCT_BITS>(required);
    assert_fits_in_bits::<PRODUCT_BITS>(balance - required);
}

// Constrain `value` to be exactly 0 or 1. Returns the value as a Field.
// Implemented via `value * (value - 1) == 0`, which is satisfied iff value in {0,1}.
pub fn assert_boolean(value: Field) {
    assert(value * (value - 1) == 0, "value must be 0 or 1");
}

// Conditional select: returns `if_true` when `selector == 1`, `if_false` when `selector == 0`.
// Selector must be boolean (caller's responsibility -- use `assert_boolean` if untrusted).
pub fn cond_select(selector: Field, if_true: Field, if_false: Field) -> Field {
    // selector * if_true + (1 - selector) * if_false
    if_false + selector * (if_true - if_false)
}

#[test]
fn test_assert_fits_in_bits_ok() {
    assert_fits_in_bits::<8>(0);
    assert_fits_in_bits::<8>(255);
    assert_fits_in_bits::<60>(0xFFFFFFFFFFFFFFF);
}

#[test(should_fail)]
fn test_assert_fits_in_bits_overflow() {
    assert_fits_in_bits::<8>(256);
}

#[test]
fn test_assert_positive_amount_ok() {
    assert_positive_amount(1);
    assert_positive_amount(1_000_000);
}

#[test(should_fail_with = "amount must be non-zero")]
fn test_assert_positive_amount_zero_rejected() {
    assert_positive_amount(0);
}

#[test]
fn test_safe_mul_ok() {
    let p = safe_mul_amount_price(1_000_000, 250_000);
    assert(p == 250_000_000_000);
}

#[test]
fn test_assert_gte_amount_ok() {
    assert_gte_amount(100, 50);
    assert_gte_amount(100, 100);
}

#[test(should_fail)]
fn test_assert_gte_amount_underflow_rejected() {
    assert_gte_amount(50, 100);
}

#[test]
fn test_assert_boolean_ok() {
    assert_boolean(0);
    assert_boolean(1);
}

#[test(should_fail_with = "value must be 0 or 1")]
fn test_assert_boolean_rejects_two() {
    assert_boolean(2);
}

#[test]
fn test_cond_select() {
    assert(cond_select(1, 42, 99) == 42);
    assert(cond_select(0, 42, 99) == 99);
}
