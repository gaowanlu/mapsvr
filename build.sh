make && \
echo "Finished generate_proto_lua." && \
./copy_mapsvr2avant.sh && \
echo "Finished copy_mapsvr2avant." && \
cd ./thirdparty/avant && \
cd protocol && make && cd .. && \
echo "Finished generate_proto_cpp." && \
mkdir -p build && \
cd build && cmake .. && make -j$(nproc) && cd .. && \
echo "Finished build c++." && \
cd .. && cd .. && pwd &&\
./copy_avant_bin.sh && \
echo "Finished copy_avant_bin." && \
cd ./dbsvrgo && ./build.sh && \
echo "Finished build dbsvrgo." && \
cd ..
