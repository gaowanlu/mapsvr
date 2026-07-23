# 1. 获取操作系统类型
OS_NAME=$(uname -s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
echo "Working directory: $SCRIPT_DIR"

cd "$SCRIPT_DIR"

# Remove Avant-related third-party libraries
rm -rf ./thirdparty

# Remove generated Lua Protobuf type files
rm -f ./lua/ProtoLua/*.lua

# Remove built binary files
rm -rf ./avant

# Remove log files (if exist)
rm -f ./log/*.log 2>/dev/null || true

echo "Cleanup completed"
