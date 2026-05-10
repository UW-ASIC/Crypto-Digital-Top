#!/usr/bin/env bash
# Downloads the sky130_fd_sc_hd typical corner liberty file used by TinyTapeout
# Run from repo root: bash synth/get_liberty.sh

set -euo pipefail

DEST="synth/sky130_fd_sc_hd__tt_025C_1v80.lib"

if [[ -f "$DEST" ]]; then
    echo "Liberty file already present at $DEST"
    exit 0
fi

URL="https://raw.githubusercontent.com/efabless/skywater-pdk-libs-sky130_fd_sc_hd/main/timing/sky130_fd_sc_hd__tt_025C_1v80.lib"

echo "Downloading sky130_fd_sc_hd liberty file..."
if command -v curl &>/dev/null; then
    curl -fsSL "$URL" -o "$DEST"
elif command -v wget &>/dev/null; then
    wget -q "$URL" -O "$DEST"
else
    echo "ERROR: neither curl nor wget found. Install one and retry."
    exit 1
fi

echo "Saved to $DEST"
