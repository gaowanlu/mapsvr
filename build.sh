#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AVANT_DIR="$SCRIPT_DIR/thirdparty/avant"

echo "=== MapSvr Build Script ==="
echo "Working directory: $SCRIPT_DIR"

# Check dependencies
command -v cmake >/dev/null || { echo "Error: cmake is not installed"; exit 1; }
command -v make >/dev/null || { echo "Error: make is not installed"; exit 1; }
command -v git >/dev/null || { echo "Error: git is not installed"; exit 1; }
command -v node >/dev/null || { echo "Error: node is not installed"; exit 1; }
command -v go >/dev/null || { echo "Error: go is not installed"; exit 1; }

# Initialize submodules (if needed)
if [[ ! -d "$AVANT_DIR" ]]; then
    echo "=== Initialize git submodules ==="
    git submodule update --init --recursive
fi

# Build process
echo "=== Step 1/6: Generate Lua Protobuf types ==="
node ./generate_proto_lua.js ./protocol/ ./lua/ProtoLua/

echo "=== Step 2/6: Copy MapSvr files to Avant ==="
./copy_mapsvr2avant.sh

echo "=== Step 3/6: Generate C++ Protobuf code ==="
cd "$AVANT_DIR/protocol" && make

echo "=== Step 4/6: Compile Avant C++ core ==="
cd "$AVANT_DIR"
mkdir -p build && cd build
cmake .. && make -j$(nproc)

echo "=== Step 5/6: Copy binary files back to project ==="
cd "$SCRIPT_DIR" && ./copy_avant_bin.sh

echo "=== Step 6/6: Build database service ==="
cd "$SCRIPT_DIR/dbsvrgo" && ./build.sh

echo "=== Build completed ==="
