// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { OrderCommitmentVerifier } from "../src/verifiers/OrderCommitmentVerifier.sol";
import { MatchProofVerifier } from "../src/verifiers/MatchProofVerifier.sol";
import { BalanceUpdateVerifier } from "../src/verifiers/BalanceUpdateVerifier.sol";
import { Vault } from "../src/Vault.sol";
import { DarkBookEngine } from "../src/DarkBookEngine.sol";

/// @notice Two things in one file:
///   1. BalanceUpdateVerifier accepts a real UltraHonk proof for the
///      `darkbook_balance_update` circuit (direct-verify + mutations).
///   2. The full `DarkBookEngine.settleMatch` path -- match proof AND
///      balance proof together -- succeeds end-to-end on-chain.
///
/// The balance_update fixture is coherent with the match_proof fixture:
/// both bind the same fill_receipt (same commitments, fill, price, nonce),
/// which is exactly what settleMatch requires.
contract BalanceUpdateFixtureTest is Test {
    // --- engine storage slots (immutables are in bytecode, not storage) ---
    //   owner                 slot 0
    //   epochCounter           slot 1
    //   permissionedMatching   slot 2
    //   commitments mapping    slot 3
    //   nullifiers mapping     slot 4
    //   activeCommitmentCount  slot 5
    uint256 constant COMMITMENTS_SLOT = 3;
    uint256 constant ACTIVE_COUNT_SLOT = 5;
    // --- Vault: balanceTree.root is slot 21 (see OrderCommitmentProof.t.sol) ---
    uint256 constant VAULT_ROOT_SLOT = 21;

    // Fixture public inputs for balance_update (5).
    bytes32 constant FIX_OLD_ROOT = 0x1b053cb9bb022cd92962cae97a6d5024a85c57f605d42654b3cc32b1c6b7b3d4;
    bytes32 constant FIX_MID_ROOT = 0x00e411346b24e0c2e6133750b12225b03cb4ae473b5dd697418a4a0373412eca;
    bytes32 constant FIX_NEW_ROOT = 0x2845b0eb1d49aefe2dfb9202cb0dbb013bbaf3f095dab9e50cf6fd4ae4bcef2d;
    bytes32 constant FIX_FILL_RECEIPT = 0x275199da460ce433549a6fbe4029dec282c10d69c6664cf681280f421556a621;
    uint256 constant FIX_SETTLEMENT_PRICE = 100;

    // Match-fixture commitments (the two orders being settled).
    bytes32 constant FIX_COMMITMENT_A = 0x153657ffb2ddce11ef88f4d7500e6961bdb6afe935b54062fb94175cfa82dc73;
    bytes32 constant FIX_COMMITMENT_B = 0x204aa3af7ab7b8d868f8db24bb0454458a5197f6036e6c0dac03ec36f0fcd5f2;
    uint256 constant FIX_MARKET_ID = 1;

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
        // The test contract deployed the engine, so it is the owner and
        // can authorise itself as a matcher for settleMatch.
        engine.authorizeMatcher(address(this));
    }

    function _balancePublicInputs() internal pure returns (bytes32[] memory) {
        bytes32[] memory pubs = new bytes32[](5);
        pubs[0] = FIX_OLD_ROOT;
        pubs[1] = FIX_MID_ROOT;
        pubs[2] = FIX_NEW_ROOT;
        pubs[3] = FIX_FILL_RECEIPT;
        pubs[4] = bytes32(FIX_SETTLEMENT_PRICE);
        return pubs;
    }

    // ---- 1. Direct verify of the balance_update proof ----

    function test_verify_accepts_real_balance_proof() public view {
        bytes memory proof = vm.readFileBinary("test/fixtures/balance_update/proof");
        assertEq(proof.length, 9536, "fixture proof unexpected size");
        assertTrue(balanceVerifier.verify(proof, _balancePublicInputs()), "real balance proof rejected");
    }

    function test_verify_rejects_tampered_balance_proof() public {
        bytes memory proof = vm.readFileBinary("test/fixtures/balance_update/proof");
        proof[4500] = proof[4500] ^ 0x01;
        bool ok;
        try balanceVerifier.verify(proof, _balancePublicInputs()) returns (bool r) { ok = r; }
        catch { ok = false; }
        assertFalse(ok, "tampered balance proof accepted");
    }

    function test_verify_rejects_wrong_new_root() public {
        bytes memory proof = vm.readFileBinary("test/fixtures/balance_update/proof");
        bytes32[] memory pubs = _balancePublicInputs();
        pubs[2] = bytes32(uint256(0xdead)); // mutate new_root
        bool ok;
        try balanceVerifier.verify(proof, pubs) returns (bool r) { ok = r; } catch { ok = false; }
        assertFalse(ok, "balance proof accepted under wrong new_root");
    }

    // ---- 2. Full on-chain settleMatch with all three real proofs ----

    /// Seeds an order into the engine's `commitments` mapping as Active so
    /// settleMatch's status check passes, without needing a separate
    /// order_commitment proof per order. (Engine state setup only; the
    /// proofs being verified are real.)
    function _seedActiveOrder(bytes32 commitment) internal {
        bytes32 base = keccak256(abi.encode(commitment, COMMITMENTS_SLOT));
        // struct OrderCommitment field offsets:
        //   +0 commitment  +1 owner  +2 ownerId  +3 marketId
        //   +4 expiryBlock +5 epoch  +6 timestamp +7 status +8 remainingAmount
        vm.store(address(engine), base, commitment);
        vm.store(address(engine), bytes32(uint256(base) + 3), bytes32(FIX_MARKET_ID));
        vm.store(address(engine), bytes32(uint256(base) + 4), bytes32(uint256(100_000))); // expiryBlock
        vm.store(address(engine), bytes32(uint256(base) + 7), bytes32(uint256(1)));       // status = Active
    }

    function test_settleMatch_full_flow_with_real_proofs() public {
        // Seed both orders as Active.
        _seedActiveOrder(FIX_COMMITMENT_A);
        _seedActiveOrder(FIX_COMMITMENT_B);

        // activeCommitmentCount[marketId] must be >= 2 (settleMatch does -= 2).
        bytes32 countSlot = keccak256(abi.encode(FIX_MARKET_ID, ACTIVE_COUNT_SLOT));
        vm.store(address(engine), countSlot, bytes32(uint256(2)));

        // Vault root must equal the balance proof's old_root.
        vm.store(address(vault), bytes32(VAULT_ROOT_SLOT), FIX_OLD_ROOT);

        bytes memory matchProof = vm.readFileBinary("test/fixtures/match_proof/proof");
        bytes memory balanceProof = vm.readFileBinary("test/fixtures/balance_update/proof");

        engine.settleMatch(
            FIX_COMMITMENT_A,
            FIX_COMMITMENT_B,
            FIX_FILL_RECEIPT,
            FIX_SETTLEMENT_PRICE,
            FIX_MID_ROOT,
            FIX_NEW_ROOT,
            matchProof,
            balanceProof
        );

        // Both orders are now Filled, the vault advanced to new_root, and
        // the fill receipt is spent.
        DarkBookEngine.OrderCommitment memory a = engine.getOrder(FIX_COMMITMENT_A);
        DarkBookEngine.OrderCommitment memory b = engine.getOrder(FIX_COMMITMENT_B);
        assertTrue(a.status == DarkBookEngine.OrderStatus.Filled, "order A not filled");
        assertTrue(b.status == DarkBookEngine.OrderStatus.Filled, "order B not filled");
        assertEq(vault.getBalanceRoot(), FIX_NEW_ROOT, "vault root not advanced");
        assertTrue(engine.spentFillReceipts(FIX_FILL_RECEIPT), "fill receipt not spent");
        assertEq(engine.getSettlementCount(), 1, "settlement not recorded");
    }

    function test_settleMatch_rejects_double_settlement() public {
        _seedActiveOrder(FIX_COMMITMENT_A);
        _seedActiveOrder(FIX_COMMITMENT_B);
        bytes32 countSlot = keccak256(abi.encode(FIX_MARKET_ID, ACTIVE_COUNT_SLOT));
        vm.store(address(engine), countSlot, bytes32(uint256(2)));
        vm.store(address(vault), bytes32(VAULT_ROOT_SLOT), FIX_OLD_ROOT);

        bytes memory matchProof = vm.readFileBinary("test/fixtures/match_proof/proof");
        bytes memory balanceProof = vm.readFileBinary("test/fixtures/balance_update/proof");

        engine.settleMatch(
            FIX_COMMITMENT_A, FIX_COMMITMENT_B, FIX_FILL_RECEIPT,
            FIX_SETTLEMENT_PRICE, FIX_MID_ROOT, FIX_NEW_ROOT, matchProof, balanceProof
        );

        // Re-seeding the orders as Active and replaying the exact same
        // proofs must fail: the fill receipt is already spent.
        _seedActiveOrder(FIX_COMMITMENT_A);
        _seedActiveOrder(FIX_COMMITMENT_B);
        vm.store(address(engine), countSlot, bytes32(uint256(2)));
        vm.store(address(vault), bytes32(VAULT_ROOT_SLOT), FIX_OLD_ROOT);

        vm.expectRevert(DarkBookEngine.FillReceiptAlreadySpent.selector);
        engine.settleMatch(
            FIX_COMMITMENT_A, FIX_COMMITMENT_B, FIX_FILL_RECEIPT,
            FIX_SETTLEMENT_PRICE, FIX_MID_ROOT, FIX_NEW_ROOT, matchProof, balanceProof
        );
    }
}
