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
- **Worker VM**: Client connection handling (multiple instances configurable)
- **Other VM**: Background tasks and cross-thread communication

Protocol flow:
1. C++ Avant framework receives Protobuf messages
2. Messages are converted to Lua tables and dispatched to Lua VMs
3. Lua logic processes messages and sends responses back to C++
4. C++ converts Lua tables back to Protobuf for delivery

### Protocol Registration
Protobuf messages must be registered in `lua_plugin.cpp` via `REGISTER_MSG()` to enable C++<->Lua conversion. See `protocol/proto_cmd.proto` for command definitions.

### Hot-Reload
Triggered via `kill -10 <PID>`, reloads specified Lua files without stopping the server. Defined in `MapSvr.OnReload()` and `Other:OnReload()`.

## Common Commands

### Build
```bash
# See Dockerfile for complete build process
cd avant_dir
cmake -DAVANT_JIT_VERSION=ON ..
make -j3
./copy_avant_bin.sh  # Copy binary back to project root
```

### Generate Lua Types from Protobuf
```bash
node generate_proto_lua.js ./protocol/ ./lua/ProtoLua/
```

### Testing
```bash
cd testing
npm install
npm run proto_gen
npm run build
node dist/testing_client.js
```

### Database Service
```bash
cd dbsvrgo
./build.sh
```

### Run
```bash
./avant --mapsvr
```

## Protocol Handling in Lua

Message handlers are organized in `lua/Msg/`:
- `MsgHandlerFromClientLogic.lua`: Client connection messages (login, map input, etc.)
- `MsgHandlerFromOtherLogic.lua`: IPC messages from other processes
- `MsgHandlerFromUDPLogic.lua`: UDP protocol handlers

Handlers are registered as a table mapping `ProtoCmd` to handler functions.

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `lua/` | Lua game logic |
| `protocol/` | Protobuf definitions |
| `dbsvrgo/` | Go database service |
| `testing/` | TypeScript test client |
| `config/` | Configuration files |

## Lua VM Lifecycle

| VM | Entry Point | Hot-Reload Trigger |
|----|-------------|-------------------|
| Main | `MapSvr.OnInit()` / `MapSvr.OnReload()` | `MapSvr.OnReload()` |
| Worker | `Worker:OnInit(workerIdx)` | `Worker:OnReload(workerIdx)` |
| Other | `Other:OnInit()` | `Other:OnReload()` |
