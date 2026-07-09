SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
echo "pwd: $SCRIPT_DIR"

cd "$SCRIPT_DIR"
rm -rf ./thirdparty
rm -rf ./lua/ProtoLua/*.lua
rm -rf ./avant
echo "Done"
