#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
echo "工作目录: $SCRIPT_DIR"

cd "$SCRIPT_DIR"

# 删除 Avant 相关的第三方库
rm -rf ./thirdparty

# 删除生成的 Lua Protobuf 类型文件
rm -f ./lua/ProtoLua/*.lua

# 删除构建的二进制文件
rm -rf ./avant

# 删除日志文件（如果存在）
rm -f ./log/*.log 2>/dev/null || true

echo "清理完成"
