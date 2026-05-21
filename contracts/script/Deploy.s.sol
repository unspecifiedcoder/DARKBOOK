// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { OrderCommitmentVerifier } from "../src/verifiers/OrderCommitmentVerifier.sol";
import { MatchProofVerifier } from "../src/verifiers/MatchProofVerifier.sol";
import { BalanceUpdateVerifier } from "../src/verifiers/BalanceUpdateVerifier.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @title Deploy
/// @notice Deploys the three UltraHonk verifiers, the vault, and the engine
///         on whichever chain the broadcast targets.
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying DarkBook contracts...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        OrderCommitmentVerifier orderVerifier = new OrderCommitmentVerifier();
        console.log("OrderCommitmentVerifier deployed at:", address(orderVerifier));

        MatchProofVerifier matchVerifier = new MatchProofVerifier();
        console.log("MatchProofVerifier deployed at:    ", address(matchVerifier));

        BalanceUpdateVerifier balanceVerifier = new BalanceUpdateVerifier();
        console.log("BalanceUpdateVerifier deployed at: ", address(balanceVerifier));

        Vault vault = new Vault();
        console.log("Vault deployed at:                 ", address(vault));

        DarkBookEngine engine = new DarkBookEngine(
            address(orderVerifier),
            address(matchVerifier),
            address(balanceVerifier),
            address(vault)
        );
        console.log("DarkBookEngine deployed at:        ", address(engine));

        vault.setDarkBookEngine(address(engine));
        console.log("Vault wired to engine");

        engine.authorizeMatcher(deployer);
        console.log("Deployer authorized as matcher");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("OrderCommitmentVerifier: ", address(orderVerifier));
        console.log("MatchProofVerifier:      ", address(matchVerifier));
        console.log("BalanceUpdateVerifier:   ", address(balanceVerifier));
        console.log("Vault:                   ", address(vault));
        console.log("Engine:                  ", address(engine));
        console.log("==========================");
    }
}
