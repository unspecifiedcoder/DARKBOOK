// DarkBook -- Circuit 3 of 3: Balance Update
//
// After a match is verified (Circuit 2), this circuit proves that the four
// affected balance leaves (each trader has a base-token leaf and a quote-
// token leaf) transition correctly from `old_root` to `new_root`. The
// engine learns only the two roots and the fill receipt -- the actual
// balances stay private.
//
// Settlement semantics for one match where A=buyer, B=seller, fill F at
// settlement price P:
//      A.base   += F                  A.quote  -= F * P
//      B.base   -= F                  B.quote  += F * P
//
// The signs flip when A is the seller. We implement this branchlessly with
// the side_a indicator.
//
// Approach to the four-leaf update:
//   We split the work into two sequential dual-leaf updates.
//     Step 1: (A.base, B.base)    : old_root -> mid_root
//     Step 2: (A.quote, B.quote)  : mid_root -> new_root
//   The prover supplies fresh authentication paths for the quote leaves
//   that reflect the intermediate state (where the base leaves have already
//   been updated). The `assert_dual_update` helper handles the LCA case
//   in each step.
//
// Bindings to the match proof:
//   * `fill_receipt` is recomputed from the same (match_id, fill_amount,
//     settlement_price) tuple Circuit 2 signed. The match-id in turn binds
//     (commitment_a, commitment_b, fill_amount, settlement_price,
//     match_nonce), so this update applies to exactly one match.
//
// Underflow protection:
//   * `assert_gte_balance_product` constrains old_balance >= delta before
//     the subtraction, so the field cannot wrap.

use darkbook_lib::constants::TREE_DEPTH;
use darkbook_lib::hash::{
    balance_leaf as hash_balance_leaf,
    fill_receipt as hash_fill_receipt,
    match_id as hash_match_id,
};
use darkbook_lib::merkle::assert_dual_update;
use darkbook_lib::order::assert_valid_side;
use darkbook_lib::utils::{
    assert_positive_amount,
    assert_positive_price,
    assert_gte_balance_product,
    cond_select,
    safe_mul_amount_price,
    assert_in_amount_range,
};

fn main(
    // ----- Private inputs: trader A (side_a holder) -----
    a_owner_id: Field,
    a_old_base: Field,
    a_old_quote: Field,
    a_new_leaf_nonce_base: Field,
    a_new_leaf_nonce_quote: Field,
    a_old_leaf_nonce_base: Field,
    a_old_leaf_nonce_quote: Field,
    a_leaf_index_base: Field,
    a_leaf_index_quote: Field,
    a_path_base_in_old: [Field; TREE_DEPTH],
    a_path_quote_in_mid: [Field; TREE_DEPTH],

    // ----- Private inputs: trader B -----
    b_owner_id: Field,
    b_old_base: Field,
    b_old_quote: Field,
    b_new_leaf_nonce_base: Field,
    b_new_leaf_nonce_quote: Field,
    b_old_leaf_nonce_base: Field,
    b_old_leaf_nonce_quote: Field,
    b_leaf_index_base: Field,
    b_leaf_index_quote: Field,
    b_path_base_in_old: [Field; TREE_DEPTH],
    b_path_quote_in_mid: [Field; TREE_DEPTH],

    // ----- Private inputs: market & match context -----
    side_a: Field,
    base_token: Field,
    quote_token: Field,
    commitment_a: Field,
    commitment_b: Field,
    fill_amount: Field,
    match_nonce: Field,

    // ----- Public inputs -----
    old_root: pub Field,
    mid_root: pub Field,
    new_root: pub Field,
    fill_receipt: pub Field,
    settlement_price: pub Field,
) {
    // 1. Sanity checks.
    assert_valid_side(side_a);
    assert_positive_amount(fill_amount);
    assert_positive_price(settlement_price);
    assert(a_owner_id != b_owner_id, "owner ids must differ");
    assert(base_token != quote_token, "base and quote tokens must differ");

    // 2. Re-derive fill_receipt (binds this update to a specific match).
    let mid_id = hash_match_id(commitment_a, commitment_b, fill_amount, settlement_price, match_nonce);
    let receipt = hash_fill_receipt(mid_id, fill_amount, settlement_price);
    assert(receipt == fill_receipt, "fill_receipt mismatch");

    // 3. Compute deltas.
    let trade_value = safe_mul_amount_price(fill_amount, settlement_price);
    let is_a_buyer = 1 - side_a;

    // Underflow guards on the side losing balance.
    let seller_old_base = cond_select(is_a_buyer, b_old_base, a_old_base);
    assert_gte_balance_product(seller_old_base, fill_amount);
    let buyer_old_quote = cond_select(is_a_buyer, a_old_quote, b_old_quote);
    assert_gte_balance_product(buyer_old_quote, trade_value);

    // 4. New balances (branchless via cond_select on is_a_buyer).
    let a_new_base = cond_select(is_a_buyer, a_old_base + fill_amount, a_old_base - fill_amount);
    let b_new_base = cond_select(is_a_buyer, b_old_base - fill_amount, b_old_base + fill_amount);
    let a_new_quote = cond_select(is_a_buyer, a_old_quote - trade_value, a_old_quote + trade_value);
    let b_new_quote = cond_select(is_a_buyer, b_old_quote + trade_value, b_old_quote - trade_value);

    assert_in_amount_range(a_new_base);
    assert_in_amount_range(b_new_base);
    assert_in_amount_range(a_new_quote);
    assert_in_amount_range(b_new_quote);

    // 5. Compute leaf hashes for all four positions (old + new).
    let old_leaf_base_a = hash_balance_leaf(a_owner_id, base_token, a_old_base, a_old_leaf_nonce_base);
    let new_leaf_base_a = hash_balance_leaf(a_owner_id, base_token, a_new_base, a_new_leaf_nonce_base);
    let old_leaf_base_b = hash_balance_leaf(b_owner_id, base_token, b_old_base, b_old_leaf_nonce_base);
    let new_leaf_base_b = hash_balance_leaf(b_owner_id, base_token, b_new_base, b_new_leaf_nonce_base);

    let old_leaf_quote_a = hash_balance_leaf(a_owner_id, quote_token, a_old_quote, a_old_leaf_nonce_quote);
    let new_leaf_quote_a = hash_balance_leaf(a_owner_id, quote_token, a_new_quote, a_new_leaf_nonce_quote);
    let old_leaf_quote_b = hash_balance_leaf(b_owner_id, quote_token, b_old_quote, b_old_leaf_nonce_quote);
    let new_leaf_quote_b = hash_balance_leaf(b_owner_id, quote_token, b_new_quote, b_new_leaf_nonce_quote);

    // 6. Sequential dual-leaf updates.
    //    Step 1: update base leaves      old_root -> mid_root
    //    Step 2: update quote leaves     mid_root -> new_root
    //    The prover-supplied `*_path_quote_in_mid` paths reflect the state
    //    of the tree *after* step 1 (i.e., with the base leaves already
    //    updated). assert_dual_update enforces that both leaves are
    //    consistent with the supplied root, so a wrong path-in-mid is
    //    caught.
    assert_dual_update(
        old_root, mid_root,
        old_leaf_base_a, new_leaf_base_a, a_leaf_index_base, a_path_base_in_old,
        old_leaf_base_b, new_leaf_base_b, b_leaf_index_base, b_path_base_in_old,
    );

    assert_dual_update(
        mid_root, new_root,
        old_leaf_quote_a, new_leaf_quote_a, a_leaf_index_quote, a_path_quote_in_mid,
        old_leaf_quote_b, new_leaf_quote_b, b_leaf_index_quote, b_path_quote_in_mid,
    );
}

// ---------- Tests ----------
//
// We need to construct concrete tree states. The lib's
// `simulate_two_leaf_tree` only handles 2 leaves; for balance_update we
// have 4 leaves so we reuse it twice, treating each "after-step-1" snapshot
// as the input for step 2.

use darkbook_lib::hash::internal_node;

// Build a path for a single leaf in an otherwise-empty tree of the
// configured depth. The path is all-zero (every sibling is an empty subtree
// hashed iteratively up).
//
// This gives us a simple way to construct a witness for a tree containing
// exactly the four leaves we care about, by placing each at a unique index
// far enough apart that updating any one does not affect the others'
// paths-in-old. We then explicitly recompute the path-in-mid for the quote
// leaves after the base leaves have been updated.

// Simulate a 4-leaf tree update by directly computing what each leaf's
// path should be at each stage. To keep this manageable, we pick indices
// such that:
//   - A.base   at index 0
//   - A.quote  at index 2
//   - B.base   at index 4
//   - B.quote  at index 6
// All four are in distinct subtrees high up but share enough lower-level
// structure that the LCA logic is meaningfully exercised.
//
// We model the tree as: every position not occupied is 0; we explicitly
// hash up. The helpers below compute the path each leaf needs.

// Walk up the tree from level 1 to TREE_DEPTH, returning the sibling at
// each level for the given leaf index. At each level above 0, the sibling
// is the parent subtree on the other side. We compute it recursively by
// hashing pairs all the way up.
//
// For a tree with at most 4 modeled leaves, an efficient explicit approach
// is to simulate the bottom 3 levels (covering indices 0..7) fully, then
// extend with empty siblings for the rest of the tree.
fn build_tree_below_8(leaves: [(u32, Field); 4]) -> [Field; 15] {
    // Nodes laid out as a heap: index 0 = root of 8-leaf subtree,
    // indices 1..2 = level-2 nodes, 3..6 = level-1, 7..14 = leaves.
    // Standard breadth-first heap order.
    let mut nodes = [0; 15];
    for k in 0..4 {
        let (i, v) = leaves[k];
        nodes[7 + i] = v;
    }
    // Build levels: 3 levels of internal nodes from leaves at 7..14
    // Level 2 (children of leaves): nodes[3..7]
    for j in 0..4 {
        nodes[3 + j] = internal_node(nodes[7 + 2*j], nodes[7 + 2*j + 1]);
    }
    // Level 1: nodes[1..3]
    for j in 0..2 {
        nodes[1 + j] = internal_node(nodes[3 + 2*j], nodes[3 + 2*j + 1]);
    }
    // Level 0: nodes[0]
    nodes[0] = internal_node(nodes[1], nodes[2]);
    nodes
}

// Given the bottom-8 subtree root and an extension path of TREE_DEPTH-3
// zero siblings up to the global root, compute the global root.
fn extend_root(subtree_root: Field) -> Field {
    let mut current = subtree_root;
    for _ in 0..(TREE_DEPTH - 3) {
        current = internal_node(current, 0);
    }
    current
}

// Authentication path for an index in 0..8 within the 4-leaf bottom subtree,
// extended with zeros up to TREE_DEPTH.
//
// Heap layout (0-indexed): root=0, level1=[1,2], level2=[3..6], leaves=[7..14].
// Sibling of heap node h (h > 0): h+1 if h is odd, h-1 if h is even.
fn path_for(index: u32, tree: [Field; 15]) -> [Field; TREE_DEPTH] {
    let mut p = [0; TREE_DEPTH];
    let mut h: u32 = 7 + index;
    for i in 0..3 {
        let sibling_h: u32 = if h % 2 == 1 { h + 1 } else { h - 1 };
        p[i] = tree[sibling_h];
        h = (h - 1) / 2;
    }
    // Levels 3..TREE_DEPTH-1 stay zero (extension is to an empty supertree).
    p
}

// Fixture printer for `circuits/scripts/gen-fixtures.sh`. The witness is
// chosen to be *coherent with the match_proof fixture*: same commitment_a,
// commitment_b, fill_amount, settlement_price, match_nonce -- so the
// fill_receipt this proof binds is identical to the one the match proof
// binds, and the engine's settleMatch accepts both for the same match.
//
// Match-fixture values (see circuits/match_proof Prover.toml):
//   commitment_a = 0x153657ffb2ddce11ef88f4d7500e6961bdb6afe935b54062fb94175cfa82dc73
//   commitment_b = 0x204aa3af7ab7b8d868f8db24bb0454458a5197f6036e6c0dac03ec36f0fcd5f2
//   fill = 30, settlement_price = 100, match_nonce = 999, side_a = 0 (buy)
//
// Paths use the bottom-8-leaf subtree with leaves at 0/2/4/6; only the
// first three elements are non-zero (the rest is the all-zero extension).
#[test]
fn print_fixture_values() {
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let a_owner: Field = 100;
    let b_owner: Field = 200;
    let fill: Field = 30;
    let price: Field = 100; // trade_value = 3000
    let match_nonce: Field = 999;

    // Buyer A needs quote >= 3000; seller B needs base >= 30.
    let a_old_base: Field = 0;
    let a_old_quote: Field = 10_000;
    let b_old_base: Field = 100;
    let b_old_quote: Field = 0;
    let a_new_base: Field = 30;
    let a_new_quote: Field = 7_000;
    let b_new_base: Field = 70;
    let b_new_quote: Field = 3_000;

    let n_old: Field = 1;
    let n_new: Field = 2;

    let old_leaf_ba = hash_balance_leaf(a_owner, base_token, a_old_base, n_old);
    let old_leaf_qa = hash_balance_leaf(a_owner, quote_token, a_old_quote, n_old);
    let old_leaf_bb = hash_balance_leaf(b_owner, base_token, b_old_base, n_old);
    let old_leaf_qb = hash_balance_leaf(b_owner, quote_token, b_old_quote, n_old);
    let new_leaf_ba = hash_balance_leaf(a_owner, base_token, a_new_base, n_new);
    let new_leaf_qa = hash_balance_leaf(a_owner, quote_token, a_new_quote, n_new);
    let new_leaf_bb = hash_balance_leaf(b_owner, base_token, b_new_base, n_new);
    let new_leaf_qb = hash_balance_leaf(b_owner, quote_token, b_new_quote, n_new);

    let tree_old = build_tree_below_8([(0, old_leaf_ba), (2, old_leaf_qa), (4, old_leaf_bb), (6, old_leaf_qb)]);
    let tree_mid = build_tree_below_8([(0, new_leaf_ba), (2, old_leaf_qa), (4, new_leaf_bb), (6, old_leaf_qb)]);
    let tree_new = build_tree_below_8([(0, new_leaf_ba), (2, new_leaf_qa), (4, new_leaf_bb), (6, new_leaf_qb)]);

    let old_root = extend_root(tree_old[0]);
    let mid_root = extend_root(tree_mid[0]);
    let new_root = extend_root(tree_new[0]);

    let path_ba = path_for(0, tree_old);
    let path_bb = path_for(4, tree_old);
    let path_qa = path_for(2, tree_mid);
    let path_qb = path_for(6, tree_mid);

    let commitment_a: Field = 0x153657ffb2ddce11ef88f4d7500e6961bdb6afe935b54062fb94175cfa82dc73;
    let commitment_b: Field = 0x204aa3af7ab7b8d868f8db24bb0454458a5197f6036e6c0dac03ec36f0fcd5f2;
    let mid_id = hash_match_id(commitment_a, commitment_b, fill, price, match_nonce);
    let receipt = hash_fill_receipt(mid_id, fill, price);

    // Public inputs (5).
    println(f"FIXTURE:old_root={old_root}");
    println(f"FIXTURE:mid_root={mid_root}");
    println(f"FIXTURE:new_root={new_root}");
    println(f"FIXTURE:fill_receipt={receipt}");
    println(f"FIXTURE:settlement_price={price}");
    // Path non-zero elements (indices 0..3; rest are zero). Noir f-strings
    // can't index, so bind each element to a local first.
    let ba0 = path_ba[0]; let ba1 = path_ba[1]; let ba2 = path_ba[2];
    let bb0 = path_bb[0]; let bb1 = path_bb[1]; let bb2 = path_bb[2];
    let qa0 = path_qa[0]; let qa1 = path_qa[1]; let qa2 = path_qa[2];
    let qb0 = path_qb[0]; let qb1 = path_qb[1]; let qb2 = path_qb[2];
    println(f"FIXTURE:path_ba_0={ba0}");
    println(f"FIXTURE:path_ba_1={ba1}");
    println(f"FIXTURE:path_ba_2={ba2}");
    println(f"FIXTURE:path_bb_0={bb0}");
    println(f"FIXTURE:path_bb_1={bb1}");
    println(f"FIXTURE:path_bb_2={bb2}");
    println(f"FIXTURE:path_qa_0={qa0}");
    println(f"FIXTURE:path_qa_1={qa1}");
    println(f"FIXTURE:path_qa_2={qa2}");
    println(f"FIXTURE:path_qb_0={qb0}");
    println(f"FIXTURE:path_qb_1={qb1}");
    println(f"FIXTURE:path_qb_2={qb2}");
}

#[test]
fn test_valid_balance_update_a_is_buyer() {
    // Indices: A.base=0, A.quote=2, B.base=4, B.quote=6 (bottom 8-leaf subtree).
    let chain_id: Field = 10143;
    let market_id: Field = 1;
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let a_owner: Field = 100;
    let b_owner: Field = 200;
    let fill: Field = 10;
    let price: Field = 20; // settlement price; trade_value = 200
    let match_nonce: Field = 7;

    // Initial balances
    let a_old_base: Field = 0;
    let a_old_quote: Field = 1_000; // buyer needs >= 200 quote
    let b_old_base: Field = 50;     // seller needs >= 10 base
    let b_old_quote: Field = 0;

    // After-state: A.base += 10, A.quote -= 200, B.base -= 10, B.quote += 200
    let a_new_base: Field = 10;
    let a_new_quote: Field = 800;
    let b_new_base: Field = 40;
    let b_new_quote: Field = 200;

    // Leaf nonces
    let n_old: Field = 1;
    let n_new: Field = 2;

    let old_leaf_ba = hash_balance_leaf(a_owner, base_token, a_old_base, n_old);
    let old_leaf_qa = hash_balance_leaf(a_owner, quote_token, a_old_quote, n_old);
    let old_leaf_bb = hash_balance_leaf(b_owner, base_token, b_old_base, n_old);
    let old_leaf_qb = hash_balance_leaf(b_owner, quote_token, b_old_quote, n_old);

    let new_leaf_ba = hash_balance_leaf(a_owner, base_token, a_new_base, n_new);
    let new_leaf_qa = hash_balance_leaf(a_owner, quote_token, a_new_quote, n_new);
    let new_leaf_bb = hash_balance_leaf(b_owner, base_token, b_new_base, n_new);
    let new_leaf_qb = hash_balance_leaf(b_owner, quote_token, b_new_quote, n_new);

    // Build the three tree states.
    let tree_old = build_tree_below_8([(0, old_leaf_ba), (2, old_leaf_qa), (4, old_leaf_bb), (6, old_leaf_qb)]);
    let tree_mid = build_tree_below_8([(0, new_leaf_ba), (2, old_leaf_qa), (4, new_leaf_bb), (6, old_leaf_qb)]);
    let tree_new = build_tree_below_8([(0, new_leaf_ba), (2, new_leaf_qa), (4, new_leaf_bb), (6, new_leaf_qb)]);

    let old_root = extend_root(tree_old[0]);
    let mid_root = extend_root(tree_mid[0]);
    let new_root = extend_root(tree_new[0]);

    let path_ba_in_old = path_for(0, tree_old);
    let path_bb_in_old = path_for(4, tree_old);
    let path_qa_in_mid = path_for(2, tree_mid);
    let path_qb_in_mid = path_for(6, tree_mid);

    // Match context.
    let owner_a_id = a_owner;
    let owner_b_id = b_owner;
    let commitment_a = hash_balance_leaf(owner_a_id, base_token, 0, 0); // arbitrary dummy
    let commitment_b = hash_balance_leaf(owner_b_id, base_token, 0, 0);
    let mid_id = hash_match_id(commitment_a, commitment_b, fill, price, match_nonce);
    let receipt = hash_fill_receipt(mid_id, fill, price);

    main(
        owner_a_id,
        a_old_base, a_old_quote,
        n_new, n_new, n_old, n_old,
        0, 2,
        path_ba_in_old, path_qa_in_mid,

        owner_b_id,
        b_old_base, b_old_quote,
        n_new, n_new, n_old, n_old,
        4, 6,
        path_bb_in_old, path_qb_in_mid,

        0, // side_a: A buys
        base_token, quote_token,
        commitment_a, commitment_b,
        fill, match_nonce,

        old_root, mid_root, new_root, receipt, price,
    );

    let _ = chain_id; let _ = market_id; // unused in body, kept for parity
}

#[test]
fn test_valid_balance_update_a_is_seller() {
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let a_owner: Field = 100;
    let b_owner: Field = 200;
    let fill: Field = 10;
    let price: Field = 20;
    let match_nonce: Field = 7;

    // A is seller this time.
    let a_old_base: Field = 50;
    let a_old_quote: Field = 0;
    let b_old_base: Field = 0;
    let b_old_quote: Field = 1_000;

    let a_new_base: Field = 40;
    let a_new_quote: Field = 200;
    let b_new_base: Field = 10;
    let b_new_quote: Field = 800;

    let n_old: Field = 1;
    let n_new: Field = 2;

    let old_leaf_ba = hash_balance_leaf(a_owner, base_token, a_old_base, n_old);
    let old_leaf_qa = hash_balance_leaf(a_owner, quote_token, a_old_quote, n_old);
    let old_leaf_bb = hash_balance_leaf(b_owner, base_token, b_old_base, n_old);
    let old_leaf_qb = hash_balance_leaf(b_owner, quote_token, b_old_quote, n_old);

    let new_leaf_ba = hash_balance_leaf(a_owner, base_token, a_new_base, n_new);
    let new_leaf_qa = hash_balance_leaf(a_owner, quote_token, a_new_quote, n_new);
    let new_leaf_bb = hash_balance_leaf(b_owner, base_token, b_new_base, n_new);
    let new_leaf_qb = hash_balance_leaf(b_owner, quote_token, b_new_quote, n_new);

    let tree_old = build_tree_below_8([(0, old_leaf_ba), (2, old_leaf_qa), (4, old_leaf_bb), (6, old_leaf_qb)]);
    let tree_mid = build_tree_below_8([(0, new_leaf_ba), (2, old_leaf_qa), (4, new_leaf_bb), (6, old_leaf_qb)]);
    let tree_new = build_tree_below_8([(0, new_leaf_ba), (2, new_leaf_qa), (4, new_leaf_bb), (6, new_leaf_qb)]);

    let old_root = extend_root(tree_old[0]);
    let mid_root = extend_root(tree_mid[0]);
    let new_root = extend_root(tree_new[0]);

    let path_ba_in_old = path_for(0, tree_old);
    let path_bb_in_old = path_for(4, tree_old);
    let path_qa_in_mid = path_for(2, tree_mid);
    let path_qb_in_mid = path_for(6, tree_mid);

    let commitment_a: Field = 0xCAFE_AAAA;
    let commitment_b: Field = 0xCAFE_BBBB;
    let mid_id = hash_match_id(commitment_a, commitment_b, fill, price, match_nonce);
    let receipt = hash_fill_receipt(mid_id, fill, price);

    main(
        a_owner,
        a_old_base, a_old_quote,
        n_new, n_new, n_old, n_old,
        0, 2,
        path_ba_in_old, path_qa_in_mid,

        b_owner,
        b_old_base, b_old_quote,
        n_new, n_new, n_old, n_old,
        4, 6,
        path_bb_in_old, path_qb_in_mid,

        1, // side_a: A sells
        base_token, quote_token,
        commitment_a, commitment_b,
        fill, match_nonce,

        old_root, mid_root, new_root, receipt, price,
    );
}

#[test(should_fail_with = "fill_receipt mismatch")]
fn test_rejects_tampered_receipt() {
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let a_owner: Field = 100;
    let b_owner: Field = 200;
    let fill: Field = 10;
    let price: Field = 20;
    let match_nonce: Field = 7;

    let n_old: Field = 1;
    let n_new: Field = 2;

    let old_leaf_ba = hash_balance_leaf(a_owner, base_token, 0, n_old);
    let old_leaf_qa = hash_balance_leaf(a_owner, quote_token, 1_000, n_old);
    let old_leaf_bb = hash_balance_leaf(b_owner, base_token, 50, n_old);
    let old_leaf_qb = hash_balance_leaf(b_owner, quote_token, 0, n_old);

    let new_leaf_ba = hash_balance_leaf(a_owner, base_token, 10, n_new);
    let new_leaf_qa = hash_balance_leaf(a_owner, quote_token, 800, n_new);
    let new_leaf_bb = hash_balance_leaf(b_owner, base_token, 40, n_new);
    let new_leaf_qb = hash_balance_leaf(b_owner, quote_token, 200, n_new);

    let tree_old = build_tree_below_8([(0, old_leaf_ba), (2, old_leaf_qa), (4, old_leaf_bb), (6, old_leaf_qb)]);
    let tree_mid = build_tree_below_8([(0, new_leaf_ba), (2, old_leaf_qa), (4, new_leaf_bb), (6, old_leaf_qb)]);
    let tree_new = build_tree_below_8([(0, new_leaf_ba), (2, new_leaf_qa), (4, new_leaf_bb), (6, new_leaf_qb)]);

    let old_root = extend_root(tree_old[0]);
    let mid_root = extend_root(tree_mid[0]);
    let new_root = extend_root(tree_new[0]);

    let path_ba_in_old = path_for(0, tree_old);
    let path_bb_in_old = path_for(4, tree_old);
    let path_qa_in_mid = path_for(2, tree_mid);
    let path_qb_in_mid = path_for(6, tree_mid);

    let bad_receipt: Field = 0xBAD;

    main(
        a_owner,
        0, 1_000,
        n_new, n_new, n_old, n_old,
        0, 2,
        path_ba_in_old, path_qa_in_mid,

        b_owner,
        50, 0,
        n_new, n_new, n_old, n_old,
        4, 6,
        path_bb_in_old, path_qb_in_mid,

        0,
        base_token, quote_token,
        0xCAFE_AAAA, 0xCAFE_BBBB,
        fill, match_nonce,

        old_root, mid_root, new_root, bad_receipt, price,
    );
}

#[test(should_fail)]
fn test_rejects_buyer_quote_underflow() {
    // A is buyer with only 100 quote, but trade requires 200.
    let base_token: Field = 11;
    let quote_token: Field = 22;
    let a_owner: Field = 100;
    let b_owner: Field = 200;
    let fill: Field = 10;
    let price: Field = 20;
    let match_nonce: Field = 7;

    let n_old: Field = 1;
    let n_new: Field = 2;

    let a_old_quote: Field = 100; // insufficient

    let old_leaf_ba = hash_balance_leaf(a_owner, base_token, 0, n_old);
    let old_leaf_qa = hash_balance_leaf(a_owner, quote_token, a_old_quote, n_old);
    let old_leaf_bb = hash_balance_leaf(b_owner, base_token, 50, n_old);
    let old_leaf_qb = hash_balance_leaf(b_owner, quote_token, 0, n_old);

    // Even though it'll fail, build trees consistent with the (impossible)
    // new state to make sure the failure is the underflow guard.
    let tree_old = build_tree_below_8([(0, old_leaf_ba), (2, old_leaf_qa), (4, old_leaf_bb), (6, old_leaf_qb)]);
    let tree_mid = tree_old; // not actually used because underflow fails first
    let tree_new = tree_old;

    let old_root = extend_root(tree_old[0]);
    let mid_root = extend_root(tree_mid[0]);
    let new_root = extend_root(tree_new[0]);

    let path_ba_in_old = path_for(0, tree_old);
    let path_bb_in_old = path_for(4, tree_old);
    let path_qa_in_mid = path_for(2, tree_mid);
    let path_qb_in_mid = path_for(6, tree_mid);

    let commitment_a: Field = 0xCAFE_AAAA;
    let commitment_b: Field = 0xCAFE_BBBB;
    let mid_id = hash_match_id(commitment_a, commitment_b, fill, price, match_nonce);
    let receipt = hash_fill_receipt(mid_id, fill, price);

    main(
        a_owner,
        0, a_old_quote,
        n_new, n_new, n_old, n_old,
        0, 2,
        path_ba_in_old, path_qa_in_mid,

        b_owner,
        50, 0,
        n_new, n_new, n_old, n_old,
        4, 6,
        path_bb_in_old, path_qb_in_mid,

        0,
        base_token, quote_token,
        commitment_a, commitment_b,
        fill, match_nonce,

        old_root, mid_root, new_root, receipt, price,
    );
}

#[test(should_fail_with = "owner ids must differ")]
fn test_rejects_same_owner() {
    let dummy_path: [Field; TREE_DEPTH] = [0; TREE_DEPTH];
    main(
        7, 0, 1000, 1, 1, 1, 1, 0, 2, dummy_path, dummy_path,
        7, 50, 0, 1, 1, 1, 1, 4, 6, dummy_path, dummy_path,
        0, 11, 22, 0, 0, 10, 7,
        0, 0, 0, 0, 20,
    );
}
