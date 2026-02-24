#!/bin/bash
# Builds the python_bin PyInstaller executable for bundling into the app.
# Usage: ./build_binary.sh [--light]
#   --light: skip torch/EDGE deps (template-only choreo, much smaller binary)
# Output: MacDance/Resources/python_bin

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../MacDance/Resources"
LIGHT_MODE=false

for arg in "$@"; do
    case $arg in
        --light) LIGHT_MODE=true ;;
    esac
done

cd "$SCRIPT_DIR"

if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi

source .venv/bin/activate

if [ "$LIGHT_MODE" = true ]; then
    echo "Building in LIGHT mode (template choreo only, no EDGE/torch)"
    pip install -r requirements.txt --quiet
else
    echo "Building in FULL mode (includes EDGE/torch)"
    pip install -r requirements-edge.txt --quiet
fi

pyinstaller \
    --onefile \
    --name python_bin \
    --distpath "$OUTPUT_DIR" \
    --workpath /tmp/pyinstaller_work \
    --specpath /tmp/pyinstaller_specs \
    --clean \
    generate_choreo.py

deactivate

echo ""
echo "Built: $OUTPUT_DIR/python_bin"
echo "Testing binary..."
"$OUTPUT_DIR/python_bin" --help && echo "Binary runs OK" || echo "WARNING: Binary failed to run"
