// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MerkleTree } from "./libraries/MerkleTree.sol";
import { UltraPlonkVerifier } from "./verifiers/UltraPlonkVerifier.sol";

/// @title Vault
/// @notice Handles deposits and withdrawals with Merkle-tree balance tracking.
/// @dev Users deposit ERC20 tokens, which are tracked in an incremental Merkle tree.
///      Withdrawals require a ZK proof of balance ownership without revealing the full balance.
///      The Merkle root is used by DarkBookEngine to verify order balance sufficiency.
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Vault {
    using MerkleTree for MerkleTree.Tree;

    // ============================================================
    //                          STATE
    // ============================================================

    /// @notice The incremental Merkle tree tracking all balances
    MerkleTree.Tree internal balanceTree;

    /// @notice The ZK proof verifier contract
    UltraPlonkVerifier public immutable verifier;

    /// @notice The DarkBook engine contract (authorized to update roots)
    address public darkBookEngine;

    /// @notice Owner address for admin functions
    address public owner;

    /// @notice Supported token whitelist
    mapping(address => bool) public supportedTokens;

    /// @notice User's leaf index in the Merkle tree per token
    /// user address => token address => leaf index
    mapping(address => mapping(address => uint256)) public userLeafIndex;

    /// @notice Whether a user has a leaf for a given token
    mapping(address => mapping(address => bool)) public hasLeaf;

    /// @notice Pending deposits that haven't been committed to the tree yet
    mapping(address => mapping(address => uint256)) public pendingDeposits;

    /// @notice Total deposited per token (for accounting)
    mapping(address => uint256) public totalDeposited;

    /// @notice Nullifier set for withdrawal proofs (prevents double-withdrawal)
    mapping(bytes32 => bool) public usedWithdrawalNullifiers;

    // ============================================================
    //                          EVENTS
    // ============================================================

    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 leafIndex);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event BalanceRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event TokenAdded(address indexed token);
    event DarkBookEngineSet(address indexed engine);

    // ============================================================
    //                         ERRORS
    // ============================================================

    error TokenNotSupported();
    error InsufficientAmount();
    error TransferFailed();
    error Unauthorized();
    error InvalidProof();
    error NullifierAlreadyUsed();
    error ZeroAddress();

    // ============================================================
    //                        MODIFIERS
    // ============================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyEngine() {
        if (msg.sender != darkBookEngine) revert Unauthorized();
        _;
    }

    modifier onlySupportedToken(address token) {
        if (!supportedTokens[token]) revert TokenNotSupported();
        _;
    }

    // ============================================================
    //                       CONSTRUCTOR
    // ============================================================

    constructor(address _verifier) {
        owner = msg.sender;
        verifier = UltraPlonkVerifier(_verifier);
        balanceTree.init();
    }

    // ============================================================
    //                     ADMIN FUNCTIONS
    // ============================================================

    /// @notice Set the DarkBook engine contract address
    function setDarkBookEngine(address _engine) external onlyOwner {
        if (_engine == address(0)) revert ZeroAddress();
        darkBookEngine = _engine;
        emit DarkBookEngineSet(_engine);
    }

    /// @notice Add a supported token
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    // ============================================================
    //                    DEPOSIT FUNCTIONS
    // ============================================================

    /// @notice Deposit ERC20 tokens into the vault
    /// @param token The token address to deposit
    /// @param amount The amount to deposit
    function deposit(address token, uint256 amount) external onlySupportedToken(token) {
        if (amount == 0) revert InsufficientAmount();

        // Transfer tokens from user to vault
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        // Create or update Merkle leaf
        uint256 leafIndex;
        if (!hasLeaf[msg.sender][token]) {
            // First deposit: create new leaf
            bytes32 leaf = MerkleTree.hashLeaf(balanceTree.nextLeafIndex, amount);
            (bytes32 newRoot, uint256 idx) = balanceTree.insert(leaf);

            userLeafIndex[msg.sender][token] = idx;
            hasLeaf[msg.sender][token] = true;
            leafIndex = idx;

            emit BalanceRootUpdated(bytes32(0), newRoot);
        } else {
            // Subsequent deposit: add to pending (will be batched into tree update)
            leafIndex = userLeafIndex[msg.sender][token];
            pendingDeposits[msg.sender][token] += amount;
        }

        totalDeposited[token] += amount;
        emit Deposited(msg.sender, token, amount, leafIndex);
    }

    /// @notice Withdraw tokens from the vault with a ZK proof of balance
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    /// @param merkleProof The Merkle proof of the user's balance leaf
    /// @param zkProof The ZK proof that the user has sufficient balance
    /// @param nullifier A unique nullifier to prevent double-withdrawal
    function withdraw(
        address token,
        uint256 amount,
        bytes32[] calldata merkleProof,
        bytes calldata zkProof,
        bytes32 nullifier
    ) external onlySupportedToken(token) {
        if (amount == 0) revert InsufficientAmount();
        if (usedWithdrawalNullifiers[nullifier]) revert NullifierAlreadyUsed();

        // Verify the ZK proof of balance sufficiency
        bytes32[] memory publicInputs = new bytes32[](4);
        publicInputs[0] = bytes32(uint256(uint160(msg.sender)));
        publicInputs[1] = bytes32(uint256(uint160(token)));
        publicInputs[2] = bytes32(amount);
        publicInputs[3] = balanceTree.root;

        // Note: In production, this would use a dedicated withdrawal circuit verifier
        // For now, we verify against the order commitment verifier as a placeholder
        bool validProof = verifier.verifyOrderCommitment(zkProof, publicInputs);
        if (!validProof) revert InvalidProof();

        // Mark nullifier as used
        usedWithdrawalNullifiers[nullifier] = true;

        // Transfer tokens to user
        bool success = IERC20(token).transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        totalDeposited[token] -= amount;
        emit Withdrawn(msg.sender, token, amount);
    }

    // ============================================================
    //                     ENGINE FUNCTIONS
    // ============================================================

    /// @notice Update the balance root after settlement (called by DarkBookEngine)
    /// @param newRoot The new Merkle root after balance updates
    function updateBalanceRoot(bytes32 newRoot) external onlyEngine {
        bytes32 oldRoot = balanceTree.root;
        balanceTree.root = newRoot;
        emit BalanceRootUpdated(oldRoot, newRoot);
    }

    // ============================================================
    //                     VIEW FUNCTIONS
    // ============================================================

    /// @notice Get the current balance Merkle root
    function getBalanceRoot() external view returns (bytes32) {
        return balanceTree.root;
    }

    /// @notice Get the next available leaf index
    function getNextLeafIndex() external view returns (uint256) {
        return balanceTree.nextLeafIndex;
    }

    /// @notice Check if a withdrawal nullifier has been used
    function isNullifierUsed(bytes32 nullifier) external view returns (bool) {
        return usedWithdrawalNullifiers[nullifier];
    }
}
