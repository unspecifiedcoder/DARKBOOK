#!/usr/bin/env bash
# Regenerate the three on-chain Solidity verifiers from the current Noir
# circuits. Run from the repo root or anywhere under it.
#
# Flow per circuit:
#   1. nargo compile (writes circuits/target/<pkg>.json)
#   2. bb write_vk     -b <pkg>.json -o <vk_dir>/      -t evm
#   3. bb write_solidity_verifier -k <vk_dir>/vk -o <Verifier.sol> -t evm
#
# Outputs land in contracts/src/verifiers/. The intermediate vk binaries
# stay in circuits/target/vk/<pkg>/ so they can be committed for proof
# generation (matcher + frontend need the same vk).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CIRCUITS_DIR="$REPO_ROOT/circuits"
VERIFIERS_DIR="$REPO_ROOT/contracts/src/verifiers"
VK_DIR="$CIRCUITS_DIR/target/vk"

# (Noir package name, output Solidity contract filename)
CIRCUITS=(
    "darkbook_order_commitment OrderCommitmentVerifier.sol"
    "darkbook_match_proof      MatchProofVerifier.sol"
    "darkbook_balance_update   BalanceUpdateVerifier.sol"
)

echo "==> compiling circuits"
( cd "$CIRCUITS_DIR" && nargo compile --workspace )

mkdir -p "$VK_DIR" "$VERIFIERS_DIR"

for entry in "${CIRCUITS[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    pkg="$1"
    sol="$2"
    acir="$CIRCUITS_DIR/target/${pkg}.json"
    vk_subdir="$VK_DIR/$pkg"
    mkdir -p "$vk_subdir"

    echo
    echo "==> $pkg"
    echo "    vk         -> $vk_subdir/vk"
    echo "    verifier   -> $VERIFIERS_DIR/$sol"

    bb write_vk \
        -b "$acir" \
        -o "$vk_subdir" \
        -t evm \
        > "$vk_subdir/write_vk.log" 2>&1

    bb write_solidity_verifier \
        -k "$vk_subdir/vk" \
        -o "$VERIFIERS_DIR/$sol" \
        -t evm \
        > "$vk_subdir/write_verifier.log" 2>&1

    # bb emits the contract as `HonkVerifier`; rename it per circuit so the
    # three verifiers can coexist in the same Foundry project without name
    # collisions. Also rename the library so it's unique.
    contract_name="${sol%.sol}"
    library_name="${contract_name%Verifier}HonkVerificationKey"
    sed -i \
        -e "s/contract HonkVerifier /contract ${contract_name} /" \
        -e "s/library HonkVerificationKey /library ${library_name} /" \
        -e "s/HonkVerificationKey\\./${library_name}./g" \
        "$VERIFIERS_DIR/$sol"

    lines=$(wc -l < "$VERIFIERS_DIR/$sol")
    pub_inputs=$(grep -E "NUMBER_OF_PUBLIC_INPUTS = " "$VERIFIERS_DIR/$sol" | head -1 | sed 's/.*= //; s/;//')
    echo "    lines=$lines  public_inputs_size=$pub_inputs"
done

echo
echo "==> done. Three verifiers regenerated:"
ls -la "$VERIFIERS_DIR/"
