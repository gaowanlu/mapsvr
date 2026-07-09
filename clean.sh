rm -rf ./lua/ProtoLua/*.lua
rm -rf ./avant
cd thirdparty/avant && git checkout .
rm -rf protocol/proto_database.proto
cd build && make clean && cd ..
rm -rf build
