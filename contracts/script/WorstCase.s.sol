// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @title WorstCaseTest
/// @notice Tests attack vectors and failure modes on live Monad testnet
contract WorstCaseTest is Script {
    Vault constant vault = Vault(0xAe76085867146f76932A0711059450a01CE7e4A3);
    DarkBookEngine constant engine = DarkBookEngine(0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d);

    uint256 constant PAIR_ETH_USDC = 1;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== DarkBook WORST CASE SCENARIOS ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        uint256 passed = 0;
        uint256 total = 0;

        // ================================================
        // TEST 1: Double-submit with same nullifier
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 1: Double-submit same nullifier ---");
        bytes32 commit1 = keccak256(abi.encodePacked("worst_case_1", block.timestamp));
        bytes32 nullifier1 = keccak256(abi.encodePacked("worst_null_1", block.timestamp));
        engine.submitOrder(commit1, nullifier1, PAIR_ETH_USDC, hex"01");
        console.log("First submit: OK");

        // Try to reuse nullifier with different commitment
        bytes32 commit1b = keccak256(abi.encodePacked("worst_case_1b", block.timestamp));
        try engine.submitOrder(commit1b, nullifier1, PAIR_ETH_USDC, hex"01") {
            console.log("FAIL: Should have reverted on duplicate nullifier!");
        } catch {
            console.log("PASS: Duplicate nullifier correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 2: Double-submit with same commitment
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 2: Double-submit same commitment ---");
        bytes32 nullifier2 = keccak256(abi.encodePacked("worst_null_2", block.timestamp));
        try engine.submitOrder(commit1, nullifier2, PAIR_ETH_USDC, hex"01") {
            console.log("FAIL: Should have reverted on duplicate commitment!");
        } catch {
            console.log("PASS: Duplicate commitment correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 3: Invalid token pair (0)
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 3: Invalid token pair ID (0) ---");
        bytes32 commit3 = keccak256(abi.encodePacked("worst_case_3", block.timestamp));
        bytes32 nullifier3 = keccak256(abi.encodePacked("worst_null_3", block.timestamp));
        try engine.submitOrder(commit3, nullifier3, 0, hex"01") {
            console.log("FAIL: Should have reverted on invalid pair!");
        } catch {
            console.log("PASS: Invalid pair correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 4: Settle with non-existent commitments
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 4: Settle non-existent commitments ---");
        try engine.settleMatch(
            keccak256("fake_a"),
            keccak256("fake_b"),
            10e6,
            2000e6,
            hex"01",
            hex"01"
        ) {
            console.log("FAIL: Should have reverted on non-existent commitment!");
        } catch {
            console.log("PASS: Non-existent commitment correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 5: Cancel non-existent order
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 5: Cancel non-existent order ---");
        try engine.cancelOrder(keccak256("nonexistent_order"), hex"") {
            console.log("FAIL: Should have reverted!");
        } catch {
            console.log("PASS: Non-existent order cancel correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 6: Double cancel
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 6: Double cancel same order ---");
        // Cancel the order from Test 1
        engine.cancelOrder(commit1, hex"");
        console.log("First cancel: OK");

        try engine.cancelOrder(commit1, hex"") {
            console.log("FAIL: Should have reverted on double cancel!");
        } catch {
            console.log("PASS: Double cancel correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 7: Settle with cancelled order
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 7: Settle with cancelled order ---");
        bytes32 commit7 = keccak256(abi.encodePacked("worst_case_7", block.timestamp));
        bytes32 null7 = keccak256(abi.encodePacked("worst_null_7", block.timestamp));
        engine.submitOrder(commit7, null7, PAIR_ETH_USDC, hex"01");

        try engine.settleMatch(
            commit1,  // this was cancelled in Test 6
            commit7,
            10e6,
            2000e6,
            hex"01",
            hex"01"
        ) {
            console.log("FAIL: Should have reverted on cancelled commitment!");
        } catch {
            console.log("PASS: Cancelled commitment settlement correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 8: Settle already-filled orders
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 8: Settle already-filled orders ---");
        bytes32 commitA = keccak256(abi.encodePacked("worst_fill_a", block.timestamp));
        bytes32 nullA = keccak256(abi.encodePacked("worst_fnull_a", block.timestamp));
        bytes32 commitB = keccak256(abi.encodePacked("worst_fill_b", block.timestamp));
        bytes32 nullB = keccak256(abi.encodePacked("worst_fnull_b", block.timestamp));
        bytes32 commitC = keccak256(abi.encodePacked("worst_fill_c", block.timestamp));
        bytes32 nullC = keccak256(abi.encodePacked("worst_fnull_c", block.timestamp));

        engine.submitOrder(commitA, nullA, PAIR_ETH_USDC, hex"01");
        engine.submitOrder(commitB, nullB, PAIR_ETH_USDC, hex"01");
        engine.submitOrder(commitC, nullC, PAIR_ETH_USDC, hex"01");

        // Settle A <> B
        engine.settleMatch(commitA, commitB, 10e6, 2000e6, hex"01", hex"01");
        console.log("First settlement (A<>B): OK");

        // Try to settle A <> C (A is already filled)
        try engine.settleMatch(commitA, commitC, 5e6, 2000e6, hex"01", hex"01") {
            console.log("FAIL: Should have reverted on filled commitment!");
        } catch {
            console.log("PASS: Already-filled commitment settlement correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 9: Deposit zero amount
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 9: Deposit zero amount ---");
        // Pick the test token that was deployed earlier (doesn't matter which, just needs to be supported)
        // Use the testToken from the E2E test
        address testTokenAddr = 0x79553F542e70d2Ef0F992cb86287e02ECa15D71b;
        try vault.deposit(testTokenAddr, 0) {
            console.log("FAIL: Should have reverted on zero deposit!");
        } catch {
            console.log("PASS: Zero deposit correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 10: Set engine to zero address
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 10: Set engine to zero address ---");
        try vault.setDarkBookEngine(address(0)) {
            console.log("FAIL: Should have reverted!");
        } catch {
            console.log("PASS: Zero address engine correctly rejected");
            passed++;
        }

        // ================================================
        // TEST 11: Rapid-fire order submission (stress test)
        // ================================================
        total++;
        console.log("");
        console.log("--- Test 11: Rapid-fire 10 orders ---");
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < 10; i++) {
            bytes32 c = keccak256(abi.encodePacked("stress", i, block.timestamp));
            bytes32 n = keccak256(abi.encodePacked("stress_n", i, block.timestamp));
            engine.submitOrder(c, n, PAIR_ETH_USDC, hex"01");
        }
        uint256 gasUsed = gasBefore - gasleft();
        console.log("10 orders submitted successfully");
        console.log("Total gas for 10 orders:", gasUsed);
        console.log("Avg gas per order:", gasUsed / 10);
        passed++;

        vm.stopBroadcast();

        // ================================================
        // SUMMARY
        // ================================================
        console.log("");
        console.log("========================================");
        console.log("  WORST CASE TEST RESULTS");
        console.log("========================================");
        console.log("Passed:", passed);
        console.log("Total:", total);
        if (passed == total) {
            console.log("  ALL TESTS PASSED!");
        } else {
            console.log("  SOME TESTS FAILED!");
        }
        console.log("========================================");
    }
}
