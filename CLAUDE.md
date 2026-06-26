# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MapSvr is a game server framework built on top of [@mfavant/avant](https://github.com/mfavant/avant), supporting:
- Seamless Lua logic hot-reloading without server downtime
- Client connections via TCP, UDP, and WebSocket
- Inter-process communication (IPC) between server instances via TCP Protobuf
- Database operations via a separate `dbsvrgo` (Go) service

## Key Architectural Concepts

### Lua VM Architecture

MapSvr uses **four** Lua VM threads:

| VM | Entry Point | Hot-Reload Trigger | Purpose |
|----|-------------|-------------------|---------|
| **Main** | `Main:OnInit()` / `Main:OnReload()` | `Main:OnReload()` | Initial setup, not used for game logic |
| **Worker** | `Worker:OnInit(workerIdx)` | `Worker:OnReload(workerIdx)` | Client connection handling (configurable 1-511 instances) |
| **Other** | `Other:OnInit()` | `Other:OnReload()` | Game logic coordination, delegates to Main VM |
| **Main Game** | `MapSvr.OnInit()` / `MapSvr.OnReload()` | `MapSvr.OnReload()` | Core game logic (Player, Map, FSRoom, etc.) |

The **Other VM** receives all messages from C++ and dispatches them to the **Main Game** VM (`MapSvr`). The Main VM is currently a stub.

### Two-Way Protocol Communication
All inter-process communication uses Protobuf-defined protocols. Protocol flow:
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
Triggered via `kill -SIGUSR1 <PID>`, reloads specified Lua files without stopping the server.

**Main VM hot-reload list** (defined in `MapSvr.OnReload()`):
- ValidatorLogic, PlayerLogic, PlayerMgrLogic
- PlayerCmptBaseLogic, PlayerCmptInfoLogic, PlayerCmptBagLogic
- PlayerCmptMapLogic, PlayerCmptMap3DLogic
- PlayerCmptFSRoomLogic
- MapLogic, MapMgrLogic
- FSRoomPlayerLogic, FSRoomPlayerSkillLogic, FSRoomSyncLogic
- FSRoomHexMapLogic, FSRoomHexMapAStarLogic
- FSRoomIsometricMapLogic, FSRoomIsometricMapAStarLogic
- FSRoomSquareMapLogic, FSRoomSquareMapAStarLogic
- FSRoomMapFactoryLogic, FSRoomBattleLogic, FSRoomLogic
- FSRoomMgrLogic
- MsgHandlerFromUDPLogic, MsgHandlerFromOtherLogic, MsgHandlerFromClientLogic
- MsgHandlerLogic, ConfigTableMgrLogic, TimeMgrLogic
- Map3DLogic, Map3DMgrLogic

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
- `app_id = 1.1.1.1`: Unique process identifier for IPC
- `worker_cnt = 2` (configurable 1-511): Number of Worker VM instances
- `max_client_cnt = 1000`: Maximum concurrent client connections
- `epoll_wait_time = 10`: Tick interval in ms
- `task_type = WEBSOCKET_TASK`: Task type (HTTP_TASK, STREAM_TASK, WEBSOCKET_TASK)
- `lua_dir = ./lua`: Lua script directory
- `other_udp_svr_ip=127.0.0.1` and `other_udp_svr_port=20028`: UDP settings for Other VM

**config/ipc.json**: IPC connection configuration

## Protocol Handling in Lua

### Message Handler Organization

Message handlers are organized in `lua/Msg/`:

| File | Purpose | Key Handlers |
|------|---------|--------------|
| `MsgHandlerLogic.lua` | Core message dispatcher | `Send2Client()`, `Send2IPC()`, `Send2UDP()`, `HandlerMsgFromClient()`, `HandlerMsgFromOther()`, `HandlerMsgFromUDP()` |
| `MsgHandlerFromClientLogic.lua` | Client connection messages | LOGIN, PING, INPUT, MAP_ENTER/LEAVE, CREATE_USER |
| `MsgHandlerFromOtherLogic.lua` | IPC messages from other processes | DBUSERRECORD responses (SELECT, INSERT, LOGIN) |
| `MsgHandlerFromUDPLogic.lua` | UDP protocol handlers | SAFESTOP_REQ, EXAMPLE |

### Protocol Flow

1. **Client -> Worker VM**: Avant framework receives Protobuf messages and sends to Worker VM
2. **Worker -> Other VM**: Worker forwards client messages to Other VM (Main Game)
3. **Other VM Processing**: Main Game processes message and may:
   - Send response back to Client via Worker VM
   - Send IPC messages to dbsvrgo for database operations
   - Communicate with other IPC processes

### Message Sending

| Method | Target | Parameters |
|--------|--------|------------|
| `MsgHandler:Send2Client()` | Client connection | `clientGID`, `workerIdx`, `cmd`, `message` |
| `MsgHandler:Send2IPC()` | Other processes | `appId`, `cmd`, `message` |
| `MsgHandler:Send2UDP()` | UDP endpoint | `ip`, `port`, `cmd`, `message` |

### C++ <-> Lua Bridge

The `src/app/lua_plugin.cpp` file in `avant_dir` handles Protobuf <-> Lua table conversion. Message handlers must be registered using `REGISTER_MSG()` macro.

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `lua/` | Lua game logic |
| `lua/Player/` | Player-related logic (Player, PlayerMgr, PlayerCmpt*) |
| `lua/Msg/` | Message handlers (MsgHandler*, client/IPC/UDP) |
| `lua/Map/` | 2D map logic |
| `lua/FSRoom/` | Full-screen room battle logic |
| `lua/ProtoLua/` | Auto-generated Lua types from Protobuf |
| `lua/Utils/` | Utilities (Validator, Debug, Log) |
| `protocol/` | Protobuf definitions (9 .proto files) |
| `dbsvrgo/` | Go database service |
| `testing/` | TypeScript test client |
| `config/` | Configuration files (main.ini, ipc.json) |
| `src/app/` | C++ application plugins (lua_plugin.cpp, http, websocket, stream, other) |
| `avant_dir/` | Upstream Avant framework (git submodule) |
| `log/` | Runtime log output |

## Lua Player System

**Player Management** (`lua/Player/`):

| File | Purpose |
|------|---------|
| `PlayerData.lua` | Player class data template |
| `PlayerLogic.lua` | Player class implementation |
| `PlayerMgrData.lua` | Player manager data container |
| `PlayerMgrLogic.lua` | Player manager (create, bind, online/offline) |
| `ValidatorData.lua` | Validator class data template |
| `ValidatorLogic.lua` | Validation functions (IsEmptyString, UserIdValidator, UserPasswordValidator) |

**Player Components** (`lua/Player/PlayerCmpt*.lua`):

| Component | Purpose |
|-----------|---------|
| `PlayerCmptBaseLogic` | Base component class |
| `PlayerCmptInfoLogic` | Player info (userId, clientGID, workerIdx) |
| `PlayerCmptBagLogic` | Inventory/bag management |
| `PlayerCmptMapLogic` | 2D map functionality |
| `PlayerCmptMap3DLogic` | 3D map functionality |
| `PlayerCmptFSRoomLogic` | Full-screen room battle |

## Error Codes

Defined in `protocol/proto_err_code.proto`:

| Code | Name | Description |
|------|------|-------------|
| 0 | OK | Success |
| 1 | ERR_UNKNOW | Unknown error |
| 2 | ERR_SERVICE_SAFESTOPED | Service has been stopped gracefully |
| 1001 | ERR_TARGET_MAP_NOT_FOUND | Target map does not exist |
| 1002 | ERR_USERID_INPUT_INVALID | Invalid user ID |
| 1003 | ERR_PASSWORD_INPUT_INVALID | Invalid password |
| 1004 | ERR_USERID_OR_PASSWORD_NOTMATCH | User ID or password incorrect |

## Database Operations

Database operations are handled by `dbsvrgo` (Go service). Key messages:

| Request | Response | Purpose |
|---------|----------|---------|
| `PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_REQ` | `SELECT_DBUSERRECORD_RES` | Query user records by WHERE clause |
| `PROTO_CMD_DBSVRGO_INSERT_DBUSERRECORD_REQ` | `INSERT_DBUSERRECORD_RES` | Insert new user record |
| `PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_LOGIN_REQ` | `SELECT_DBUSERRECORD_LOGIN_RES` | Login query with password verification |

## Git Repository Notes

**Do not commit changes to the `avant_dir/` subdirectory.** This directory contains an upstream git submodule (the Avant framework) that should not be modified in this repository. Any local changes made to `avant_dir/` are intended to be temporary for testing purposes and should never be committed.
