// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MerkleTree } from "./libraries/MerkleTree.sol";

/// @title Vault
/// @notice Holds ERC20 deposits and exposes an incremental Merkle root that
///         the engine uses for balance-sufficiency proofs. Withdrawals will
///         eventually use a dedicated `withdrawal` circuit; until that
///         circuit lands, `withdraw` is disabled (see roadmap).
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Vault {
    using MerkleTree for MerkleTree.Tree;

    MerkleTree.Tree internal balanceTree;

    address public darkBookEngine;
    address public owner;

    mapping(address => bool) public supportedTokens;
    mapping(address => mapping(address => uint256)) public userLeafIndex;
    mapping(address => mapping(address => bool)) public hasLeaf;
    mapping(address => mapping(address => uint256)) public pendingDeposits;
    mapping(address => uint256) public totalDeposited;
    mapping(bytes32 => bool) public usedWithdrawalNullifiers;

    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 leafIndex);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event BalanceRootUpdated(bytes32 oldRoot, bytes32 newRoot);
    event TokenAdded(address indexed token);
    event DarkBookEngineSet(address indexed engine);

    error TokenNotSupported();
    error InsufficientAmount();
    error TransferFailed();
    error Unauthorized();
    error NullifierAlreadyUsed();
    error ZeroAddress();
    error NotYetImplemented();

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

    constructor() {
        owner = msg.sender;
        balanceTree.init();
    }

    function setDarkBookEngine(address _engine) external onlyOwner {
        if (_engine == address(0)) revert ZeroAddress();
        darkBookEngine = _engine;
        emit DarkBookEngineSet(_engine);
    }

    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }

    function deposit(address token, uint256 amount) external onlySupportedToken(token) {
        if (amount == 0) revert InsufficientAmount();

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        uint256 leafIndex;
        if (!hasLeaf[msg.sender][token]) {
            bytes32 leaf = MerkleTree.hashLeaf(balanceTree.nextLeafIndex, amount);
            (bytes32 newRoot, uint256 idx) = balanceTree.insert(leaf);
            userLeafIndex[msg.sender][token] = idx;
            hasLeaf[msg.sender][token] = true;
            leafIndex = idx;
            emit BalanceRootUpdated(bytes32(0), newRoot);
        } else {
            leafIndex = userLeafIndex[msg.sender][token];
            pendingDeposits[msg.sender][token] += amount;
        }

        totalDeposited[token] += amount;
        emit Deposited(msg.sender, token, amount, leafIndex);
    }

    /// @notice Withdrawal requires a dedicated ZK circuit that proves the
    ///         caller controls a balance leaf in the current root and is
    ///         withdrawing no more than that balance. That circuit is not
    ///         yet shipped (roadmap item 6); the function reverts with
    ///         `NotYetImplemented` until then.
    function withdraw(
        address /* token */,
        uint256 /* amount */,
        bytes32[] calldata /* merkleProof */,
        bytes calldata /* zkProof */,
        bytes32 /* nullifier */
    ) external pure {
        revert NotYetImplemented();
    }

    function updateBalanceRoot(bytes32 newRoot) external onlyEngine {
        bytes32 oldRoot = balanceTree.root;
        balanceTree.root = newRoot;
        emit BalanceRootUpdated(oldRoot, newRoot);
    }

    function getBalanceRoot() external view returns (bytes32) {
        return balanceTree.root;
    }

    function getNextLeafIndex() external view returns (uint256) {
        return balanceTree.nextLeafIndex;
    }

    function isNullifierUsed(bytes32 nullifier) external view returns (bool) {
        return usedWithdrawalNullifiers[nullifier];
    }
}
