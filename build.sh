set -e

# 1. 获取操作系统类型
OS_NAME=$(uname -s)

# 2. 根据系统设置正确的 CPU 核心数变量（解决 macOS 没有 nproc 的问题）
if [ "$OS_NAME" == "Darwin" ]; then
    JOBS=$(sysctl -n hw.logicalcpu)
elif [ "$OS_NAME" == "Linux" ]; then
    JOBS=$(nproc)
else
    echo "Unsupported OS: $OS_NAME"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AVANT_DIR="$SCRIPT_DIR/thirdparty/avant"

echo "=== MapSvr Build Script ==="
echo "Working directory: $SCRIPT_DIR"

# ── 检测操作系统，设置 MACOSX_DEPLOYMENT_TARGET ──
if [ "$OS_NAME" == "Darwin" ]; then
    export MACOSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion)
    echo "Detected macOS | JOBS=$JOBS | MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
elif [ "$OS_NAME" == "Linux" ]; then
    echo "Detected Linux | JOBS=$JOBS"
else
    echo "Error: Unsupported OS: $OS_NAME"
    exit 1
fi

echo "Detected OS | JOBS=$JOBS | MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"

# Check dependencies
command -v cmake >/dev/null || { echo "Error: cmake is not installed"; exit 1; }
command -v make  >/dev/null || { echo "Error: make is not installed"; exit 1; }
command -v git   >/dev/null || { echo "Error: git is not installed"; exit 1; }
command -v node  >/dev/null || { echo "Error: node is not installed"; exit 1; }
command -v go    >/dev/null || { echo "Error: go is not installed"; exit 1; }

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
cd "$AVANT_DIR/external/LuaJIT-2.1.ROLLING"
make -j"$JOBS"

cd "$AVANT_DIR"
mkdir -p build && cd build
cmake -DAVANT_JIT_VERSION=ON .. && make -j"$JOBS"

echo "=== Step 5/6: Copy binary files back to project ==="
cd "$SCRIPT_DIR" && ./copy_avant_bin.sh

echo "=== Step 6/6: Build database service ==="
cd "$SCRIPT_DIR/dbsvrgo" && ./build.sh

echo "=== Build completed ==="