#!/usr/bin/env bash
# Regenerate the Foundry proof fixtures from the current circuits.
#
# For each fixture we:
#   1. Build the canonical witness (Prover.toml lives in the package dir).
#   2. nargo execute -> witness.gz
#   3. bb prove -b acir -w witness -k vk -o <fixtures>/<name>/  -t evm
# Each fixture lands in `contracts/test/fixtures/<name>/` as a pair of
# binaries:
#      proof          -- the UltraHonk proof bytes
#      public_inputs  -- the 32-byte-per-element public inputs vector
# The Foundry tests read these via vm.readFileBinary.
#
# Run codegen-verifiers.sh first if circuits have changed -- this script
# assumes the vks under circuits/target/vk/ are already current.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CIRCUITS_DIR="$REPO_ROOT/circuits"
FIXTURES_DIR="$REPO_ROOT/contracts/test/fixtures"
VK_DIR="$CIRCUITS_DIR/target/vk"

cd "$CIRCUITS_DIR"

if [ ! -d "$VK_DIR" ]; then
    echo "vk directory not found; run codegen-verifiers.sh first" >&2
    exit 1
fi

# (Nargo package, fixture sub-directory)
FIXTURES=(
    "darkbook_order_commitment order_commitment"
)

mkdir -p "$FIXTURES_DIR"

for entry in "${FIXTURES[@]}"; do
    # shellcheck disable=SC2086
    set -- $entry
    pkg="$1"
    name="$2"
    out="$FIXTURES_DIR/$name"
    mkdir -p "$out"

    echo "==> $pkg -> contracts/test/fixtures/$name/"

    nargo execute --package "$pkg" > /dev/null

    bb prove \
        -b "$CIRCUITS_DIR/target/${pkg}.json" \
        -w "$CIRCUITS_DIR/target/${pkg}.gz" \
        -k "$VK_DIR/${pkg}/vk" \
        -o "$out" \
        -t evm \
        > "$out/prove.log" 2>&1

    proof_bytes=$(stat -c%s "$out/proof")
    pubs_bytes=$(stat -c%s "$out/public_inputs")
    echo "    proof          = $proof_bytes bytes"
    echo "    public_inputs  = $pubs_bytes bytes ($((pubs_bytes / 32)) fields)"

    bb verify \
        -k "$VK_DIR/${pkg}/vk" \
        -p "$out/proof" \
        -i "$out/public_inputs" \
        -t evm \
        > "$out/verify.log" 2>&1 \
        && echo "    native verify  = ok"
done

echo "==> all fixtures ready under $FIXTURES_DIR"
