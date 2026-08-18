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

```text
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

```text
┌──────────────────────────────────────┐          ┌──────────────────────────┐
│         Other VM (MapSvr.lua)        │          │       dbsvrgo (Go)       │
│  - Player, Map, FSRoom logic         │          │  - client.Client (RPC)   │
│  - MsgHandler:Send2IPC(appId, ...)   │ ◄──────► │  - worker.Worker (Queue) │
└──────────────────────────────────────┘          │  - mapper.BuildSQL       │
                   ▲                              └──────────────────────────┘
                   │                                            ▼
         C++ Avant IPC Tunnel                               ┌──────────────────┐
      (Mapped via unique AppIDs)                            │ PostgreSQL DB    │
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

### Lua Language Version

* **All Lua scripts must be written for Lua 5.1.** The Avant framework embeds LuaJIT 2.1, which implements the Lua 5.1 API (with LuaJIT extensions).
* Do **not** use Lua 5.2+/5.3+ features in `lua/` code: integer division `//`, bitwise operator syntax (`&`, `|`, `~`, `<<`, `>>`), `goto` / `<labels>`, `string.pack`/`string.unpack`, `table.pack`/`table.unpack`, `math.type`, etc. In 5.1 the table helper is the global `unpack`, not `table.unpack`. For bitwise operations use LuaJIT's `bit` library (or plain arithmetic).

### Global `avant` C++ Bridge API

The `avant` module is injected into the Lua environment with the following interfaces:

* `avant:HighresTime()`: Returns high-resolution time triple `(seconds, milliseconds, nanoseconds)`.
* `avant:Monotonic()`: Returns monotonic milliseconds.
* `avant:Logger(message)`: Outputs logs through the native C++ logger.
* `avant:CreateNewProtobufByCmd(cmd)`: Instantiates a Protobuf struct based on a command ID.
* `avant:Lua2Protobuf(message, msg_type, cmd, param1, param2, param3)`: Converts Lua tables to binary Protobuf.
* `avant:GetDBSvrGoAppID()`: Retrieves target database service identifier from configuration.

### Async & Coroutine Management

The `Async` module provides a managed coroutine scheduler (`CoroutineMgr`) to handle asynchronous tasks with timeouts and manual wakeups.

* `CoroutineMgr.Spawn(func, ...)`: Creates and starts a new managed coroutine. Returns `sessionID`.
* `CoroutineMgr.Wait(timeout)`: Suspends the current coroutine. If `timeout` is provided, it returns `(isTimeout, ...)` when resumed or timed out.
* `CoroutineMgr.Wakeup(sessionID, ...)`: Resumes a suspended coroutine with the provided arguments.
* `CoroutineMgr.Kill(sessionID)`: Forces a coroutine to terminate.
* `CoroutineMgr.DebugDump()`: Logs detailed status of all active coroutine sessions for debugging.
* `CoroutineMgr.SetTag(tag)`: Assigns a debug tag to the current coroutine.

### Protocol Command Layout (`protocol/*.proto`)

* `proto_cmd.proto`: Over 50 command definitions (e.g., `LOGIN`, `PING`, `DB_*`, `UDP_*`).
* `proto_database.proto`: Defines PostgreSQL schema bindings (e.g., `DbUserRecord`).
* `proto_message_head.proto` & `proto_ipc_stream.proto`: Formulate the envelope for network packages.

> ⚠️ **Developer Note**: All new Protobuf messages must be explicitly registered inside `src/app/lua_plugin.cpp` using the `REGISTER_MSG()` macro to be accessible in Lua.

---

## 4. Repository & Directory Layout

```text
├── lua/                           # Active Game Logic (Other VM)
│   ├── Async/                    # Asynchronous task & coroutine management
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

### ⚠️ Lua Verification Rule (No Standalone Interpreter)

* **Never invoke `lua` or `luajit` directly to run or verify Lua code** — no standalone Lua interpreter is installed on the development machine.
* Write Lua only for the framework (under `lua/`) and verify it **inside the framework**: build with `./build.sh`, run with `./avant --mapsvr`, and use hot reload (`kill -SIGUSR1 <PID>`) for Lua-only changes. Check `server_output.log` and the latest `log/YYYY-MM-DD_HH.log` for runtime errors.

### Build & Run MapSvr

Use the automation scripts to manage the build process:

* `./build.sh`: Performs a full build (generates Lua types, copies files to Avant, compiles C++ core, copies binary back, and builds `dbsvrgo`).
* `./clean.sh`: Cleans the environment (removes `thirdparty`, generated Lua types, binaries, and logs).
* `./update.sh`: Updates the `thirdparty/avant` submodule and runs `clean.sh`.

To build and run the server:

```bash
./build.sh
./avant --mapsvr
```

### Database & Testing Setup

The database service (`dbsvrgo`) is built as part of `./build.sh`.

To run end-to-end integration tests:

```bash
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

### Viewing Logs

* **Standard Logs**: Check the `log/` directory and look for the most recent date-stamped file (e.g., `log/YYYY-MM-DD_HH.log`).
* **Console Output**: Monitor `server_output.log` in the project root for real-time process stdout/stderr.

### Submodule Rules

> ⛔ **Strict Constraint**: Never commit changes to the `avant_dir/` subdirectory. It is an upstream Git submodule. Any modifications there must only be done locally for experimental debugging.

## 6. Git Commit Convention

To maintain a clean and readable history, please follow this commit message format:

**Format:** `<type>: <description>`

**Common Types:**

* `feat`: A new feature.
* `fix`: A bug fix.
* `update`: Updating dependencies, versions, or third-party code.
* `test`: Adding or updating tests.
* `docs`: Documentation only changes.
* `refactor`: A code change that neither fixes a bug nor adds a new feature.
* `chore`: Updating build tasks, package manager configs, etc.

**Examples:**

* `feat: implement player inventory system`
* `fix: resolve memory leak in FSRoom logic`
* `update: upgrade avant to latest commit`
