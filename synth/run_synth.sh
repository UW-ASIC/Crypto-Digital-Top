#!/usr/bin/env bash
# Full setup + synthesis script — run from repo root inside WSL Ubuntu
# Usage: bash synth/run_synth.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# 1. Install yosys if needed
if ! command -v yosys &>/dev/null; then
    echo "Installing yosys..."
    sudo apt-get update -qq
    sudo apt-get install -y yosys
fi

echo "Yosys: $(yosys --version)"

# 2. Fetch liberty file if not present
bash synth/get_liberty.sh

# 3. Run synthesis
echo ""
echo "=============================="
echo " Running synthesis..."
echo "=============================="
yosys synth/synth.tcl 2>&1 | tee synth/synth_report.txt

echo ""
echo "=============================="
echo " Done. Full log: synth/synth_report.txt"
echo "=============================="

# 4. Pull out the key numbers
echo ""
echo "=== Key statistics ==="
grep -E "(Flip-Flops|Number of cells|sky130|chip area)" synth/synth_report.txt || true
grep -A2 "=== design hierarchy ===" synth/synth_report.txt | tail -5 || true
