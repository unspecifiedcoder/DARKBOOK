// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { MatchProofVerifier } from "../src/verifiers/MatchProofVerifier.sol";

/// @notice Exercises `MatchProofVerifier.verify` against a real UltraHonk
///         proof produced from `darkbook_match_proof`. The fixture witness
///         encodes a valid cross: buyer at 110, seller at 90, fill 30 @ 100.
///
///         Restoring the full settleMatch flow (which also calls the
///         balance_update verifier) needs a balance_update fixture; that
///         lands in a follow-up commit. Verifying the match proof in
///         isolation here proves the verifier integration is sound.
contract MatchProofFixtureTest is Test {
    bytes32 constant FIX_COMMITMENT_A    = 0x153657ffb2ddce11ef88f4d7500e6961bdb6afe935b54062fb94175cfa82dc73;
    bytes32 constant FIX_COMMITMENT_B    = 0x204aa3af7ab7b8d868f8db24bb0454458a5197f6036e6c0dac03ec36f0fcd5f2;
    bytes32 constant FIX_FILL_RECEIPT    = 0x275199da460ce433549a6fbe4029dec282c10d69c6664cf681280f421556a621;
    uint256 constant FIX_SETTLEMENT_PRICE = 100;
    uint256 constant FIX_MARKET_ID        = 1;
    // chain_id is 31337 (Foundry default), matching the fixture.

    MatchProofVerifier verifier;

    function setUp() public {
        verifier = new MatchProofVerifier();
    }

    function _publicInputs() internal view returns (bytes32[] memory) {
        bytes32[] memory pubs = new bytes32[](6);
        pubs[0] = FIX_COMMITMENT_A;
        pubs[1] = FIX_COMMITMENT_B;
        pubs[2] = FIX_FILL_RECEIPT;
        pubs[3] = bytes32(FIX_SETTLEMENT_PRICE);
        pubs[4] = bytes32(FIX_MARKET_ID);
        pubs[5] = bytes32(block.chainid);
        return pubs;
    }

    function test_verify_accepts_real_proof() public view {
        bytes memory proof = vm.readFileBinary("test/fixtures/match_proof/proof");
        assertEq(proof.length, 8000, "fixture proof unexpected size");
        bytes32[] memory pubs = _publicInputs();
        assertTrue(verifier.verify(proof, pubs), "real match proof rejected");
    }

    function test_verify_rejects_tampered_proof() public {
        bytes memory proof = vm.readFileBinary("test/fixtures/match_proof/proof");
        proof[4000] = proof[4000] ^ 0x01;
        bytes32[] memory pubs = _publicInputs();
        bool ok;
        try verifier.verify(proof, pubs) returns (bool r) { ok = r; } catch { ok = false; }
        assertFalse(ok, "tampered match proof was accepted");
    }

    function test_verify_rejects_wrong_settlement_price() public {
        bytes memory proof = vm.readFileBinary("test/fixtures/match_proof/proof");
        bytes32[] memory pubs = _publicInputs();
        pubs[3] = bytes32(uint256(101)); // mutate settlement_price
        bool ok;
        try verifier.verify(proof, pubs) returns (bool r) { ok = r; } catch { ok = false; }
        assertFalse(ok, "match proof accepted under wrong settlement price");
    }

    function test_verify_rejects_swapped_commitments() public {
        bytes memory proof = vm.readFileBinary("test/fixtures/match_proof/proof");
        bytes32[] memory pubs = _publicInputs();
        (pubs[0], pubs[1]) = (pubs[1], pubs[0]); // swap A and B
        bool ok;
        try verifier.verify(proof, pubs) returns (bool r) { ok = r; } catch { ok = false; }
        assertFalse(ok, "match proof accepted under swapped commitments");
    }
}
