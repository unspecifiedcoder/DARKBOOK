// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { UltraPlonkVerifier } from "../src/verifiers/UltraPlonkVerifier.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @title Deploy
/// @notice Deployment script for DarkBook contracts on Monad
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying DarkBook contracts...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the UltraPlonk verifier
        UltraPlonkVerifier verifier = new UltraPlonkVerifier();
        console.log("UltraPlonkVerifier deployed at:", address(verifier));

        // 2. Deploy the Vault
        Vault vault = new Vault(address(verifier));
        console.log("Vault deployed at:", address(vault));

        // 3. Deploy the DarkBook Engine
        DarkBookEngine engine = new DarkBookEngine(address(verifier), address(vault));
        console.log("DarkBookEngine deployed at:", address(engine));

        // 4. Configure: set DarkBook engine in vault
        vault.setDarkBookEngine(address(engine));
        console.log("Vault configured with DarkBookEngine");

        // 5. Authorize the deployer as a matcher (for testing)
        engine.authorizeMatcher(deployer);
        console.log("Deployer authorized as matcher");

        vm.stopBroadcast();

        // Log summary
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Verifier:    ", address(verifier));
        console.log("Vault:       ", address(vault));
        console.log("Engine:      ", address(engine));
        console.log("========================");
    }
}
