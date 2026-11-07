#!/usr/bin/env bash
# Build script for jms578flash with PUYA SPI Flash support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/jms578flash-src"
PATCH_FILE="$SCRIPT_DIR/puya_flash_support.patch"
OUTPUT_BINARY="$SCRIPT_DIR/jms578flash_x86_64"

echo "==> [1/3] Checking submodule source..."
if [ ! -f "$SRC_DIR/main.go" ]; then
    echo "Submodule not initialized. Initializing..."
    git -C "$SCRIPT_DIR/.." submodule update --init --recursive
fi

echo "==> [2/3] Applying PUYA flash support patch if not already applied..."
if ! grep -q "0x85441285" "$SRC_DIR/spiflash/types.go"; then
    echo "Applying $PATCH_FILE..."
    git -C "$SRC_DIR" apply "$PATCH_FILE"
    echo "Patch applied successfully."
else
    echo "Patch already present in source."
fi

echo "==> [3/3] Compiling jms578flash binary..."
if command -v podman >/dev/null 2>&1; then
    echo "Using Podman container with golang:alpine..."
    podman run --rm -v "$SRC_DIR":/app:Z -w /app golang:alpine \
        go build -ldflags="-s -w" -o /app/jms578flash_x86_64 .
    mv "$SRC_DIR/jms578flash_x86_64" "$OUTPUT_BINARY"
elif command -v docker >/dev/null 2>&1; then
    echo "Using Docker container with golang:alpine..."
    docker run --rm -v "$SRC_DIR":/app -w /app golang:alpine \
        go build -ldflags="-s -w" -o /app/jms578flash_x86_64 .
    mv "$SRC_DIR/jms578flash_x86_64" "$OUTPUT_BINARY"
elif command -v go >/dev/null 2>&1; then
    echo "Using native Go compiler..."
    cd "$SRC_DIR"
    go build -ldflags="-s -w" -o "$OUTPUT_BINARY" .
else
    echo "ERROR: Neither podman, docker, nor go is installed on your system."
    exit 1
fi

chmod +x "$OUTPUT_BINARY"
echo "==> SUCCESS: Compiled binary is ready at: $OUTPUT_BINARY"
"$OUTPUT_BINARY" -h 2>&1 | head -n 4 || true
