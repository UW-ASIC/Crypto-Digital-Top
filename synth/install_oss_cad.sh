#!/usr/bin/env bash
# Downloads and extracts OSS CAD Suite (no sudo needed) into ~/oss-cad-suite
# Then runs synthesis on the crypto project.
# Run from within WSL: bash synth/install_oss_cad.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$HOME/oss-cad-suite"

# ---- 1. Download OSS CAD Suite if not present ----
if [[ ! -f "$INSTALL_DIR/bin/yosys" ]]; then
    echo "Downloading OSS CAD Suite (Linux x64)..."
    # Use a known recent release that has yosys + sky130 support
    RELEASE="2024-11-22"
    TARBALL="oss-cad-suite-linux-x64-${RELEASE//-/}.tgz"
    URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${RELEASE}/${TARBALL}"

    cd "$HOME"
    curl -fL --progress-bar "$URL" -o "$TARBALL"
    echo "Extracting..."
    tar xzf "$TARBALL"
    rm -f "$TARBALL"
    echo "Installed to $INSTALL_DIR"
else
    echo "OSS CAD Suite already at $INSTALL_DIR"
fi

export PATH="$INSTALL_DIR/bin:$PATH"
echo "Yosys: $(yosys --version)"

# ---- 2. Fetch liberty file ----
cd "$REPO_ROOT"
bash synth/get_liberty.sh

# ---- 3. Run synthesis ----
echo ""
echo "=============================="
echo " Running synthesis..."
echo "=============================="
yosys synth/synth.tcl 2>&1 | tee synth/synth_report.txt

echo ""
echo "=============================="
echo " Key statistics"
echo "=============================="
grep -E "(Flip-Flops|Number of cells|Chip area|chip area)" synth/synth_report.txt || true
