// Circuit 2: Match Proof
// Proves two commitments form a valid match without revealing order details.
//
// The matcher/relayer generates this proof after finding two crossing orders.
// It proves:
//   1. Both commitments are correctly reconstructed
//   2. Orders are on opposite sides (one buy, one sell)
//   3. Prices cross (buy price >= settlement price >= sell price)
//   4. Fill amount is valid (positive, within both order sizes)
//   5. Settlement price is the midpoint of the two limit prices

use dep::std;

mod lib;
use lib::pedersen::{compute_order_commitment, compute_fill_hash};
use lib::utils::{assert_positive_u64, assert_gte, assert_gt};

/// Main entry point for the match proof circuit
pub fn verify_match(
    // === Private Inputs (Order A) ===
    price_a: Field,
    amount_a: Field,
    side_a: Field,
    salt_a: Field,

    // === Private Inputs (Order B) ===
    price_b: Field,
    amount_b: Field,
    side_b: Field,
    salt_b: Field,

    // === Private Inputs (Match Parameters) ===
    fill_amount: Field,        // how much is being filled

    // === Public Inputs ===
    commitment_a: pub Field,   // commitment of order A
    commitment_b: pub Field,   // commitment of order B
    fill_amount_hash: pub Field, // H(fill_amount, settlement_price)
    settlement_price: pub Field, // execution price
) {
    // -------------------------------------------------------
    // 1. Recompute and verify both commitments
    // -------------------------------------------------------
    let computed_commitment_a = compute_order_commitment(price_a, amount_a, side_a, salt_a);
    assert(computed_commitment_a == commitment_a, "Commitment A mismatch");

    let computed_commitment_b = compute_order_commitment(price_b, amount_b, side_b, salt_b);
    assert(computed_commitment_b == commitment_b, "Commitment B mismatch");

    // -------------------------------------------------------
    // 2. Orders must be on opposite sides
    // -------------------------------------------------------
    assert((side_a == 0) | (side_a == 1), "Side A must be 0 or 1");
    assert((side_b == 0) | (side_b == 1), "Side B must be 0 or 1");
    assert(side_a != side_b, "Orders must be on opposite sides");

    // -------------------------------------------------------
    // 3. Price crossing check
    //    If A is buy (side_a == 0): price_a >= settlement_price >= price_b
    //    If A is sell (side_a == 1): price_b >= settlement_price >= price_a
    // -------------------------------------------------------
    assert_positive_u64(settlement_price);

    if side_a == 0 {
        // A is buyer, B is seller
        // Buyer's limit >= settlement >= Seller's limit
        assert_gte(price_a, settlement_price);
        assert_gte(settlement_price, price_b);
    } else {
        // A is seller, B is buyer
        // Buyer's limit >= settlement >= Seller's limit
        assert_gte(price_b, settlement_price);
        assert_gte(settlement_price, price_a);
    }

    // -------------------------------------------------------
    // 4. Fill amount validation
    // -------------------------------------------------------
    assert_positive_u64(fill_amount);

    // Fill amount must not exceed either order's size
    assert_gte(amount_a, fill_amount);
    assert_gte(amount_b, fill_amount);

    // -------------------------------------------------------
    // 5. Settlement price is midpoint: (price_a + price_b) / 2
    //    Note: We verify 2 * settlement_price == price_a + price_b
    //    to avoid field division issues
    // -------------------------------------------------------
    let double_settlement = settlement_price + settlement_price;
    let price_sum = price_a + price_b;
    assert(double_settlement == price_sum, "Settlement price must be midpoint");

    // -------------------------------------------------------
    // 6. Verify fill amount hash
    // -------------------------------------------------------
    let computed_fill_hash = compute_fill_hash(fill_amount, settlement_price);
    assert(computed_fill_hash == fill_amount_hash, "Fill hash mismatch");
}
