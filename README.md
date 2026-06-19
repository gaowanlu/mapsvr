# MapSvr

MapSvr is a game server framework built on top of [@mfavant/avant](https://github.com/mfavant/avant).

It supports seamless logic hot-reloading without server downtime and allows clients to connect
via TCP, UDP, and WebSocket. Inter-process communication between server instances is handled
through TCP-based protocol exchange. All protocols are uniformly defined using
[@protocolbuffers/protobuf](https://github.com/protocolbuffers/protobuf).

## How to Build

Please refer to the [Dockerfile](./Dockerfile) in this project for the complete image build process.

## Configuration Files

Configuration files are located under the [config](./config/) directory:

- [main.ini](./config/main.ini)
- [ipc.json](./config/ipc.json)

Task types can be configured as either **TCP Stream** or **WebSocket**.

## How to Add a New Protocol

There are two important core concepts in MapSvr:

- **Protocol-based communication**
- **Asynchronous processing**

All inter-process communication is performed via asynchronous protocol messages.

### Protocol Definition

- All `.proto` files are placed under the `protocol` directory.
- After adding a new protocol, it must be registered in `lua_plugin.cpp` by defining a new mapping between `Cmd` and the corresponding Protobuf message factory.

Once registered, when Avant receives a known protocol message, it will:

1. Convert the C++ Protobuf message into a Lua table
2. Dispatch it to the corresponding Lua VM for processing

Similarly, when Lua sends a Lua table to C++, it will be converted back into a C++ Protobuf message.

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

We rely heavily on Protobuf-defined types and expect them to automatically generate Lua type
annotations, including enum support.

The [generate_proto_lua.js](./generate_proto_lua.js) script can generate corresponding Lua files for all `.proto` files under the [protocol directory](./protocol/) and place them into [ProtoLua](./lua/ProtoLua/).

These files should then be required in Lua code (e.g. [MsgHandlerLogic.lua](./lua/Msg/MsgHandlerLogic.lua)).

With the EmmyLua plugin, this enables:

* Field auto-completion
* Type checking
* Enum hints

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

All protocol handling logic is located in MsgHandlerLogic.lua.

* `MsgHandler:HandlerMsgFromUDP`
    Handles incoming UDP packets
* `MsgHandler:HandlerMsgFromOther`
    Handles messages from other server processes
* `MsgHandler:HandlerMsgFromClient`
    Handles messages from client connections
* `MsgHandler:Send2UDP`
    Sends UDP packets to a target IP and port
* `MsgHandler:Send2IPC`
    Sends protocol messages to other processes
* `MsgHandler:Send2Client`
    Sends protocol messages to client connections (WebSocket or TCP)

## About dbsvrgo

[dbsvrgo](./dbsvrgo/) is a database service written in Go that communicates with Avant via TCP Protobuf.
All database operations are handled exclusively within the `dbsvrgo` process.

Lua-based game logic servers communicate with `dbsvrgo` asynchronously using protocol messages.

```bash
avant(MapSvrGo luaVM) <---- TCP Protobuf ----> dbsvrgo(MySQL)
  appId: 1.1.1.1                               appId: 1.1.2.1
```

## How to call MapSvr.OnSafeStop()

Define your own UDP shutdown protocol, such as:

[TypeScript UDP Client](./testing/testing_client.ts) 

to call [MapSvr.OnSafeStop()](./lua/MapSvr.lua) 

by [ProtoUDPSafeStopReq & ProtoUDPSafeStopRes](./protocol/proto_udp.proto) .

Before stopping the process, send a custom UDP shutdown message to handle necessary logic such as:

* Forcing all players offline
* Persisting all player data to the database
* Preventing new player logins

## How to Hot-Reload Game Logic

Logic hot-reloading is triggered via a process signal without stopping the server.
When the signal is received, `MapSvr.OnReload` will be invoked.

```bash
kill -SIGUSR1 PID
```

MapSvr.OnReload reloads the specified Lua logic files.

⚠️ Warning

If an error occurs during reload (e.g. syntax or runtime error),
the process will crash immediately. This is a dangerous operation and should be avoided
unless absolutely necessary.

A crash during reload may interrupt database persistence logic,
potentially causing data loss or rollback.

## Debugging Lua Code

Recommended setup:

* VSCode
* EmmyLua (VSCode extension)

### Building emmy_core.so

Reference: https://github.com/EmmyLua/EmmyLuaDebugger

```bash
mkdir build
cd build
cmake .. -DEMMY_LUA_VERSION=54 -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

### CMake Integration

Copy emmy_core.so into the MapSvr directory and update lua_plugin.cpp.

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

### Using emmy_core in Lua

Other.lua

```lua
local Other = {};
local Log = require("Log");
local MapSvr = require("MapSvr")

Other_dbg = {}; -- creating global dbg object

function Other:OnInit()
    Other_dbg = require("emmy_core")
    Other_dbg.tcpListen("127.0.0.1", 9966)
    Other_dbg.waitIDE() -- waiting for IDE

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
    Other_dbg.breakHere() -- setting break point
    MapSvr.OnTick()
end
```

### VSCode launch.json

MapSvr/.vscode/launch.json

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

After starting the Avant process, the `other` thread will block at
`Other_dbg.waitIDE()`, waiting for the debugger to attach.

### Connecting VSCode to Other_dbg

In VSCode, open **Run and Debug**, select **EmmyLua New Debug**, and start debugging.
Once connected, execution will pause when `Other_dbg.breakHere()` is reached.

## FAQ

[Frequently Asked Questions](./FAQ.md)
