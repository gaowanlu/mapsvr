# MapSvr

MapSvr is a game server framework built on top of [@mfavant/avant](https://github.com/mfavant/avant).

It supports seamless hot-reloading of game logic without server downtime, and allows clients to
connect via TCP, UDP, and WebSocket. Inter-process communication between server instances is
handled over TCP using [Protocol Buffers](https://github.com/protocolbuffers/protobuf).

## How to Build

See the [Dockerfile](./Dockerfile) for the complete build process.

## Configuration Files

Configuration files are located under the [config](./config/) directory:

- [main.ini](./config/main.ini)
- [ipc.json](./config/ipc.json)

Supported task types are **TCP Stream** and **WebSocket**.

## How to Add a New Protocol

MapSvr is built around two core concepts:

- **Protocol-based communication**
- **Asynchronous processing**

All inter-process communication uses asynchronous protocol messages.

### Protocol Definition

- All `.proto` files live under the `protocol/` directory.
- After adding a new protocol, register it in `lua_plugin.cpp` by mapping the `Cmd` value to the corresponding Protobuf message factory.

Once registered, when Avant receives a known protocol message it will:

1. Convert the C++ Protobuf message into a Lua table
2. Dispatch it to the appropriate Lua VM for processing

The reverse conversion also applies: when Lua sends a Lua table to C++, it is converted back into a C++ Protobuf message.

### Example: Registering Protocol Messages

```cpp
// Register protocols that need to interact between C++ and Lua
void lua_plugin::init_message_factory()
{
    REGISTER_MSG(ProtoCmd::PROTO_CMD_LUA_TEST, ProtoLuaTest);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_REQ_EXAMPLE, ProtoCSReqExample);
    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_RES_EXAMPLE, ProtoCSResExample);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_TUNNEL_WORKER2OTHER_EVENT_NEW_CLIENT_CONNECTION, ProtoTunnelWorker2OtherEventNewClientConnection);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_TUNNEL_WORKER2OTHER_EVENT_CLOSE_CLIENT_CONNECTION, ProtoTunnelWorker2OtherEventCloseClientConnection);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_TUNNEL_OTHERLUAVM2WORKER_CLOSE_CLIENT_CONNECTION, ProtoTunnelOtherLuaVM2WorkerCloseClientConnection);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_REQ_LOGIN, ProtoCSReqLogin);
    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_RES_LOGIN, ProtoCSResLogin);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_MAP_NOTIFY_INIT_DATA, ProtoCSMapNotifyInitData);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_REQ_MAP_PING, ProtoCSReqMapPing);
    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_RES_MAP_PONG, ProtoCSResMapPong);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_REQ_MAP_INPUT, ProtoCSReqMapInput);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_MAP_NOTIFY_STATE_DATA, ProtoCSMapNotifyStateData);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_MAP_ENTER_REQ, ProtoCSMapEnterReq);
    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_MAP_ENTER_RES, ProtoCSMapEnterRes);

    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_MAP_LEAVE_REQ, ProtoCSMapLeaveReq);
    REGISTER_MSG(ProtoCmd::PROTO_CMD_CS_MAP_LEAVE_RES, ProtoCSMapLeaveRes);
}
```

## Generating Lua Type Annotations from Protobuf

MapSvr relies heavily on Protobuf-defined types, so we auto-generate Lua type annotations
(including enums) from the `.proto` files.

The [generate_proto_lua.js](./generate_proto_lua.js) script reads all `.proto` files under the
[protocol/](./protocol/) directory and generates corresponding Lua files into
[ProtoLua/](./lua/ProtoLua/).

These generated files should be `require`d in Lua code (e.g. in
[MsgHandlerLogic.lua](./lua/Msg/MsgHandlerLogic.lua)).

With the EmmyLua VSCode extension, this enables:

- Field auto-completion
- Type checking
- Enum hints

Example in MsgHandlerLogic.lua

```lua
local ProtoLuaCmd = require("ProtoLuaCmd");
local ProtoLuaDatabase = require("ProtoLuaDatabase");
local ProtoLuaExample = require("ProtoLuaExample");
local ProtoLuaIpcStream = require("ProtoLuaIpcStream");
local ProtoLuaLua = require("ProtoLuaLua");
local ProtoLuaMessageHead = require("ProtoLuaMessageHead");
local ProtoLuaTunnel = require("ProtoLuaTunnel");
```

## Message Handling in Lua

All protocol handling logic lives in [MsgHandlerLogic.lua](./lua/Msg/MsgHandlerLogic.lua).

| Method | Description |
|--------|-------------|
| `MsgHandler:HandlerMsgFromUDP` | Handles incoming UDP packets |
| `MsgHandler:HandlerMsgFromOther` | Handles messages from other server processes |
| `MsgHandler:HandlerMsgFromClient` | Handles messages from client connections |
| `MsgHandler:Send2UDP` | Sends a UDP packet to a target IP and port |
| `MsgHandler:Send2IPC` | Sends a protocol message to another process |
| `MsgHandler:Send2Client` | Sends a protocol message to a client (TCP or WebSocket) |

## About dbsvrgo

[dbsvrgo](./dbsvrgo/) is a Go-based database service that communicates with Avant over TCP using
Protocol Buffers. All database operations are handled exclusively inside `dbsvrgo`.

The Lua game logic in Avant communicates with `dbsvrgo` asynchronously via protocol messages:

```
avant (MapSvr luaVM) <---- TCP Protobuf ----> dbsvrgo (MySQL)
  appId: 1.1.1.1                               appId: 1.1.2.1
```

## Safe Shutdown via `MapSvr.OnSafeStop()`

Define a custom UDP shutdown protocol and invoke
[`MapSvr.OnSafeStop()`](./lua/MapSvr.lua) using the messages defined in
[proto_udp.proto](./protocol/proto_udp.proto) (`ProtoUDPSafeStopReq` / `ProtoUDPSafeStopRes`).

An example TypeScript UDP client is available at
[testing_client.ts](./testing/testing_client.ts).

Sending this shutdown message triggers cleanup logic before the process exits, such as:

- Kicking all connected players offline
- Persisting all player data to the database
- Rejecting new login attempts

## Hot-Reloading Game Logic

Game logic can be hot-reloaded by sending a signal to the process — no server restart is needed.
Upon receiving the signal, `MapSvr.OnReload` is invoked:

```bash
kill -SIGUSR1 <PID>
```

`MapSvr.OnReload` reloads the specified Lua logic files.

> ⚠️ **Warning**
> If an error occurs during reload (e.g. a syntax or runtime error), the process will crash
> immediately. This is a dangerous operation and should be used with caution.
> A crash during reload may interrupt in-flight database persistence logic, potentially causing data loss or rollback.

## Debugging Lua Code

The recommended setup uses VSCode with the [EmmyLua](https://marketplace.visualstudio.com/items?itemName=EmmyLua.emmylua) extension.

### Building `emmy_core.so`

See the [EmmyLuaDebugger](https://github.com/EmmyLua/EmmyLuaDebugger) repository for details.

```bash
mkdir build && cd build
cmake .. -DEMMY_LUA_VERSION=54 -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

### Integrating with CMake

Copy the built `emmy_core.so` into the mapsvr directory and update `lua_plugin.cpp` as shown below.

```cpp
// Declare in lua_plugin.cpp
extern "C" int luaopen_emmy_core(lua_State *L);

// Load emmy_core into other_lua_state
luaL_requiref(this->other_lua_state, "emmy_core", luaopen_emmy_core, 1);
lua_pop(this->other_lua_state, 1);

void lua_plugin::on_other_init(avant::workers::other *ptr_other_obj)
{
    this->ptr_other_obj = ptr_other_obj;
    this->other_lua_state = luaL_newstate();
    luaL_openlibs(this->other_lua_state);

    luaL_requiref(this->other_lua_state, "emmy_core", luaopen_emmy_core, 1);
    lua_pop(this->other_lua_state, 1);

    other_mount();
    std::string filename = this->lua_dir + "/Init.lua";
    int isok = luaL_dofile(this->other_lua_state, filename.data());
    lua_plugin::lua_plugin_lua_return_not_is_ok_print_error(isok, this->other_lua_state);
    ASSERT_LOG_EXIT(isok == LUA_OK);
}
```

Link `emmy_core.so` when building Avant:

```bash
target_link_libraries(${PROJECT_NAME} ... /path/to/emmy_core.so ${EXTERNAL_LIB})
```

### Using `emmy_core` in Lua

[Other.lua](./lua/Other.lua)

```lua
local Other = {};
local Log = require("Log");
local MapSvr = require("MapSvr")

Other_dbg = {}; -- global dbg object

function Other:OnInit()
    Other_dbg = require("emmy_core")
    Other_dbg.tcpListen("127.0.0.1", 9966)
    Other_dbg.waitIDE() -- wait for IDE connection

    local log = "OnOtherInit";
    Log:Error(log);
    MapSvr.OnInit()
    Other:OnReload();
end

function Other:OnStop()
    local log = "OnOtherStop";
    Log:Error(log);
    MapSvr.OnStop()
end

function Other:OnTick()
    Other_dbg.breakHere() -- set breakpoint
    MapSvr.OnTick()
end
```

### VSCode `launch.json`

Create `.vscode/launch.json` in the mapsvr directory:

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "type": "emmylua_new",
            "request": "launch",
            "name": "EmmyLua New Debug",
            "host": "127.0.0.1",
            "port": 9966,
            "ext": [
                ".lua",
                ".lua.txt",
                ".lua.bytes"
            ],
            "ideConnectDebugger": true
        }
    ]
}
```

### Starting Avant

Once the Avant process starts, the `other` thread blocks at `Other_dbg.waitIDE()`, waiting for
the debugger to connect.

### Connecting VSCode to `Other_dbg`

In VSCode, open **Run and Debug**, select **EmmyLua New Debug**, and press **Start**.
Once connected, execution will pause at any `Other_dbg.breakHere()` calls.

## FAQ

See [FAQ.md](./FAQ.md) for frequently asked questions.
