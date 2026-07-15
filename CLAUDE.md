# CLAUDE.md

This file provides development and architectural guidance for the MapSvr repository when working with Claude Code.

---

## 1. Core Architecture & Threading Model

### ⚠️ Critical Clarification: Lua VM Reality

Although the C++ Avant framework creates three types of Lua VMs (`Main`, `Worker`, `Other`), **almost all game logic runs exclusively within the Other VM (`Other.lua`) on the Other thread.**

* `Main.lua` and `Worker.lua` are essentially **unused placeholders** in the Lua layer.

| Thread (C++) | Lua VM | Real Usage | Responsibility |
| --- | --- | --- | --- |
| **Main Thread** | Main VM | ❌ Unused | Only accepts TCP/UDP/WS client connections and assigns them to Workers. |
| **Worker Threads** | Worker VMs | ❌ Unused | Only handles low-level client socket read, write, decode, and encode. |
| **Other Thread** | **Other VM** | **Active** | **Runs 100% of game logic** (Player, Map, FSRoom, MsgHandlers, DB IPC). |

### End-to-End Message Flow

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Client      │     │  C++ Main    │     │  C++ Worker  │     │  Other VM    │
│  (TCP/WS)    │ ──► │  Thread      │ ──► │  Thread      │ ──► │  (MapSvr)    │
│              │     │  (Accept)    │     │  (Decode)    │     │  (Game Logic)│
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
       ▲                                                              │
       │                                                              │
       └──────────────────────────────────────────────────────────────┘
                          (Direct response via workerIdx)

```

1. **Ingress**: C++ Main Thread accepts a connection $\rightarrow$ assigns to a C++ Worker Thread.
2. **Dispatch**: C++ Worker reads & decodes bytes $\rightarrow$ forwards to Other VM via `on_other_lua_vm_recv_client_message()`.
3. **Processing**: Other VM executes game logic $\rightarrow$ sends response back using `avant:Lua2Protobuf()` by specifying the target `workerIdx`.
4. **Egress**: The designated C++ Worker encodes & writes data back to the Client.

---

## 2. Inter-Process Communication (IPC) & Database Architecture

Database operations are decoupled into a separate Go service (`dbsvrgo`) communicating with MapSvr's Other VM via a custom TCP Protobuf IPC stream.

```
┌──────────────────────────────────────┐          ┌──────────────────────────┐
│         Other VM (MapSvr.lua)        │          │       dbsvrgo (Go)       │
│  - Player, Map, FSRoom logic         │          │  - client.Client (RPC)   │
│  - MsgHandler:Send2IPC(appId, ...)   │ ◄──────► │  - worker.Worker (Queue) │
└──────────────────────────────────────┘          │  - mapper.BuildSQL       │
                   ▲                              └──────────────────────────┘
                   │                                            │
         C++ Avant IPC Tunnel                                   ▼
      (Mapped via unique AppIDs)                        ┌──────────────────┐
                                                        │ PostgreSQL DB    │
                                                        └──────────────────┘

```

### Database Request Pipeline

1. **Lua Trigger**: Lua logic calls `MsgHandler:Send2IPC(appId, cmd, message)`.
2. **C++ Transit**: Avant C++ serializes with `msg_type = PROTO_LUA_VM_MSG_TYPE_IPC` and routes it via TCP to `dbsvrgo` (matched by its unique `AppID`).
3. **Go Consumption**: `dbsvrgo` processes packets asynchronously through an internal channel queue (`Worker.Push()`).
4. **SQL Translation**: `mapper.go` dynamically compiles Protobuf messages into PostgreSQL queries.
5. **Response Return**: Result is sent back over the IPC socket $\rightarrow$ C++ triggers Lua callback `MsgHandler:HandlerMsgFromOther()`.

---

## 3. Lua API & Protocol Mapping

### Global `avant` C++ Bridge API

The `avant` module is injected into the Lua environment with the following interfaces:

* `avant:HighresTime()`: Returns high-resolution time triple `(seconds, milliseconds, nanoseconds)`.
* `avant:Monotonic()`: Returns monotonic milliseconds.
* `avant:Logger(message)`: Outputs logs through the native C++ logger.
* `avant:CreateNewProtobufByCmd(cmd)`: Instantiates a Protobuf struct based on a command ID.
* `avant:Lua2Protobuf(message, msg_type, cmd, param1, param2, param3)`: Converts Lua tables to binary Protobuf.
* `avant:GetDBSvrGoAppID()`: Retrieves target database service identifier from configuration.

### Protocol Command Layout (`protocol/*.proto`)

* `proto_cmd.proto`: Over 50 command definitions (e.g., `LOGIN`, `PING`, `DB_*`, `UDP_*`).
* `proto_database.proto`: Defines PostgreSQL schema bindings (e.g., `DbUserRecord`).
* `proto_message_head.proto` & `proto_ipc_stream.proto`: Formulate the envelope for network packages.

> ⚠️ **Developer Note**: All new Protobuf messages must be explicitly registered inside `src/app/lua_plugin.cpp` using the `REGISTER_MSG()` macro to be accessible in Lua.

---

## 4. Repository & Directory Directory Layout

```
├── lua/                           # Active Game Logic (Other VM)
│   ├── Player/                    # Player entity, components (Bag, Info, Map, FSRoom)
│   ├── Msg/                       # Message routing (FromClient, FromOther, FromUDP)
│   ├── Map/                       # 2D grid maps & navigation
│   ├── FSRoom/                    # Battle rooms & map calculations (AStar, Isometric, Hex)
│   ├── ProtoLua/                  # Auto-generated Lua types from Protobuf definitions
│   └── Utils/                     # Shared utilities (Validation, Log, Time)
├── protocol/                      # Protobuf definitions (.proto)
├── dbsvrgo/                       # Go Database Microservice
│   ├── client/                    # TCP connection pool & auto-reconnection logic
│   ├── worker/                    # Job queue dispatcher & handler mappings
│   └── mapper/                    # Safe SQL builder translating Proto to PostgreSQL
├── config/                        # Service configs (main.ini, ipc.json)
├── testing/                       # TypeScript/Node.js client test suite
├── src/app/                       # C++ Avant custom plugins (lua_plugin.cpp)
└── avant_dir/                     # Upstream Avant Framework (Git Submodule - DO NOT COMMIT)

```

---

## 5. Development Workflow

### Build & Run MapSvr

```bash
# 1. Copy local MapSvr application code to avant_dir
./copy_mapsvr2avant.sh

# 2. Compile the C++ binary
cd avant_dir
cmake -DAVANT_JIT_VERSION=ON ..
make -j3

# 3. Pull binary back to root and execute
cd ..
./copy_avant_bin.sh
./avant --mapsvr

```

### Database & Testing Setup

```bash
# Generate Lua types from Protobuf definitions
node generate_proto_lua.js ./protocol/ ./lua/ProtoLua/

# Compile dbsvrgo
cd dbsvrgo && ./build.sh && cd ..

# Run end-to-end integration tests
cd testing
npm install && npm run proto_gen && npm run build
node dist/testing_client.js

```

### Hot-Reloading Lua Logic

MapSvr supports zero-downtime hot reloading of game logic.

* **Trigger**: Send a user signal 1 to the running C++ process:
```bash
kill -SIGUSR1 <PID>

```


* **Reload Scope**: Managed inside `MapSvr.OnReload()`. This safely reloads core components (e.g., `PlayerLogic`, `MapLogic`, `FSRoomLogic`, and all message handler files) without tearing down existing socket connections.

### Submodule Rules

> ⛔ **Strict Constraint**: Never commit changes to the `avant_dir/` subdirectory. It is an upstream Git submodule. Any modifications there must only be done locally for experimental debugging.
