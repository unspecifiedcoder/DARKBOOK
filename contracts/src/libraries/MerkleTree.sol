// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MerkleTree
/// @notice Incremental Merkle tree for tracking vault balances on-chain.
/// @dev Uses Pedersen-compatible hashing (keccak256 as placeholder).
///      Supports up to 2^TREE_DEPTH leaves.
library MerkleTree {
    uint256 internal constant TREE_DEPTH = 20;
    uint256 internal constant MAX_LEAVES = 1 << TREE_DEPTH; // 2^20 = 1,048,576

    struct Tree {
        uint256 nextLeafIndex;
        bytes32[TREE_DEPTH] filledSubtrees; // cached left-most non-empty subtree hashes
        bytes32 root;
    }

    /// @notice Get the zero (empty) value for a given tree level
    /// @dev Precomputed zeros: zero[0] = hash(0), zero[i] = hash(zero[i-1], zero[i-1])
    function zeros(uint256 level) internal pure returns (bytes32) {
        // Level 0 zero value
        if (level == 0) return bytes32(0);
        // For simplicity, compute iteratively. In production, these would be precomputed constants.
        bytes32 current = bytes32(0);
        for (uint256 i = 0; i < level; i++) {
            current = _hashPair(current, current);
        }
        return current;
    }

    /// @notice Initialize a new Merkle tree
    function init(Tree storage tree) internal {
        tree.nextLeafIndex = 0;
        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            tree.filledSubtrees[i] = zeros(i);
        }
        tree.root = zeros(TREE_DEPTH);
    }

    /// @notice Insert a leaf into the tree and return the new root
    /// @param tree The tree storage reference
    /// @param leaf The leaf value to insert
    /// @return newRoot The updated Merkle root
    /// @return leafIndex The index where the leaf was inserted
    function insert(Tree storage tree, bytes32 leaf) internal returns (bytes32 newRoot, uint256 leafIndex) {
        require(tree.nextLeafIndex < MAX_LEAVES, "Merkle tree is full");

        leafIndex = tree.nextLeafIndex;
        tree.nextLeafIndex++;

        bytes32 currentHash = leaf;
        uint256 currentIndex = leafIndex;

        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            if (currentIndex % 2 == 0) {
                // Current node is a left child
                tree.filledSubtrees[i] = currentHash;
                currentHash = _hashPair(currentHash, zeros(i));
            } else {
                // Current node is a right child
                currentHash = _hashPair(tree.filledSubtrees[i], currentHash);
            }
            currentIndex /= 2;
        }

        tree.root = currentHash;
        newRoot = currentHash;
    }

    /// @notice Verify a Merkle proof for a given leaf
    /// @param root The expected Merkle root
    /// @param leaf The leaf value to verify
    /// @param index The leaf index
    /// @param proof The sibling hashes along the path
    /// @return True if the proof is valid
    function verify(
        bytes32 root,
        bytes32 leaf,
        uint256 index,
        bytes32[] memory proof
    ) internal pure returns (bool) {
        require(proof.length == TREE_DEPTH, "Invalid proof length");

        bytes32 currentHash = leaf;
        uint256 currentIndex = index;

        for (uint256 i = 0; i < TREE_DEPTH; i++) {
            if (currentIndex % 2 == 0) {
                currentHash = _hashPair(currentHash, proof[i]);
            } else {
                currentHash = _hashPair(proof[i], currentHash);
            }
            currentIndex /= 2;
        }

        return currentHash == root;
    }

    /// @notice Hash a leaf value: H(index, value)
    function hashLeaf(uint256 index, uint256 value) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, value));
    }

    /// @dev Hash two child nodes to produce parent
    function _hashPair(bytes32 left, bytes32 right) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(left, right));
    }
}
