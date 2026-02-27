// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UltraPlonkVerifier } from "./verifiers/UltraPlonkVerifier.sol";

/// @title DarkBookEngine
/// @notice Core orderbook logic — stores commitments, manages the order lifecycle,
///         and settles matches with ZK proof verification.
/// @dev All orders are submitted as opaque commitments. The engine never sees
///      plaintext order parameters (price, amount, side). Validity and balance
///      sufficiency are guaranteed by ZK proofs verified on-chain.

interface IVault {
    function getBalanceRoot() external view returns (bytes32);
    function updateBalanceRoot(bytes32 newRoot) external;
}

contract DarkBookEngine {
    // ============================================================
    //                         TYPES
    // ============================================================

    enum OrderStatus {
        None,       // 0 - does not exist
        Active,     // 1 - submitted and verified
        Filled,     // 2 - fully filled via match
        PartialFill,// 3 - partially filled
        Cancelled   // 4 - cancelled by owner
    }

    struct OrderCommitment {
        bytes32 commitment;      // Pedersen hash of (price, amount, side, salt)
        address owner;           // order submitter
        uint256 tokenPairId;     // which market
        uint256 epoch;           // submission epoch
        uint256 timestamp;       // block timestamp at submission
        OrderStatus status;      // current lifecycle state
        uint256 remainingAmount; // tracks partial fills (in commitment space)
    }

    struct SettlementRecord {
        bytes32 commitmentA;
        bytes32 commitmentB;
        uint256 fillAmount;
        uint256 settlementPrice;
        uint256 timestamp;
    }

    // ============================================================
    //                          STATE
    // ============================================================

    /// @notice The ZK proof verifier
    UltraPlonkVerifier public immutable verifier;

    /// @notice The vault contract for balance verification
    IVault public immutable vault;

    /// @notice Owner for admin functions
    address public owner;

    /// @notice Order commitments indexed by commitment hash
    mapping(bytes32 => OrderCommitment) public commitments;

    /// @notice Nullifier set — prevents double-submission of orders
    mapping(bytes32 => bool) public nullifiers;

    /// @notice Current epoch counter (incremented periodically)
    uint256 public epochCounter;

    /// @notice Active commitment count per token pair
    mapping(uint256 => uint256) public activeCommitmentCount;

    /// @notice All active commitment hashes per token pair (for enumeration)
    mapping(uint256 => bytes32[]) public pairCommitments;

    /// @notice Settlement history
    SettlementRecord[] public settlements;

    /// @notice Matcher/relayer whitelist (authorized to submit settlements)
    mapping(address => bool) public authorizedMatchers;

    /// @notice Whether the matching is permissioned or open
    bool public permissionedMatching;

    // ============================================================
    //                          EVENTS
    // ============================================================

    event OrderSubmitted(
        bytes32 indexed commitment,
        address indexed owner,
        uint256 indexed tokenPairId,
        uint256 epoch,
        uint256 timestamp
    );

    event OrderCancelled(
        bytes32 indexed commitment,
        address indexed owner,
        uint256 timestamp
    );

    event MatchSettled(
        bytes32 indexed commitmentA,
        bytes32 indexed commitmentB,
        uint256 fillAmount,
        uint256 settlementPrice,
        uint256 timestamp
    );

    event EpochAdvanced(uint256 newEpoch);
    event MatcherAuthorized(address indexed matcher);
    event MatcherRevoked(address indexed matcher);

    // ============================================================
    //                         ERRORS
    // ============================================================

    error Unauthorized();
    error InvalidProof();
    error NullifierAlreadyUsed();
    error CommitmentAlreadyExists();
    error CommitmentNotFound();
    error CommitmentNotActive();
    error NotCommitmentOwner();
    error InvalidTokenPair();
    error MatcherNotAuthorized();
    error StaleBalanceRoot();

    // ============================================================
    //                        MODIFIERS
    // ============================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAuthorizedMatcher() {
        if (permissionedMatching && !authorizedMatchers[msg.sender]) {
            revert MatcherNotAuthorized();
        }
        _;
    }

    // ============================================================
    //                       CONSTRUCTOR
    // ============================================================

    constructor(address _verifier, address _vault) {
        owner = msg.sender;
        verifier = UltraPlonkVerifier(_verifier);
        vault = IVault(_vault);
        epochCounter = 1;
        permissionedMatching = true; // start permissioned
    }

    // ============================================================
    //                     ADMIN FUNCTIONS
    // ============================================================

    /// @notice Authorize a matcher address
    function authorizeMatcher(address matcher) external onlyOwner {
        authorizedMatchers[matcher] = true;
        emit MatcherAuthorized(matcher);
    }

    /// @notice Revoke a matcher's authorization
    function revokeMatcher(address matcher) external onlyOwner {
        authorizedMatchers[matcher] = false;
        emit MatcherRevoked(matcher);
    }

    /// @notice Toggle permissioned matching
    function setPermissionedMatching(bool _permissioned) external onlyOwner {
        permissionedMatching = _permissioned;
    }

    /// @notice Advance the epoch
    function advanceEpoch() external onlyOwner {
        epochCounter++;
        emit EpochAdvanced(epochCounter);
    }

    // ============================================================
    //                    ORDER SUBMISSION
    // ============================================================

    /// @notice Submit a new order commitment with a ZK proof of validity
    /// @param commitment The Pedersen commitment to the order
    /// @param nullifier The anti-replay nullifier
    /// @param tokenPairId The trading pair identifier
    /// @param proof The UltraPlonk proof of order validity and balance sufficiency
    function submitOrder(
        bytes32 commitment,
        bytes32 nullifier,
        uint256 tokenPairId,
        bytes calldata proof
    ) external {
        // Validate inputs
        if (tokenPairId == 0) revert InvalidTokenPair();
        if (nullifiers[nullifier]) revert NullifierAlreadyUsed();
        if (commitments[commitment].status != OrderStatus.None) revert CommitmentAlreadyExists();

        // Get current balance root from vault
        bytes32 balanceRoot = vault.getBalanceRoot();

        // Verify ZK proof: order is valid, funded, and commitment matches
        bytes32[] memory publicInputs = new bytes32[](4);
        publicInputs[0] = commitment;
        publicInputs[1] = balanceRoot;
        publicInputs[2] = nullifier;
        publicInputs[3] = bytes32(tokenPairId);

        bool validProof = verifier.verifyOrderCommitment(proof, publicInputs);
        if (!validProof) revert InvalidProof();

        // Mark nullifier as used
        nullifiers[nullifier] = true;

        // Store commitment
        commitments[commitment] = OrderCommitment({
            commitment: commitment,
            owner: msg.sender,
            tokenPairId: tokenPairId,
            epoch: epochCounter,
            timestamp: block.timestamp,
            status: OrderStatus.Active,
            remainingAmount: 0 // unknown in commitment space; tracked off-chain
        });

        // Track in pair's commitment list
        pairCommitments[tokenPairId].push(commitment);
        activeCommitmentCount[tokenPairId]++;

        emit OrderSubmitted(commitment, msg.sender, tokenPairId, epochCounter, block.timestamp);
    }

    // ============================================================
    //                    ORDER CANCELLATION
    // ============================================================

    /// @notice Cancel an active order
    /// @dev Owner proves knowledge of the salt to cancel without revealing order params.
    ///      A simplified version uses signature-based ownership proof.
    /// @param commitment The commitment to cancel
    /// @param cancellationProof Proof of ownership (salt knowledge or signature)
    function cancelOrder(
        bytes32 commitment,
        bytes calldata cancellationProof
    ) external {
        OrderCommitment storage order = commitments[commitment];

        if (order.status == OrderStatus.None) revert CommitmentNotFound();
        if (order.status != OrderStatus.Active && order.status != OrderStatus.PartialFill) {
            revert CommitmentNotActive();
        }
        if (order.owner != msg.sender) revert NotCommitmentOwner();

        // For MVP: ownership is verified by msg.sender == owner
        // In production: verify a ZK proof of salt knowledge
        // This prevents front-running of cancellation by ensuring only
        // the original submitter can cancel
        cancellationProof; // suppress unused warning; used in production

        // Mark as cancelled
        order.status = OrderStatus.Cancelled;
        activeCommitmentCount[order.tokenPairId]--;

        emit OrderCancelled(commitment, msg.sender, block.timestamp);
    }

    // ============================================================
    //                    MATCH SETTLEMENT
    // ============================================================

    /// @notice Settle a match between two order commitments
    /// @param commitA First order commitment
    /// @param commitB Second order commitment
    /// @param fillAmount The fill amount (in base token units)
    /// @param settlementPrice The execution price
    /// @param matchProof ZK proof that the match is valid
    /// @param balanceProof ZK proof that balance updates are correct
    function settleMatch(
        bytes32 commitA,
        bytes32 commitB,
        uint256 fillAmount,
        uint256 settlementPrice,
        bytes calldata matchProof,
        bytes calldata balanceProof
    ) external onlyAuthorizedMatcher {
        // Validate both commitments are active
        OrderCommitment storage orderA = commitments[commitA];
        OrderCommitment storage orderB = commitments[commitB];

        if (orderA.status != OrderStatus.Active && orderA.status != OrderStatus.PartialFill) {
            revert CommitmentNotActive();
        }
        if (orderB.status != OrderStatus.Active && orderB.status != OrderStatus.PartialFill) {
            revert CommitmentNotActive();
        }

        // Verify match proof
        bytes32[] memory matchInputs = new bytes32[](4);
        matchInputs[0] = commitA;
        matchInputs[1] = commitB;
        matchInputs[2] = keccak256(abi.encodePacked(fillAmount, settlementPrice)); // fill hash
        matchInputs[3] = bytes32(settlementPrice);

        bool validMatch = verifier.verifyMatch(matchProof, matchInputs);
        if (!validMatch) revert InvalidProof();

        // Verify balance update proof
        bytes32 currentRoot = vault.getBalanceRoot();
        bytes32[] memory balanceInputs = new bytes32[](4);
        balanceInputs[0] = currentRoot;
        balanceInputs[1] = bytes32(0); // new_root will be extracted from proof
        balanceInputs[2] = commitA;
        balanceInputs[3] = commitB;

        bool validBalance = verifier.verifyBalanceUpdate(balanceProof, balanceInputs);
        if (!validBalance) revert InvalidProof();

        // Update balance root in vault
        // In production, new_root would be extracted from the proof's public outputs
        // For now, we compute a simple transition
        bytes32 newRoot = keccak256(abi.encodePacked(currentRoot, commitA, commitB, fillAmount));
        vault.updateBalanceRoot(newRoot);

        // Update order statuses
        // In a full implementation, we'd track remaining amounts
        // For MVP, we mark as filled
        orderA.status = OrderStatus.Filled;
        orderB.status = OrderStatus.Filled;

        activeCommitmentCount[orderA.tokenPairId]--;
        activeCommitmentCount[orderB.tokenPairId]--;

        // Record settlement
        settlements.push(SettlementRecord({
            commitmentA: commitA,
            commitmentB: commitB,
            fillAmount: fillAmount,
            settlementPrice: settlementPrice,
            timestamp: block.timestamp
        }));

        emit MatchSettled(commitA, commitB, fillAmount, settlementPrice, block.timestamp);
    }

    // ============================================================
    //                     VIEW FUNCTIONS
    // ============================================================

    /// @notice Get the number of active commitments for a token pair
    function getActiveCommitmentCount(uint256 tokenPairId) external view returns (uint256) {
        return activeCommitmentCount[tokenPairId];
    }

    /// @notice Get all commitments for a token pair
    function getPairCommitments(uint256 tokenPairId) external view returns (bytes32[] memory) {
        return pairCommitments[tokenPairId];
    }

    /// @notice Get the total number of settlements
    function getSettlementCount() external view returns (uint256) {
        return settlements.length;
    }

    /// @notice Get an order commitment's details
    function getOrder(bytes32 commitment) external view returns (OrderCommitment memory) {
        return commitments[commitment];
    }

    /// @notice Check if a nullifier has been used
    function isNullifierUsed(bytes32 nullifier) external view returns (bool) {
        return nullifiers[nullifier];
    }
}
