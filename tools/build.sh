#!/usr/bin/env bash
# ==============================================================================
# Build Script for jms578flash with PUYA Flash IC Support
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBMODULE_DIR="${SCRIPT_DIR}/jms578flash"
PATCH_FILE="${SCRIPT_DIR}/puya_flash_support.patch"
OUTPUT_BINARY="${SCRIPT_DIR}/jms578flash_x86_64"

echo "==> [1/4] Checking jms578flash submodule..."
if [[ ! -f "${SUBMODULE_DIR}/main.go" ]]; then
    echo "    Submodule not initialized. Initializing..."
    git -C "${REPO_ROOT}" submodule update --init --recursive tools/jms578flash
fi

echo "==> [2/4] Applying PUYA flash IC patch..."
# Check if patch is already applied
if git -C "${SUBMODULE_DIR}" apply --check "${PATCH_FILE}" >/dev/null 2>&1; then
    echo "    Applying ${PATCH_FILE}..."
    git -C "${SUBMODULE_DIR}" apply "${PATCH_FILE}"
elif grep -q "0x85441285" "${SUBMODULE_DIR}/spiflash/types.go"; then
    echo "    Patch already applied in ${SUBMODULE_DIR}/spiflash/types.go."
else
    echo "    Warning: Could not apply patch automatically. Checking types.go manually..."
fi

echo "==> [3/4] Compiling static x86_64 binary..."
if command -v podman >/dev/null 2>&1; then
    echo "    Using Podman (golang:alpine container)..."
    podman run --rm -v "${SUBMODULE_DIR}":/src:Z -w /src golang:alpine \
        go build -ldflags="-s -w" -o /src/jms578flash_x86_64 .
    mv "${SUBMODULE_DIR}/jms578flash_x86_64" "${OUTPUT_BINARY}"
elif command -v docker >/dev/null 2>&1; then
    echo "    Using Docker (golang:alpine container)..."
    docker run --rm -v "${SUBMODULE_DIR}":/src -w /src golang:alpine \
        go build -ldflags="-s -w" -o /src/jms578flash_x86_64 .
    mv "${SUBMODULE_DIR}/jms578flash_x86_64" "${OUTPUT_BINARY}"
elif command -v go >/dev/null 2>&1; then
    echo "    Using host Go compiler..."
    (cd "${SUBMODULE_DIR}" && go build -ldflags="-s -w" -o "${OUTPUT_BINARY}" .)
else
    echo "ERROR: Neither podman, docker, nor go compiler found on system." >&2
    exit 1
fi

chmod +x "${OUTPUT_BINARY}"
echo "==> [4/4] Build complete! Binary saved to:"
echo "    ${OUTPUT_BINARY}"
ls -lh "${OUTPUT_BINARY}"
