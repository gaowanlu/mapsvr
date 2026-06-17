# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MapSvr is a game server framework built on top of [@mfavant/avant](https://github.com/mfavant/avant), supporting:
- Seamless Lua logic hot-reloading without server downtime
- Client connections via TCP, UDP, and WebSocket
- Inter-process communication (IPC) between server instances via TCP Protobuf
- Database operations via a separate `dbsvrgo` (Go) service

## Key Architectural Concepts

### Two-Way Protocol Communication
All inter-process communication uses Protobuf-defined protocols. The system has three Lua VM threads:
- **Main VM**: Game logic coordination
- **Worker VM**: Client connection handling (multiple instances configurable, default 2)
- **Other VM**: Background tasks and cross-thread communication

Protocol flow:
1. C++ Avant framework receives Protobuf messages
2. Messages are converted to Lua tables and dispatched to Lua VMs
3. Lua logic processes messages and sends responses back to C++
4. C++ converts Lua tables back to Protobuf for delivery

### Protocol Registration
Protobuf messages must be registered in `src/app/lua_plugin.cpp` via `REGISTER_MSG()` to enable C++<->Lua conversion. See `protocol/proto_cmd.proto` for command definitions.

The protocol definitions include:
- **proto_cmd.proto**: 50+ command codes (EXAMPLE, TUNNEL, IPC_AUTH, LOGIN, PING, INPUT, DB_*, UDP_*, etc.)
- **proto_database.proto**: Database operation messages
- **proto_err_code.proto**: Error codes
- **proto_example.proto**: Example message types
- **proto_ipc_stream.proto**: IPC stream protocol
- **proto_lua.proto**: Lua bridge messages
- **proto_message_head.proto**: Message headers
- **proto_tunnel.proto**: Tunnel/IPC packaging
- **proto_udp.proto**: UDP protocol

### Hot-Reload
Triggered via `kill -10 <PID>`, reloads specified Lua files without stopping the server. Defined in:
- `MapSvr.OnReload()` for Main VM
- `Worker:OnReload(workerIdx)` for Worker VM
- `Other:OnReload()` for Other VM

## Common Commands

### Build
```bash
# Copy project files to avant_dir (git submodule)
./copy_mapsvr2avant.sh

# Build the Avant framework
cd avant_dir
cmake -DAVANT_JIT_VERSION=ON ..
make -j3

# Copy binary back to project root
./copy_avant_bin.sh
```

### Generate Lua Types from Protobuf
```bash
node generate_proto_lua.js ./protocol/ ./lua/ProtoLua/
```

### Build Database Service
```bash
cd dbsvrgo
./build.sh
```

### Testing
```bash
cd testing
npm install
npm run proto_gen
npm run build
node dist/testing_client.js
```

### Run
```bash
./avant --mapsvr
```

### Configuration

**config/main.ini** key settings:
- `worker_cnt = 2` (configurable 1-511)
- `max_client_cnt = 1000`
- `epoll_wait_time = 10` (tick interval in ms)
- Task types: HTTP_TASK, STREAM_TASK, WEBSOCKET_TASK

**config/ipc.json**: IPC connection configuration

## Protocol Handling in Lua

Message handlers are organized in `lua/Msg/`:
- `MsgHandlerFromClientLogic.lua`: Client connection messages (LOGIN, PING, INPUT, etc.)
- `MsgHandlerFromOtherLogic.lua`: IPC messages from other processes (WORKER2OTHER, OTHER2WORKER, etc.)
- `MsgHandlerFromUDPLogic.lua`: UDP protocol handlers

Handlers are registered as a table mapping `ProtoCmd` to handler functions.

### C++ <-> Lua Bridge

The `src/app/lua_plugin.cpp` file in `avant_dir` handles Protobuf <-> Lua table conversion. Message handlers must be registered using `REGISTER_MSG()` macro.

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `lua/` | Lua game logic |
| `protocol/` | Protobuf definitions (9 .proto files) |
| `dbsvrgo/` | Go database service |
| `testing/` | TypeScript test client |
| `config/` | Configuration files (main.ini, ipc.json) |
| `src/app/` | C++ application plugins (lua_plugin.cpp, http, websocket, stream, other) |
| `avant_dir/` | Upstream Avant framework (git submodule) |
| `log/` | Runtime log output |

## Lua VM Lifecycle

| VM | Entry Point | Hot-Reload Trigger |
|----|-------------|-------------------|
| Main | `MapSvr.OnInit()` / `MapSvr.OnReload()` | `MapSvr.OnReload()` |
| Worker | `Worker:OnInit(workerIdx)` | `Worker:OnReload(workerIdx)` |
| Other | `Other:OnInit()` | `Other:OnReload()` |
