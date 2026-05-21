// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { OrderCommitmentVerifier } from "../src/verifiers/OrderCommitmentVerifier.sol";
import { MatchProofVerifier } from "../src/verifiers/MatchProofVerifier.sol";
import { BalanceUpdateVerifier } from "../src/verifiers/BalanceUpdateVerifier.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @notice Minimal compile-and-deploy test that proves the new wiring is
///         self-consistent: three real verifiers + vault + engine all
///         construct against each other. The full unit + E2E suite returns
///         in the next commit (A5) once real proof fixtures are generated.
contract CompileTest is Test {
    OrderCommitmentVerifier orderVerifier;
    MatchProofVerifier matchVerifier;
    BalanceUpdateVerifier balanceVerifier;
    Vault vault;
    DarkBookEngine engine;

    function setUp() public {
        orderVerifier = new OrderCommitmentVerifier();
        matchVerifier = new MatchProofVerifier();
        balanceVerifier = new BalanceUpdateVerifier();
        vault = new Vault();
        engine = new DarkBookEngine(
            address(orderVerifier),
            address(matchVerifier),
            address(balanceVerifier),
            address(vault)
        );
        vault.setDarkBookEngine(address(engine));
    }

    function test_deployed_addresses_distinct() public view {
        assertTrue(address(orderVerifier) != address(matchVerifier));
        assertTrue(address(matchVerifier) != address(balanceVerifier));
        assertTrue(address(orderVerifier) != address(balanceVerifier));
        assertTrue(address(engine) != address(vault));
    }

    function test_engine_wired_to_three_verifiers() public view {
        assertEq(address(engine.orderVerifier()), address(orderVerifier));
        assertEq(address(engine.matchVerifier()), address(matchVerifier));
        assertEq(address(engine.balanceVerifier()), address(balanceVerifier));
        assertEq(address(engine.vault()), address(vault));
    }

    function test_vault_engine_authority() public view {
        assertEq(vault.darkBookEngine(), address(engine));
    }

    function test_initial_state() public {
        assertEq(engine.epochCounter(), 1);
        assertTrue(engine.permissionedMatching());
        // The empty balance tree has a non-zero root (recursive hash of
        // empty subtrees), so we just assert it's deterministic across
        // a freshly-deployed pair.
        Vault v2 = new Vault();
        assertEq(vault.getBalanceRoot(), v2.getBalanceRoot());
    }

    /// @notice The stub verifier used to return `true` for any bytes. The
    ///         real one rejects garbage. We can't fully test this without
    ///         a valid proof (that's A5), but we can confirm `verify` is
    ///         reachable and reverts/returns false on garbage rather than
    ///         silently succeeding.
    function test_real_verifier_rejects_garbage() public {
        bytes memory garbage = new bytes(1024);
        bytes32[] memory pubs = new bytes32[](7);
        // The honk verifier reverts on malformed proof bytes rather than
        // returning false. Either outcome is acceptable here -- the point
        // is that it does NOT return true.
        bool succeeded;
        try orderVerifier.verify(garbage, pubs) returns (bool ok) {
            succeeded = ok;
        } catch {
            succeeded = false;
        }
        assertFalse(succeeded, "real verifier should not accept garbage");
    }
}
