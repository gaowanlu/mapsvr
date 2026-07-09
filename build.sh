SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
echo "pwd: /$SCRIPT_DIR"
[[ ! -d "/$SCRIPT_DIR/thirdparty/avant" ]] && git submodule update --init --recursive
make 
echo "Finished generate_proto_lua."
./copy_mapsvr2avant.sh
echo "Finished copy_mapsvr2avant."
cd "/$SCRIPT_DIR/thirdparty/avant/protocol"
make
echo "Finished generate_proto_cpp."
cd "/$SCRIPT_DIR/thirdparty/avant"
mkdir -p build
cd "/$SCRIPT_DIR/thirdparty/avant/build"
cmake .. && make -j$(nproc)
echo "Finished build c++."
cd "/$SCRIPT_DIR"
./copy_avant_bin.sh
echo "Finished copy_avant_bin."
cd "/$SCRIPT_DIR"
cd ./dbsvrgo && ./build.sh
echo "Finished build dbsvrgo."
cd "/$SCRIPT_DIR"
echo "Done"
