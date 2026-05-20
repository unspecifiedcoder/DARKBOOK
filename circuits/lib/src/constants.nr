// Tree depth: supports 2^20 ~= 1M balance leaves.
pub global TREE_DEPTH: u32 = 20;

// Amount/price ceiling (60 bits) -- leaves 4 spare bits so that
// `amount * price` provably fits in 120 bits and never wraps the field.
pub global AMOUNT_BITS: u32 = 60;
pub global PRICE_BITS: u32 = 60;
pub global PRODUCT_BITS: u32 = 120;

// Order sides.
pub global SIDE_BUY: Field = 0;
pub global SIDE_SELL: Field = 1;

// Domain separation tags. Each `Pedersen(...)` invocation in the protocol
// uses a unique DST so commitments from one context cannot be reinterpreted
// in another. The values are arbitrary but must never be reused or removed.
pub global DST_ORDER_COMMITMENT: Field = 0x444152_4b424f4f4b_4f5244_0001; // "DARKBOOK_ORD_0001"
pub global DST_NULLIFIER: Field        = 0x444152_4b424f4f4b_4e554c_0002;
pub global DST_FILL_RECEIPT: Field     = 0x444152_4b424f4f4b_46494c_0003;
pub global DST_MATCH_ID: Field         = 0x444152_4b424f4f4b_4d4348_0004;
pub global DST_BALANCE_LEAF: Field     = 0x444152_4b424f4f4b_42414c_0005;
pub global DST_OWNER_ID: Field         = 0x444152_4b424f4f4b_4f574e_0006;
pub global DST_INTERNAL_NODE: Field    = 0x444152_4b424f4f4b_4e4f44_0007;
