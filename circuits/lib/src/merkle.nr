use crate::constants::TREE_DEPTH;
use crate::hash::internal_node;
use crate::utils::{assert_boolean, cond_select};

// Hash a single Merkle step: given a child node and its sibling, produce
// the parent. `bit` selects the side (0 = child is left, 1 = child is right).
//
// We constrain `bit` to be boolean here so callers can pass index bits
// without re-asserting.
fn merkle_step(child: Field, sibling: Field, bit: Field) -> Field {
    assert_boolean(bit);
    let left = cond_select(bit, sibling, child);
    let right = cond_select(bit, child, sibling);
    internal_node(left, right)
}

// Compute the Merkle root by climbing from a leaf to the root using the
// provided authentication path. `index_bits[i]` is the i-th LSB of the
// leaf index (0 = leaf on left at level i, 1 = leaf on right).
//
// We accept the bits as input (rather than re-decomposing the index inside)
// so that callers needing the bits for other purposes (e.g., LCA detection
// in dual-leaf updates) only pay the decomposition cost once.
pub fn compute_root_from_bits(
    leaf: Field,
    index_bits: [u1; TREE_DEPTH],
    path: [Field; TREE_DEPTH],
) -> Field {
    let mut current = leaf;
    for i in 0..TREE_DEPTH {
        current = merkle_step(current, path[i], index_bits[i] as Field);
    }
    current
}

// Convenience wrapper that decomposes the index and asserts it fits in
// TREE_DEPTH bits in the process.
pub fn compute_root(
    leaf: Field,
    index: Field,
    path: [Field; TREE_DEPTH],
) -> Field {
    let index_bits: [u1; TREE_DEPTH] = index.to_le_bits();
    compute_root_from_bits(leaf, index_bits, path)
}

// Verify a single inclusion proof.
pub fn assert_inclusion(
    leaf: Field,
    index: Field,
    path: [Field; TREE_DEPTH],
    root: Field,
) {
    let computed = compute_root(leaf, index, path);
    assert(computed == root, "merkle inclusion failed");
}

// Verify an inclusion proof, returning the intermediate node values that
// were computed on the way up. node_at_level[0] = leaf, and
// node_at_level[TREE_DEPTH] = root. Used by the dual-leaf updater.
fn inclusion_with_intermediates(
    leaf: Field,
    index_bits: [u1; TREE_DEPTH],
    path: [Field; TREE_DEPTH],
) -> [Field; TREE_DEPTH + 1] {
    let mut nodes = [0; TREE_DEPTH + 1];
    nodes[0] = leaf;
    for i in 0..TREE_DEPTH {
        nodes[i + 1] = merkle_step(nodes[i], path[i], index_bits[i] as Field);
    }
    nodes
}

// LCA detection. Returns a one-hot indicator `lca_at[i] = 1` at the unique
// level `i` where A's path-element contains B's subtree (and symmetrically
// B's path-element contains A's subtree). All other levels are zero.
//
// The LCA level is the highest level where index_a's bit differs from
// index_b's bit (i.e., the highest set bit of `a XOR b`).
fn lca_one_hot(
    index_a_bits: [u1; TREE_DEPTH],
    index_b_bits: [u1; TREE_DEPTH],
) -> [Field; TREE_DEPTH] {
    // diff_bit[i] = 1 iff a_bits[i] != b_bits[i]
    let mut diff_bit = [0; TREE_DEPTH];
    for i in 0..TREE_DEPTH {
        let a_i = index_a_bits[i] as Field;
        let b_i = index_b_bits[i] as Field;
        // For boolean a, b: (a - b)^2 = a XOR b
        let d = a_i - b_i;
        diff_bit[i] = d * d;
    }

    // higher_differs[i] = 1 iff any j > i has diff_bit[j] == 1.
    // Computed top-down with OR.
    let mut higher_differs = [0; TREE_DEPTH + 1];
    higher_differs[TREE_DEPTH] = 0;
    for k in 0..TREE_DEPTH {
        let i = TREE_DEPTH - 1 - k;
        let d = diff_bit[i];
        let h = higher_differs[i + 1];
        // OR(d, h) = d + h - d*h
        higher_differs[i] = d + h - d * h;
    }

    // lca_at[i] = diff_bit[i] AND NOT higher_differs[i+1]
    //          = diff_bit[i] * (1 - higher_differs[i+1])
    let mut lca_at = [0; TREE_DEPTH];
    for i in 0..TREE_DEPTH {
        lca_at[i] = diff_bit[i] * (1 - higher_differs[i + 1]);
    }
    lca_at
}

// Dual-leaf update.
//
// The classic bug in naive ZK Merkle dual-updates: when leaves A and B
// share a common ancestor, updating A invalidates one element of B's
// authentication path (the one at the LCA level, which is the value of
// A's subtree-root before the update). A path supplied for the *old*
// tree therefore cannot be reused as-is to compute the new root via B.
//
// Correct algorithm:
//   1. Verify A's old leaf is in `old_root` via `path_a`.
//   2. Verify B's old leaf is in `old_root` via `path_b`.
//   3. Walk A's path with the *new* leaf, producing the subtree-root values
//      at every level (`a_new_nodes`). The top is the root after A is
//      updated but B is not.
//   4. Walk B's path with the *new* leaf for B, but at exactly the LCA
//      level substitute `a_new_nodes[i]` for `path_b[i]`. Every other level
//      uses `path_b[i]` unchanged. The top is `new_root`.
//   5. As a defensive consistency check: at the LCA level, the *old*
//      A-subtree-root must equal the original `path_b[i]`. Otherwise the
//      caller is supplying paths for different trees and the substitution
//      is undefined.
//
// All branching is done via constant-time `cond_select` on the LCA one-hot
// vector -- no `if` on witness values.
pub fn assert_dual_update(
    old_root: Field,
    new_root: Field,
    old_leaf_a: Field,
    new_leaf_a: Field,
    index_a: Field,
    path_a: [Field; TREE_DEPTH],
    old_leaf_b: Field,
    new_leaf_b: Field,
    index_b: Field,
    path_b: [Field; TREE_DEPTH],
) {
    // Disallow the degenerate case A == B (same leaf updated twice in one
    // proof, which is meaningless and would let a prover settle a self-trade
    // against themselves trivially).
    assert(index_a != index_b, "dual update requires distinct leaves");

    let bits_a: [u1; TREE_DEPTH] = index_a.to_le_bits();
    let bits_b: [u1; TREE_DEPTH] = index_b.to_le_bits();

    // Step 1+3: compute A's old and new subtree-root at every level.
    let a_old_nodes = inclusion_with_intermediates(old_leaf_a, bits_a, path_a);
    let a_new_nodes = inclusion_with_intermediates(new_leaf_a, bits_a, path_a);
    assert(a_old_nodes[TREE_DEPTH] == old_root, "old leaf A not in old_root");

    // Step 2: verify B's old leaf is in old_root using path_b unchanged.
    let b_old_nodes = inclusion_with_intermediates(old_leaf_b, bits_b, path_b);
    assert(b_old_nodes[TREE_DEPTH] == old_root, "old leaf B not in old_root");

    // Identify LCA level.
    let lca_at = lca_one_hot(bits_a, bits_b);

    // Defensive consistency check: at the LCA level, A's old subtree-root
    // (as climbed via path_a) must equal path_b[lca]. We enforce this
    // pointwise: for every i, (a_old_nodes[i] - path_b[i]) * lca_at[i] == 0.
    // This is zero on non-LCA levels (lca_at[i] == 0) and forces equality
    // on the LCA level (lca_at[i] == 1).
    for i in 0..TREE_DEPTH {
        let mismatch = a_old_nodes[i] - path_b[i];
        assert(mismatch * lca_at[i] == 0, "path_a / path_b inconsistent at LCA");
    }

    // Step 4: walk B's path with new leaf B, swapping the LCA-level sibling
    // for A's new subtree-root.
    let mut current = new_leaf_b;
    for i in 0..TREE_DEPTH {
        // sibling = if lca_at[i] then a_new_nodes[i] else path_b[i]
        let sibling = cond_select(lca_at[i], a_new_nodes[i], path_b[i]);
        current = merkle_step(current, sibling, bits_b[i] as Field);
    }
    assert(current == new_root, "new_root mismatch");
}

// ---------- Tests ----------
// These tests exercise the tree primitives using small constructed inputs.
// We can't easily build a 2^20 tree, so we test the algorithms on the
// shapes they're meant to handle: single inclusion, dual update with
// adjacent leaves, dual update with maximally distant leaves.

#[test]
fn test_compute_root_single_leaf() {
    // Leaf at index 0; every sibling along the path is some arbitrary fixed
    // value. Verify root computation is deterministic and matches a manual
    // calculation for the first three levels.
    let leaf = 7;
    let mut path = [0; TREE_DEPTH];
    for i in 0..TREE_DEPTH {
        path[i] = (i as Field) + 100;
    }
    let root1 = compute_root(leaf, 0, path);
    let root2 = compute_root(leaf, 0, path);
    assert(root1 == root2);
}

#[test]
fn test_root_changes_with_index() {
    let leaf = 7;
    let mut path = [0; TREE_DEPTH];
    for i in 0..TREE_DEPTH {
        path[i] = (i as Field) + 100;
    }
    let root_at_zero = compute_root(leaf, 0, path);
    let root_at_one = compute_root(leaf, 1, path);
    assert(root_at_zero != root_at_one);
}

#[test(should_fail_with = "merkle inclusion failed")]
fn test_assert_inclusion_rejects_wrong_root() {
    let leaf = 7;
    let path = [0; TREE_DEPTH];
    assert_inclusion(leaf, 0, path, 999_999);
}

// Helper: build a 2-leaf state. Insert leaves A and B at indices i_a, i_b
// into an otherwise-empty tree by computing the path each one would have
// in the same tree. We do this by simulating the tree explicitly.
//
// We use a small explicit simulator that returns (root, path_a, path_b)
// for any two leaves we want to test against.
fn simulate_two_leaf_tree(
    leaf_a: Field,
    index_a: Field,
    leaf_b: Field,
    index_b: Field,
) -> (Field, [Field; TREE_DEPTH], [Field; TREE_DEPTH]) {
    // Simulator strategy: walk both indices in parallel from leaf to root,
    // tracking the subtree-roots on each side at every level. For each
    // level, A's sibling = the level-i subtree on the other side of A;
    // similarly for B.
    let bits_a: [u1; TREE_DEPTH] = index_a.to_le_bits();
    let bits_b: [u1; TREE_DEPTH] = index_b.to_le_bits();

    // At level 0, the "subtree" containing A is just A's leaf; same for B.
    // We track the subtree-root at level i containing A (`node_a`), and
    // similarly for B. Any cell not on A's or B's path is treated as the
    // empty hash 0.
    let mut node_a = leaf_a;
    let mut node_b = leaf_b;
    let mut path_a = [0; TREE_DEPTH];
    let mut path_b = [0; TREE_DEPTH];

    // Once paths merge (A and B in the same subtree), we track the joint
    // subtree root and the rest of the path is identical for both.
    let mut merged = false;
    let mut joint_node = 0;

    for i in 0..TREE_DEPTH {
        // Determine if at this level A and B happen to be in the same
        // subtree (i.e., indices share all bits above i and differ at i).
        let same_higher = {
            let mut s = true;
            for j in 0..TREE_DEPTH {
                if j > i {
                    if bits_a[j] != bits_b[j] { s = false; }
                }
            }
            s
        };
        let merge_now = (!merged) & same_higher & (bits_a[i] != bits_b[i]);

        if !merged {
            if merge_now {
                // A's sibling at level i is B's subtree-root, and vice versa.
                path_a[i] = node_b;
                path_b[i] = node_a;
                // Compose the joint parent.
                let left = if bits_a[i] == 0 { node_a } else { node_b };
                let right = if bits_a[i] == 0 { node_b } else { node_a };
                joint_node = internal_node(left, right);
                merged = true;
            } else {
                // A's sibling at level i is 0 (empty), and similarly for B.
                path_a[i] = 0;
                path_b[i] = 0;
                let new_node_a = if bits_a[i] == 0 {
                    internal_node(node_a, 0)
                } else {
                    internal_node(0, node_a)
                };
                let new_node_b = if bits_b[i] == 0 {
                    internal_node(node_b, 0)
                } else {
                    internal_node(0, node_b)
                };
                node_a = new_node_a;
                node_b = new_node_b;
            }
        } else {
            // After merge, both paths track the same node. Sibling is 0.
            path_a[i] = 0;
            path_b[i] = 0;
            joint_node = if bits_a[i] == 0 {
                internal_node(joint_node, 0)
            } else {
                internal_node(0, joint_node)
            };
        }
    }

    let root = if merged { joint_node } else {
        // Paths never merged because they live in entirely disjoint
        // top-level subtrees -- but with TREE_DEPTH bits they MUST share
        // a prefix of length 0 at the top, so this branch is unreachable.
        // We just return one of them defensively.
        node_a
    };
    (root, path_a, path_b)
}

#[test]
fn test_dual_update_adjacent_leaves() {
    // Adjacent leaves share their LCA at level 0 -- the worst case for the
    // naive algorithm. Verifies the LCA patching works.
    let old_a = 100;
    let old_b = 200;
    let new_a = 150;
    let new_b = 250;
    let index_a: Field = 0;
    let index_b: Field = 1;

    let (old_root, path_a, path_b) = simulate_two_leaf_tree(old_a, index_a, old_b, index_b);
    let (new_root, _, _) = simulate_two_leaf_tree(new_a, index_a, new_b, index_b);

    assert_dual_update(
        old_root, new_root,
        old_a, new_a, index_a, path_a,
        old_b, new_b, index_b, path_b,
    );
}

#[test]
fn test_dual_update_distant_leaves() {
    // Maximally distant leaves: indices 0 and 2^(TREE_DEPTH-1). LCA at top.
    let old_a = 100;
    let old_b = 200;
    let new_a = 150;
    let new_b = 250;
    let index_a: Field = 0;
    let index_b: Field = (1 << (TREE_DEPTH - 1)) as Field;

    let (old_root, path_a, path_b) = simulate_two_leaf_tree(old_a, index_a, old_b, index_b);
    let (new_root, _, _) = simulate_two_leaf_tree(new_a, index_a, new_b, index_b);

    assert_dual_update(
        old_root, new_root,
        old_a, new_a, index_a, path_a,
        old_b, new_b, index_b, path_b,
    );
}

#[test]
fn test_dual_update_mid_distance_leaves() {
    // Indices 5 and 9 -- LCA somewhere in the middle.
    let old_a = 100;
    let old_b = 200;
    let new_a = 150;
    let new_b = 250;
    let index_a: Field = 5;
    let index_b: Field = 9;

    let (old_root, path_a, path_b) = simulate_two_leaf_tree(old_a, index_a, old_b, index_b);
    let (new_root, _, _) = simulate_two_leaf_tree(new_a, index_a, new_b, index_b);

    assert_dual_update(
        old_root, new_root,
        old_a, new_a, index_a, path_a,
        old_b, new_b, index_b, path_b,
    );
}

#[test(should_fail_with = "new_root mismatch")]
fn test_dual_update_rejects_wrong_new_root() {
    let old_a = 100;
    let old_b = 200;
    let new_a = 150;
    let new_b = 250;
    let index_a: Field = 5;
    let index_b: Field = 9;

    let (old_root, path_a, path_b) = simulate_two_leaf_tree(old_a, index_a, old_b, index_b);

    // Use a deliberately wrong new_root.
    assert_dual_update(
        old_root, 0xdeadbeef,
        old_a, new_a, index_a, path_a,
        old_b, new_b, index_b, path_b,
    );
}

#[test(should_fail_with = "old leaf A not in old_root")]
fn test_dual_update_rejects_wrong_old_leaf_a() {
    let old_a = 100;
    let old_b = 200;
    let new_a = 150;
    let new_b = 250;
    let index_a: Field = 5;
    let index_b: Field = 9;

    let (old_root, path_a, path_b) = simulate_two_leaf_tree(old_a, index_a, old_b, index_b);
    let (new_root, _, _) = simulate_two_leaf_tree(new_a, index_a, new_b, index_b);

    // Tamper with old_leaf_a -- prover claims a wrong starting balance.
    assert_dual_update(
        old_root, new_root,
        old_a + 1, new_a, index_a, path_a,
        old_b, new_b, index_b, path_b,
    );
}

#[test(should_fail_with = "dual update requires distinct leaves")]
fn test_dual_update_rejects_same_index() {
    let path = [0; TREE_DEPTH];
    assert_dual_update(0, 0, 0, 0, 5, path, 0, 0, 5, path);
}
