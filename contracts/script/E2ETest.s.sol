// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @title TestToken — Simple ERC20 for E2E testing on testnet
contract TestToken {
    string public name = "DarkBook Test USDC";
    string public symbol = "dUSDC";
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

/// @title E2ETest
/// @notice Full end-to-end test on live Monad testnet
contract E2ETest is Script {
    // Deployed contract addresses
    Vault constant vault = Vault(0xAe76085867146f76932A0711059450a01CE7e4A3);
    DarkBookEngine constant engine = DarkBookEngine(0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d);

    uint256 constant PAIR_ETH_USDC = 1;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("=== DarkBook E2E Test on Monad Testnet ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // ================================================
        // STEP 1: Deploy test token and configure vault
        // ================================================
        console.log("");
        console.log("--- Step 1: Deploy Test Token ---");
        TestToken testToken = new TestToken();
        console.log("Test token deployed:", address(testToken));

        vault.addSupportedToken(address(testToken));
        console.log("Token added to vault whitelist");

        // Mint tokens to deployer
        testToken.mint(deployer, 100_000e6);
        console.log("Minted 100,000 dUSDC to deployer");

        // ================================================
        // STEP 2: Deposit into vault
        // ================================================
        console.log("");
        console.log("--- Step 2: Deposit into Vault ---");
        testToken.approve(address(vault), type(uint256).max);
        vault.deposit(address(testToken), 50_000e6);
        console.log("Deposited 50,000 dUSDC into vault");

        bytes32 rootAfterDeposit = vault.getBalanceRoot();
        console.log("Balance root after deposit:");
        console.logBytes32(rootAfterDeposit);

        // ================================================
        // STEP 3: Submit buy order (commitment)
        // ================================================
        console.log("");
        console.log("--- Step 3: Submit BUY Order ---");
        bytes32 buyCommitment = keccak256(abi.encodePacked("e2e_buy_100_at_2000", block.timestamp));
        bytes32 buyNullifier = keccak256(abi.encodePacked("e2e_buy_null", block.timestamp));
        engine.submitOrder(buyCommitment, buyNullifier, PAIR_ETH_USDC, hex"01");
        console.log("Buy order committed:");
        console.logBytes32(buyCommitment);

        // ================================================
        // STEP 4: Submit sell order (commitment)
        // ================================================
        console.log("");
        console.log("--- Step 4: Submit SELL Order ---");
        bytes32 sellCommitment = keccak256(abi.encodePacked("e2e_sell_100_at_1990", block.timestamp));
        bytes32 sellNullifier = keccak256(abi.encodePacked("e2e_sell_null", block.timestamp));
        engine.submitOrder(sellCommitment, sellNullifier, PAIR_ETH_USDC, hex"01");
        console.log("Sell order committed:");
        console.logBytes32(sellCommitment);

        uint256 activeCount = engine.getActiveCommitmentCount(PAIR_ETH_USDC);
        console.log("Active commitments:", activeCount);

        // ================================================
        // STEP 5: Settle match
        // ================================================
        console.log("");
        console.log("--- Step 5: Settle Match ---");
        uint256 fillAmount = 100e6;
        uint256 settlementPrice = 1995e6;

        engine.settleMatch(
            buyCommitment,
            sellCommitment,
            fillAmount,
            settlementPrice,
            hex"01",
            hex"01"
        );
        console.log("Match settled!");
        console.log("Fill amount: 100 dUSDC");
        console.log("Settlement price: 1995");

        // ================================================
        // STEP 6: Verify final state
        // ================================================
        console.log("");
        console.log("--- Step 6: Verify Final State ---");

        uint256 settlements = engine.getSettlementCount();
        console.log("Total settlements:", settlements);

        uint256 activeAfter = engine.getActiveCommitmentCount(PAIR_ETH_USDC);
        console.log("Active commitments after settle:", activeAfter);

        bytes32 finalRoot = vault.getBalanceRoot();
        console.log("Final balance root:");
        console.logBytes32(finalRoot);

        // ================================================
        // STEP 7: Test cancellation flow
        // ================================================
        console.log("");
        console.log("--- Step 7: Cancel Order Flow ---");
        bytes32 cancelCommitment = keccak256(abi.encodePacked("e2e_cancel_order", block.timestamp));
        bytes32 cancelNullifier = keccak256(abi.encodePacked("e2e_cancel_null", block.timestamp));
        engine.submitOrder(cancelCommitment, cancelNullifier, PAIR_ETH_USDC, hex"01");
        console.log("Order submitted for cancellation test");

        engine.cancelOrder(cancelCommitment, hex"");
        console.log("Order cancelled successfully");

        uint256 activeAfterCancel = engine.getActiveCommitmentCount(PAIR_ETH_USDC);
        console.log("Active commitments after cancel:", activeAfterCancel);

        vm.stopBroadcast();

        // ================================================
        // SUMMARY
        // ================================================
        console.log("");
        console.log("========================================");
        console.log("  E2E TEST COMPLETE - ALL STEPS PASSED  ");
        console.log("========================================");
        console.log("Verifier:   0x94De85a9737dba2f2C470Be46D0F77D3E9f3eb40");
        console.log("Vault:      0xAe76085867146f76932A0711059450a01CE7e4A3");
        console.log("Engine:     0x25Fef829200F56Ee1EAE448250dbC5Ee1d6cdf2d");
        console.log("TestToken: ", address(testToken));
        console.log("========================================");
    }
}
