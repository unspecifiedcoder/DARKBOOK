use crate::hash::owner_id as owner_id_hash;

// `OwnerId` is what the vault and engine see; the underlying `sender_secret`
// stays private inside the proof. Two helpers:
//   - `derive_owner_id(secret)`: deterministic mapping
//   - `assert_owner_id(secret, claimed)`: convenience guard for circuits
pub fn derive_owner_id(sender_secret: Field) -> Field {
    owner_id_hash(sender_secret)
}

pub fn assert_owner_id(sender_secret: Field, claimed: Field) {
    assert(derive_owner_id(sender_secret) == claimed, "owner id mismatch");
}

#[test]
fn test_derive_deterministic() {
    assert(derive_owner_id(42) == derive_owner_id(42));
    assert(derive_owner_id(42) != derive_owner_id(43));
}

#[test]
fn test_assert_owner_id_ok() {
    let secret = 0xC0FFEE;
    let id = derive_owner_id(secret);
    assert_owner_id(secret, id);
}

#[test(should_fail_with = "owner id mismatch")]
fn test_assert_owner_id_rejects_wrong_claim() {
    assert_owner_id(42, 0xDEADBEEF);
}
