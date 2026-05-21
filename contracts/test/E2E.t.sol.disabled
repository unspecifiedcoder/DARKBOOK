// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { UltraPlonkVerifier } from "../src/verifiers/UltraPlonkVerifier.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @title MockERC20
contract MockERC20 {
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
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

/// @title MockERC20NoReturn — token that doesn't return bool on transfer (non-standard)
contract MockERC20NoReturn {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external { balanceOf[to] += amount; }
    function approve(address spender, uint256 amount) external { allowance[msg.sender][spender] = amount; }
    function transfer(address to, uint256 amount) external { balanceOf[msg.sender] -= amount; balanceOf[to] += amount; }
    function transferFrom(address from, address to, uint256 amount) external {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
    }
}

// ============================================================
//  E2E Happy Flow Test
// ============================================================
contract E2EHappyFlowTest is Test {
    UltraPlonkVerifier verifier;
    Vault vault;
    DarkBookEngine engine;
    MockERC20 usdc;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address matcher = makeAddr("matcher");
    address deployer;

    uint256 constant PAIR_ETH_USDC = 1;

    function setUp() public {
        deployer = address(this);

        verifier = new UltraPlonkVerifier();
        usdc = new MockERC20();
        vault = new Vault(address(verifier));
        engine = new DarkBookEngine(address(verifier), address(vault));

        vault.setDarkBookEngine(address(engine));
        vault.addSupportedToken(address(usdc));
        engine.authorizeMatcher(matcher);

        // Fund Alice (buyer) with 10,000 USDC
        usdc.mint(alice, 10_000e6);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        // Fund Bob (seller) with 10,000 USDC
        usdc.mint(bob, 10_000e6);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    /// @notice Full happy path: Deposit -> Submit Orders -> Match -> Settle -> Verify
    function test_fullHappyFlow() public {
        // ========== STEP 1: DEPOSITS ==========
        vm.prank(alice);
        vault.deposit(address(usdc), 5_000e6);
        assertEq(usdc.balanceOf(address(vault)), 5_000e6, "Vault should hold Alice's deposit");
        assertEq(vault.totalDeposited(address(usdc)), 5_000e6);

        vm.prank(bob);
        vault.deposit(address(usdc), 3_000e6);
        assertEq(usdc.balanceOf(address(vault)), 8_000e6, "Vault should hold both deposits");
        assertEq(vault.totalDeposited(address(usdc)), 8_000e6);

        // Verify balance root is non-zero (tree was updated)
        bytes32 rootAfterDeposits = vault.getBalanceRoot();
        assertTrue(rootAfterDeposits != bytes32(0), "Balance root should be non-zero after deposits");

        // ========== STEP 2: SUBMIT ORDERS ==========
        // Alice submits a BUY order commitment
        bytes32 aliceCommitment = keccak256("alice_buy_100_at_2000");
        bytes32 aliceNullifier = keccak256("alice_null_1");
        bytes memory aliceProof = hex"01";

        vm.prank(alice);
        engine.submitOrder(aliceCommitment, aliceNullifier, PAIR_ETH_USDC, aliceProof);

        // Bob submits a SELL order commitment
        bytes32 bobCommitment = keccak256("bob_sell_100_at_1990");
        bytes32 bobNullifier = keccak256("bob_null_1");
        bytes memory bobProof = hex"01";

        vm.prank(bob);
        engine.submitOrder(bobCommitment, bobNullifier, PAIR_ETH_USDC, bobProof);

        // Verify both orders are active
        assertEq(engine.getActiveCommitmentCount(PAIR_ETH_USDC), 2, "Should have 2 active commitments");
        
        DarkBookEngine.OrderCommitment memory aliceOrder = engine.getOrder(aliceCommitment);
        assertEq(aliceOrder.owner, alice);
        assertTrue(aliceOrder.status == DarkBookEngine.OrderStatus.Active);
        assertEq(aliceOrder.epoch, 1);

        DarkBookEngine.OrderCommitment memory bobOrder = engine.getOrder(bobCommitment);
        assertEq(bobOrder.owner, bob);
        assertTrue(bobOrder.status == DarkBookEngine.OrderStatus.Active);

        // ========== STEP 3: MATCH SETTLEMENT ==========
        uint256 fillAmount = 50e6;        // 50 units filled
        uint256 settlementPrice = 1995e6; // midpoint price

        vm.prank(matcher);
        engine.settleMatch(
            aliceCommitment,
            bobCommitment,
            fillAmount,
            settlementPrice,
            hex"01", // match proof
            hex"01"  // balance update proof
        );

        // ========== STEP 4: VERIFY POST-SETTLEMENT STATE ==========
        // Both orders should be Filled
        DarkBookEngine.OrderCommitment memory aliceAfter = engine.getOrder(aliceCommitment);
        DarkBookEngine.OrderCommitment memory bobAfter = engine.getOrder(bobCommitment);
        assertTrue(aliceAfter.status == DarkBookEngine.OrderStatus.Filled, "Alice order should be Filled");
        assertTrue(bobAfter.status == DarkBookEngine.OrderStatus.Filled, "Bob order should be Filled");

        // Active commitment count should be 0
        assertEq(engine.getActiveCommitmentCount(PAIR_ETH_USDC), 0, "No active commitments after settlement");

        // Settlement should be recorded
        assertEq(engine.getSettlementCount(), 1, "Should have 1 settlement");

        // Balance root should have changed
        bytes32 rootAfterSettlement = vault.getBalanceRoot();
        assertTrue(rootAfterSettlement != rootAfterDeposits, "Balance root should change after settlement");

        // Nullifiers should be consumed
        assertTrue(engine.isNullifierUsed(aliceNullifier), "Alice nullifier used");
        assertTrue(engine.isNullifierUsed(bobNullifier), "Bob nullifier used");
    }

    /// @notice Multiple deposits from same user accumulate correctly
    function test_multipleDeposits() public {
        vm.startPrank(alice);
        vault.deposit(address(usdc), 1_000e6);
        vault.deposit(address(usdc), 2_000e6); // second deposit goes to pending
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(vault)), 3_000e6);
        assertEq(vault.totalDeposited(address(usdc)), 3_000e6);
        // Pending deposits should accumulate
        assertEq(vault.pendingDeposits(alice, address(usdc)), 2_000e6);
    }

    /// @notice Multiple orders, multiple matches in sequence
    function test_multipleOrdersAndMatches() public {
        // Deposits
        vm.prank(alice);
        vault.deposit(address(usdc), 5_000e6);
        vm.prank(bob);
        vault.deposit(address(usdc), 5_000e6);

        // Submit 3 orders each
        bytes memory proof = hex"01";
        
        // Alice: 3 buy orders
        vm.startPrank(alice);
        engine.submitOrder(keccak256("a1"), keccak256("an1"), PAIR_ETH_USDC, proof);
        engine.submitOrder(keccak256("a2"), keccak256("an2"), PAIR_ETH_USDC, proof);
        engine.submitOrder(keccak256("a3"), keccak256("an3"), PAIR_ETH_USDC, proof);
        vm.stopPrank();

        // Bob: 3 sell orders
        vm.startPrank(bob);
        engine.submitOrder(keccak256("b1"), keccak256("bn1"), PAIR_ETH_USDC, proof);
        engine.submitOrder(keccak256("b2"), keccak256("bn2"), PAIR_ETH_USDC, proof);
        engine.submitOrder(keccak256("b3"), keccak256("bn3"), PAIR_ETH_USDC, proof);
        vm.stopPrank();

        assertEq(engine.getActiveCommitmentCount(PAIR_ETH_USDC), 6);

        // Settle 2 matches
        vm.startPrank(matcher);
        engine.settleMatch(keccak256("a1"), keccak256("b1"), 10e6, 2000e6, proof, proof);
        engine.settleMatch(keccak256("a2"), keccak256("b2"), 20e6, 1990e6, proof, proof);
        vm.stopPrank();

        assertEq(engine.getActiveCommitmentCount(PAIR_ETH_USDC), 2);
        assertEq(engine.getSettlementCount(), 2);
    }

    /// @notice Order submission then cancellation then re-submit with new commitment
    function test_cancelAndResubmit() public {
        vm.prank(alice);
        vault.deposit(address(usdc), 5_000e6);

        bytes memory proof = hex"01";

        // Submit order
        vm.prank(alice);
        engine.submitOrder(keccak256("order1"), keccak256("null1"), PAIR_ETH_USDC, proof);
        assertEq(engine.getActiveCommitmentCount(PAIR_ETH_USDC), 1);

        // Cancel order
        vm.prank(alice);
        engine.cancelOrder(keccak256("order1"), hex"");
        assertEq(engine.getActiveCommitmentCount(PAIR_ETH_USDC), 0);

        // Submit new order (different commitment and nullifier)
        vm.prank(alice);
        engine.submitOrder(keccak256("order2"), keccak256("null2"), PAIR_ETH_USDC, proof);
        assertEq(engine.getActiveCommitmentCount(PAIR_ETH_USDC), 1);
    }

    /// @notice Epoch advancement works correctly
    function test_epochTracking() public {
        assertEq(engine.epochCounter(), 1);

        vm.prank(alice);
        vault.deposit(address(usdc), 5_000e6);

        // Submit order in epoch 1
        vm.prank(alice);
        engine.submitOrder(keccak256("e1_order"), keccak256("e1_null"), PAIR_ETH_USDC, hex"01");
        DarkBookEngine.OrderCommitment memory order1 = engine.getOrder(keccak256("e1_order"));
        assertEq(order1.epoch, 1);

        // Advance epoch
        engine.advanceEpoch();
        assertEq(engine.epochCounter(), 2);

        // Submit order in epoch 2
        vm.prank(bob);
        vault.deposit(address(usdc), 5_000e6);
        vm.prank(bob);
        engine.submitOrder(keccak256("e2_order"), keccak256("e2_null"), PAIR_ETH_USDC, hex"01");
        DarkBookEngine.OrderCommitment memory order2 = engine.getOrder(keccak256("e2_order"));
        assertEq(order2.epoch, 2);
    }
}

// ============================================================
//  Worst Case / Attack Scenario Tests
// ============================================================
contract WorstCaseTest is Test {
    UltraPlonkVerifier verifier;
    Vault vault;
    DarkBookEngine engine;
    MockERC20 usdc;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");
    address matcher = makeAddr("matcher");

    uint256 constant PAIR_ETH_USDC = 1;

    function setUp() public {
        verifier = new UltraPlonkVerifier();
        usdc = new MockERC20();
        vault = new Vault(address(verifier));
        engine = new DarkBookEngine(address(verifier), address(vault));

        vault.setDarkBookEngine(address(engine));
        vault.addSupportedToken(address(usdc));
        engine.authorizeMatcher(matcher);

        usdc.mint(alice, 100_000e6);
        usdc.mint(bob, 100_000e6);
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ========== DOUBLE-SUBMIT ATTACKS ==========

    /// @notice Cannot reuse the same nullifier (prevents double-submit)
    function test_doubleSubmitSameNullifier() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("order_a"), keccak256("shared_null"), PAIR_ETH_USDC, hex"01");

        // Attacker tries to use same nullifier with different commitment
        vm.prank(attacker);
        vm.expectRevert(DarkBookEngine.NullifierAlreadyUsed.selector);
        engine.submitOrder(keccak256("order_b"), keccak256("shared_null"), PAIR_ETH_USDC, hex"01");
    }

    /// @notice Cannot submit the same commitment twice
    function test_doubleSubmitSameCommitment() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("same_order"), keccak256("null_1"), PAIR_ETH_USDC, hex"01");

        vm.prank(bob);
        vm.expectRevert(DarkBookEngine.CommitmentAlreadyExists.selector);
        engine.submitOrder(keccak256("same_order"), keccak256("null_2"), PAIR_ETH_USDC, hex"01");
    }

    // ========== UNAUTHORIZED ACCESS ==========

    /// @notice Non-matcher cannot settle matches
    function test_unauthorizedSettlement() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("a"), keccak256("an"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("b"), keccak256("bn"), PAIR_ETH_USDC, hex"01");

        // Attacker tries to settle
        vm.prank(attacker);
        vm.expectRevert(DarkBookEngine.MatcherNotAuthorized.selector);
        engine.settleMatch(keccak256("a"), keccak256("b"), 10e6, 2000e6, hex"01", hex"01");
    }

    /// @notice Non-owner cannot cancel someone else's order
    function test_unauthorizedCancellation() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("alice_order"), keccak256("null1"), PAIR_ETH_USDC, hex"01");

        // Attacker tries to cancel Alice's order
        vm.prank(attacker);
        vm.expectRevert(DarkBookEngine.NotCommitmentOwner.selector);
        engine.cancelOrder(keccak256("alice_order"), hex"");
    }

    /// @notice Non-owner cannot modify admin settings
    function test_unauthorizedAdmin() public {
        vm.prank(attacker);
        vm.expectRevert(DarkBookEngine.Unauthorized.selector);
        engine.authorizeMatcher(attacker);

        vm.prank(attacker);
        vm.expectRevert(DarkBookEngine.Unauthorized.selector);
        engine.advanceEpoch();

        vm.prank(attacker);
        vm.expectRevert(DarkBookEngine.Unauthorized.selector);
        engine.setPermissionedMatching(false);
    }

    /// @notice Non-owner cannot modify vault admin settings
    function test_unauthorizedVaultAdmin() public {
        vm.prank(attacker);
        vm.expectRevert(Vault.Unauthorized.selector);
        vault.setDarkBookEngine(attacker);

        vm.prank(attacker);
        vm.expectRevert(Vault.Unauthorized.selector);
        vault.addSupportedToken(address(0x1234));
    }

    /// @notice Only engine can update balance root
    function test_unauthorizedBalanceRootUpdate() public {
        vm.prank(attacker);
        vm.expectRevert(Vault.Unauthorized.selector);
        vault.updateBalanceRoot(bytes32(uint256(0xdead)));
    }

    // ========== INVALID STATE TRANSITIONS ==========

    /// @notice Cannot settle already-filled orders
    function test_settleAlreadyFilledOrder() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("a"), keccak256("an"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("b"), keccak256("bn"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("c"), keccak256("cn"), PAIR_ETH_USDC, hex"01");

        // Settle a <> b
        vm.prank(matcher);
        engine.settleMatch(keccak256("a"), keccak256("b"), 10e6, 2000e6, hex"01", hex"01");

        // Try to settle a <> c (a is already Filled)
        vm.prank(matcher);
        vm.expectRevert(DarkBookEngine.CommitmentNotActive.selector);
        engine.settleMatch(keccak256("a"), keccak256("c"), 5e6, 2000e6, hex"01", hex"01");
    }

    /// @notice Cannot settle cancelled orders
    function test_settleCancelledOrder() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("a"), keccak256("an"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("b"), keccak256("bn"), PAIR_ETH_USDC, hex"01");

        // Alice cancels
        vm.prank(alice);
        engine.cancelOrder(keccak256("a"), hex"");

        // Try to settle with cancelled order
        vm.prank(matcher);
        vm.expectRevert(DarkBookEngine.CommitmentNotActive.selector);
        engine.settleMatch(keccak256("a"), keccak256("b"), 10e6, 2000e6, hex"01", hex"01");
    }

    /// @notice Cannot cancel non-existent order
    function test_cancelNonExistentOrder() public {
        vm.prank(alice);
        vm.expectRevert(DarkBookEngine.CommitmentNotFound.selector);
        engine.cancelOrder(keccak256("nonexistent"), hex"");
    }

    /// @notice Cannot cancel already-cancelled order
    function test_doubleCancelOrder() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("order"), keccak256("null"), PAIR_ETH_USDC, hex"01");

        vm.prank(alice);
        engine.cancelOrder(keccak256("order"), hex"");

        vm.prank(alice);
        vm.expectRevert(DarkBookEngine.CommitmentNotActive.selector);
        engine.cancelOrder(keccak256("order"), hex"");
    }

    // ========== VAULT EDGE CASES ==========

    /// @notice Cannot deposit unsupported token
    function test_depositUnsupportedToken() public {
        MockERC20 badToken = new MockERC20();
        badToken.mint(alice, 1000e6);

        vm.startPrank(alice);
        badToken.approve(address(vault), type(uint256).max);
        vm.expectRevert(Vault.TokenNotSupported.selector);
        vault.deposit(address(badToken), 100e6);
        vm.stopPrank();
    }

    /// @notice Cannot deposit zero amount
    function test_depositZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Vault.InsufficientAmount.selector);
        vault.deposit(address(usdc), 0);
    }

    /// @notice Cannot deposit more than balance
    function test_depositMoreThanBalance() public {
        vm.prank(alice);
        vm.expectRevert(); // ERC20 transferFrom will fail
        vault.deposit(address(usdc), 200_000e6); // Alice only has 100_000
    }

    /// @notice Cannot set engine to zero address
    function test_setEngineZeroAddress() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.setDarkBookEngine(address(0));
    }

    /// @notice Cannot add zero address as supported token
    function test_addZeroToken() public {
        vm.expectRevert(Vault.ZeroAddress.selector);
        vault.addSupportedToken(address(0));
    }

    // ========== TOKEN PAIR VALIDATION ==========

    /// @notice Cannot submit order for pair ID 0
    function test_invalidTokenPairZero() public {
        vm.prank(alice);
        vm.expectRevert(DarkBookEngine.InvalidTokenPair.selector);
        engine.submitOrder(keccak256("order"), keccak256("null"), 0, hex"01");
    }

    // ========== MATCHER MANAGEMENT ==========

    /// @notice Revoked matcher cannot settle
    function test_revokedMatcherCannotSettle() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("a"), keccak256("an"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("b"), keccak256("bn"), PAIR_ETH_USDC, hex"01");

        // Revoke matcher
        engine.revokeMatcher(matcher);

        // Matcher can no longer settle
        vm.prank(matcher);
        vm.expectRevert(DarkBookEngine.MatcherNotAuthorized.selector);
        engine.settleMatch(keccak256("a"), keccak256("b"), 10e6, 2000e6, hex"01", hex"01");
    }

    /// @notice When permissioned matching is disabled, anyone can settle
    function test_permissionlessMatching() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("a"), keccak256("an"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("b"), keccak256("bn"), PAIR_ETH_USDC, hex"01");

        // Disable permissioned matching
        engine.setPermissionedMatching(false);

        // Random address can now settle
        vm.prank(attacker);
        engine.settleMatch(keccak256("a"), keccak256("b"), 10e6, 2000e6, hex"01", hex"01");

        assertEq(engine.getSettlementCount(), 1);
    }

    // ========== SETTLEMENT EDGE CASES ==========

    /// @notice Settle with non-existent commitments fails
    function test_settleNonExistentCommitments() public {
        vm.prank(matcher);
        vm.expectRevert(DarkBookEngine.CommitmentNotActive.selector);
        engine.settleMatch(keccak256("fake_a"), keccak256("fake_b"), 10e6, 2000e6, hex"01", hex"01");
    }

    /// @notice Settlement records are correctly stored
    function test_settlementRecordIntegrity() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("a"), keccak256("an"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("b"), keccak256("bn"), PAIR_ETH_USDC, hex"01");

        vm.warp(1700000000); // set block timestamp

        vm.prank(matcher);
        engine.settleMatch(keccak256("a"), keccak256("b"), 42e6, 1999e6, hex"01", hex"01");

        (bytes32 cA, bytes32 cB, uint256 fill, uint256 price, uint256 ts) = engine.settlements(0);
        assertEq(cA, keccak256("a"));
        assertEq(cB, keccak256("b"));
        assertEq(fill, 42e6);
        assertEq(price, 1999e6);
        assertEq(ts, 1700000000);
    }

    // ========== GAS BENCHMARKS ==========

    /// @notice Benchmark gas cost for order submission
    function test_gasOrderSubmission() public {
        vm.prank(alice);
        uint256 gasBefore = gasleft();
        engine.submitOrder(keccak256("gas_order"), keccak256("gas_null"), PAIR_ETH_USDC, hex"01");
        uint256 gasUsed = gasBefore - gasleft();
        
        emit log_named_uint("Gas: submitOrder", gasUsed);
        // Should be well under 300k on EVM
        assertLt(gasUsed, 500_000, "submitOrder gas should be reasonable");
    }

    /// @notice Benchmark gas cost for settlement
    function test_gasSettlement() public {
        vm.prank(alice);
        engine.submitOrder(keccak256("ga"), keccak256("gan"), PAIR_ETH_USDC, hex"01");
        vm.prank(bob);
        engine.submitOrder(keccak256("gb"), keccak256("gbn"), PAIR_ETH_USDC, hex"01");

        vm.prank(matcher);
        uint256 gasBefore = gasleft();
        engine.settleMatch(keccak256("ga"), keccak256("gb"), 10e6, 2000e6, hex"01", hex"01");
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("Gas: settleMatch", gasUsed);
        assertLt(gasUsed, 500_000, "settleMatch gas should be reasonable");
    }
}
