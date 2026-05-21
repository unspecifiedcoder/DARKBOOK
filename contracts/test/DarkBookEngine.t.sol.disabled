// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { UltraPlonkVerifier } from "../src/verifiers/UltraPlonkVerifier.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @title MockERC20
/// @notice Minimal ERC20 for testing
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract DarkBookEngineTest is Test {
    UltraPlonkVerifier verifier;
    Vault vault;
    DarkBookEngine engine;
    MockERC20 token;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address matcher = makeAddr("matcher");

    uint256 constant TOKEN_PAIR_ID = 1;

    function setUp() public {
        // Deploy contracts
        verifier = new UltraPlonkVerifier();
        vault = new Vault(address(verifier));
        engine = new DarkBookEngine(address(verifier), address(vault));

        // Deploy mock token
        token = new MockERC20();

        // Configure
        vault.setDarkBookEngine(address(engine));
        vault.addSupportedToken(address(token));
        engine.authorizeMatcher(matcher);

        // Fund users
        token.mint(alice, 100_000e18);
        token.mint(bob, 100_000e18);

        // Approve vault
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        token.approve(address(vault), type(uint256).max);
    }

    // ============================================================
    //                    DEPOSIT TESTS
    // ============================================================

    function test_deposit() public {
        vm.prank(alice);
        vault.deposit(address(token), 1000e18);

        assertEq(token.balanceOf(address(vault)), 1000e18);
        assertEq(vault.totalDeposited(address(token)), 1000e18);
        assertTrue(vault.hasLeaf(alice, address(token)));
    }

    function test_deposit_reverts_unsupported_token() public {
        MockERC20 badToken = new MockERC20();
        vm.prank(alice);
        vm.expectRevert(Vault.TokenNotSupported.selector);
        vault.deposit(address(badToken), 1000e18);
    }

    function test_deposit_reverts_zero_amount() public {
        vm.prank(alice);
        vm.expectRevert(Vault.InsufficientAmount.selector);
        vault.deposit(address(token), 0);
    }

    // ============================================================
    //                  ORDER SUBMISSION TESTS
    // ============================================================

    function test_submitOrder() public {
        // First deposit
        vm.prank(alice);
        vault.deposit(address(token), 1000e18);

        // Submit order with mock proof
        bytes32 commitment = keccak256("order1");
        bytes32 nullifier = keccak256("null1");
        bytes memory proof = hex"01";

        vm.prank(alice);
        engine.submitOrder(commitment, nullifier, TOKEN_PAIR_ID, proof);

        // Verify state
        DarkBookEngine.OrderCommitment memory order = engine.getOrder(commitment);
        assertEq(order.owner, alice);
        assertEq(order.tokenPairId, TOKEN_PAIR_ID);
        assertTrue(order.status == DarkBookEngine.OrderStatus.Active);
        assertTrue(engine.isNullifierUsed(nullifier));
        assertEq(engine.getActiveCommitmentCount(TOKEN_PAIR_ID), 1);
    }

    function test_submitOrder_reverts_duplicate_nullifier() public {
        vm.prank(alice);
        vault.deposit(address(token), 1000e18);

        bytes32 nullifier = keccak256("null1");
        bytes memory proof = hex"01";

        vm.prank(alice);
        engine.submitOrder(keccak256("order1"), nullifier, TOKEN_PAIR_ID, proof);

        vm.prank(bob);
        vm.expectRevert(DarkBookEngine.NullifierAlreadyUsed.selector);
        engine.submitOrder(keccak256("order2"), nullifier, TOKEN_PAIR_ID, proof);
    }

    function test_submitOrder_reverts_duplicate_commitment() public {
        bytes32 commitment = keccak256("order1");
        bytes memory proof = hex"01";

        vm.prank(alice);
        engine.submitOrder(commitment, keccak256("null1"), TOKEN_PAIR_ID, proof);

        vm.prank(bob);
        vm.expectRevert(DarkBookEngine.CommitmentAlreadyExists.selector);
        engine.submitOrder(commitment, keccak256("null2"), TOKEN_PAIR_ID, proof);
    }

    function test_submitOrder_reverts_invalid_pair() public {
        vm.prank(alice);
        vm.expectRevert(DarkBookEngine.InvalidTokenPair.selector);
        engine.submitOrder(keccak256("order1"), keccak256("null1"), 0, hex"01");
    }

    // ============================================================
    //                  CANCELLATION TESTS
    // ============================================================

    function test_cancelOrder() public {
        bytes32 commitment = keccak256("order1");
        bytes memory proof = hex"01";

        vm.prank(alice);
        engine.submitOrder(commitment, keccak256("null1"), TOKEN_PAIR_ID, proof);

        vm.prank(alice);
        engine.cancelOrder(commitment, hex"");

        DarkBookEngine.OrderCommitment memory order = engine.getOrder(commitment);
        assertTrue(order.status == DarkBookEngine.OrderStatus.Cancelled);
        assertEq(engine.getActiveCommitmentCount(TOKEN_PAIR_ID), 0);
    }

    function test_cancelOrder_reverts_not_owner() public {
        bytes32 commitment = keccak256("order1");

        vm.prank(alice);
        engine.submitOrder(commitment, keccak256("null1"), TOKEN_PAIR_ID, hex"01");

        vm.prank(bob);
        vm.expectRevert(DarkBookEngine.NotCommitmentOwner.selector);
        engine.cancelOrder(commitment, hex"");
    }

    // ============================================================
    //                  SETTLEMENT TESTS
    // ============================================================

    function test_settleMatch() public {
        // Submit two orders
        bytes32 commitA = keccak256("orderA");
        bytes32 commitB = keccak256("orderB");

        vm.prank(alice);
        engine.submitOrder(commitA, keccak256("nullA"), TOKEN_PAIR_ID, hex"01");

        vm.prank(bob);
        engine.submitOrder(commitB, keccak256("nullB"), TOKEN_PAIR_ID, hex"01");

        // Settle match
        uint256 fillAmount = 10e18;
        uint256 price = 100e6;

        vm.prank(matcher);
        engine.settleMatch(commitA, commitB, fillAmount, price, hex"01", hex"01");

        // Verify state
        DarkBookEngine.OrderCommitment memory orderA = engine.getOrder(commitA);
        DarkBookEngine.OrderCommitment memory orderB = engine.getOrder(commitB);
        assertTrue(orderA.status == DarkBookEngine.OrderStatus.Filled);
        assertTrue(orderB.status == DarkBookEngine.OrderStatus.Filled);
        assertEq(engine.getSettlementCount(), 1);
    }

    function test_settleMatch_reverts_unauthorized() public {
        bytes32 commitA = keccak256("orderA");
        bytes32 commitB = keccak256("orderB");

        vm.prank(alice);
        engine.submitOrder(commitA, keccak256("nullA"), TOKEN_PAIR_ID, hex"01");
        vm.prank(bob);
        engine.submitOrder(commitB, keccak256("nullB"), TOKEN_PAIR_ID, hex"01");

        // Try to settle as non-matcher
        vm.prank(alice);
        vm.expectRevert(DarkBookEngine.MatcherNotAuthorized.selector);
        engine.settleMatch(commitA, commitB, 10e18, 100e6, hex"01", hex"01");
    }

    // ============================================================
    //                    ADMIN TESTS
    // ============================================================

    function test_advanceEpoch() public {
        assertEq(engine.epochCounter(), 1);
        engine.advanceEpoch();
        assertEq(engine.epochCounter(), 2);
    }

    function test_authorizeMatcher() public {
        address newMatcher = makeAddr("newMatcher");
        engine.authorizeMatcher(newMatcher);
        assertTrue(engine.authorizedMatchers(newMatcher));
    }

    function test_revokeMatcher() public {
        engine.revokeMatcher(matcher);
        assertFalse(engine.authorizedMatchers(matcher));
    }
}
