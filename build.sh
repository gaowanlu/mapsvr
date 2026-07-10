#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AVANT_DIR="$SCRIPT_DIR/thirdparty/avant"

echo "=== MapSvr 构建脚本 ==="
echo "工作目录: $SCRIPT_DIR"

# 检查依赖
command -v cmake >/dev/null || { echo "错误: cmake 未安装"; exit 1; }
command -v make >/dev/null || { echo "错误: make 未安装"; exit 1; }
command -v git >/dev/null || { echo "错误: git 未安装"; exit 1; }
command -v node >/dev/null || { echo "错误: node 未安装"; exit 1; }
command -v go >/dev/null || { echo "错误: go 未安装"; exit 1; }

# 初始化子模块（如果需要）
if [[ ! -d "$AVANT_DIR" ]]; then
    echo "=== 初始化 git 子模块 ==="
    git submodule update --init --recursive
fi

# 构建流程
echo "=== 步骤 1/6: 生成 Lua Protobuf 类型 ==="
node ./generate_proto_lua.js ./protocol/ ./lua/ProtoLua/

echo "=== 步骤 2/6: 复制 MapSvr 文件到 Avant ==="
./copy_mapsvr2avant.sh

echo "=== 步骤 3/6: 生成 C++ Protobuf 代码 ==="
cd "$AVANT_DIR/protocol" && make

echo "=== 步骤 4/6: 编译 Avant C++ 核心 ==="
cd "$AVANT_DIR"
mkdir -p build && cd build
cmake .. && make -j$(nproc)

echo "=== 步骤 5/6: 复制二进制文件回项目 ==="
cd "$SCRIPT_DIR" && ./copy_avant_bin.sh

echo "=== 步骤 6/6: 构建数据库服务 ==="
cd "$SCRIPT_DIR/dbsvrgo" && ./build.sh

echo "=== 构建完成 ==="
