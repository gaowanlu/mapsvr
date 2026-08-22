FROM ubuntu:latest
RUN mkdir -p /mapsvrgo

COPY . /mapsvrgo
WORKDIR /mapsvrgo

RUN apt update
RUN apt install cmake g++ make git -y
RUN apt install protobuf-compiler libprotobuf-dev  -y
RUN apt install libssl-dev -y
RUN apt install -y nodejs npm

WORKDIR /mapsvrgo
RUN git submodule update --init --recursive

WORKDIR /mapsvrgo/
RUN chmod +x ./*.sh
RUN ./copy_mapsvr2avant.sh

# for generate_proto_lua
WORKDIR /mapsvrgo
RUN make clean && make

WORKDIR /mapsvrgo/thirdparty/avant
RUN cd external/LuaJIT-2.1 \
    && make clean \
    && make -j$(nproc)
WORKDIR /mapsvrgo/thirdparty/avant
RUN cd protocol \
    && make \
    && cd .. \
    && mkdir build \
    && rm -rf ./build/* \
    && cd build \
    && cmake -DAVANT_JIT_VERSION=ON .. \
    && make -j$(nproc) \
    && cd .. \
    && cd bin \
    && ls

WORKDIR /mapsvrgo
RUN ./copy_avant_bin.sh

WORKDIR /mapsvrgo/testing
RUN apt install -y nodejs npm
RUN npm install
RUN npm run proto_gen
RUN npm run build

WORKDIR /mapsvrgo/dbsvrgo
RUN apt install -y golang
RUN chmod +x ./build.sh
RUN ./build.sh

WORKDIR /mapsvrgo

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["./avant --mapsvr"]
