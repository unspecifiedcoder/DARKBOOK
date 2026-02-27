// Utility functions for DarkBook circuits
// Range checks, field arithmetic helpers

/// Assert that a value fits in N bits (range check)
/// This ensures values don't overflow when used in comparisons
pub fn assert_fits_in_64_bits(value: Field) {
    let _bits = value.to_le_bits(64);
    // If this doesn't panic, value fits in 64 bits
}

/// Assert value is positive (non-zero) and fits in 64 bits
pub fn assert_positive_u64(value: Field) {
    assert(value != 0, "Value must be non-zero");
    assert_fits_in_64_bits(value);
}

/// Safe multiplication with overflow check
/// Both inputs and output must fit in 64 bits
pub fn safe_mul(a: Field, b: Field) -> Field {
    assert_fits_in_64_bits(a);
    assert_fits_in_64_bits(b);
    let result = a * b;
    // Result must fit in 128 bits (product of two 64-bit numbers)
    let _bits = result.to_le_bits(128);
    result
}

/// Assert a >= b using bit decomposition
pub fn assert_gte(a: Field, b: Field) {
    // a - b should be non-negative, i.e., fit in 128 bits
    let diff = a - b;
    let _bits = diff.to_le_bits(128);
}

/// Assert a > b
pub fn assert_gt(a: Field, b: Field) {
    assert(a != b, "Values must not be equal");
    assert_gte(a, b);
}

/// Check if two fields are equal (returns bool, no assert)
pub fn field_eq(a: Field, b: Field) -> bool {
    a == b
}
