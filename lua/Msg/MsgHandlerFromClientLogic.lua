local Log = require("Log")
local PlayerMgr = require("PlayerMgrLogic")
local MsgHandler = require("MsgHandlerLogic")
local MapSvr = require("MapSvr")
local Validator = require("ValidatorLogic")

---@type table<number, function>
MsgHandlerFromClient = {}

-- 有新的客户端连接
---@param message ProtoLua_ProtoTunnelWorker2OtherEventNewClientConnection
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_TUNNEL_WORKER2OTHER_EVENT_NEW_CLIENT_CONNECTION] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    if message.gid ~= clientGID then
        Log:Error(
            'PROTO_CMD_TUNNEL_WORKER2OTHER_EVENT_NEW_CLIENT_CONNECTION message["gid"]%s ~= clientGID[%s]', message.gid,
            clientGID
        )
        return
    end

    Log:Error(
        "New Client Connection gid[%s] workerIdx[%d] IP [%s] Port [%d]", clientGID, workerIdx, message.ip, message.port
    )

    local player = PlayerMgr.GetPlayerByPlayerId(playerId)

    if player ~= nil then
        Log:Error("Fatal Player already exists for gid[%s] workerIdx[%d]", clientGID, workerIdx)

        -- 关闭客户端的连接
        ---@type ProtoLua_ProtoTunnelOtherLuaVM2WorkerCloseClientConnection
        local ProtoTunnelOtherLuaVM2WorkerCloseClientConnection = { gid = clientGID, workerIdx = workerIdx }
        MsgHandler:Send2Client(
            clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_TUNNEL_OTHERLUAVM2WORKER_CLOSE_CLIENT_CONNECTION,
            ProtoTunnelOtherLuaVM2WorkerCloseClientConnection
        )
        return
    end

    PlayerMgr.SetPlayerIdOnline(playerId)
end

-- 客户端连接关闭
---@param message ProtoLua_ProtoTunnelWorker2OtherEventCloseClientConnection
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_TUNNEL_WORKER2OTHER_EVENT_CLOSE_CLIENT_CONNECTION] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    if message.gid ~= clientGID then
        Log:Error(
            'PROTO_CMD_TUNNEL_WORKER2OTHER_EVENT_CLOSE_CLIENT_CONNECTION message["gid"]%s ~= clientGID[%s]', message.gid,
            clientGID
        )
        return
    end
    -- Log:Error("Close Client Connection gid[%s] workerIdx[%d]", clientGID, workerIdx)

    PlayerMgr.SetPlayerIdOffline(playerId)

    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player ~= nil then
        player:OnLogout()
        PlayerMgr.RemovePlayerByPlayerId(playerId)
    else
        -- Log:Error("Player does not exist for gid[%s] workerIdx[%d]", clientGID, workerIdx)
    end
end

-- 示例请求处理
---@param message ProtoLua_ProtoCSReqExample
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_EXAMPLE] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)

    ---@type ProtoLua_ProtoCSResExample
    local t = { testContext = message.testContext }

    if player == nil then
        t.testContext = "Not Logined In"
        MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_EXAMPLE, t)

        -- 关闭客户端的连接
        ---@type ProtoLua_ProtoTunnelOtherLuaVM2WorkerCloseClientConnection
        local ProtoTunnelOtherLuaVM2WorkerCloseClientConnection = { gid = clientGID, workerIdx = workerIdx }
        MsgHandler:Send2Client(
            clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_TUNNEL_OTHERLUAVM2WORKER_CLOSE_CLIENT_CONNECTION,
            ProtoTunnelOtherLuaVM2WorkerCloseClientConnection
        )

        return
    end

    -- Log:Error("Recv Player from clientGID[%s] workerIdx[%d] PROTO_CMD_CS_REQ_EXAMPLE message: %s", clientGID,
    --     workerIdx, self:DebugTableToString(message));

    t.testContext = message.testContext

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_EXAMPLE, t)
end

-- 登录请求处理
---@param message ProtoLua_ProtoCSReqLogin
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_LOGIN] = function (playerId, clientGID, workerIdx, cmd, message)
    -- 检查其是否有了玩家对象 有玩家对象的肯定是重复登录了
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player ~= nil then
        Log:Error("Player already exists for gid[%s] workerIdx[%d]", clientGID, workerIdx)
        return
    end

    ---@type ProtoLua_ProtoCSResLogin
    local res = { ret = ProtoLua_ProtoErrCode.ERR_SERVICE_SAFESTOPED, sessionId = playerId }

    if MapSvr.IsSafeStop() == true then
        MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_LOGIN, res)
        return
    end

    -- Log:Error("Login Request from clientGID[%s] workerIdx[%d] message: %s", clientGID,
    --     workerIdx, self:DebugTableToString(message));

    -- 查userId是否已经有了玩家对象 有的话说明重复登录了
    local playerByUserId = PlayerMgr.GetPlayerByUserId(message.userId)
    if playerByUserId ~= nil then
        Log:Error("UserId[%s] already logged in", message.userId)
        return
    end

    if Validator.IsEmptyString(message.userId) or Validator.IsEmptyString(message.password) then
        res.ret = ProtoLua_ProtoErrCode.ERR_USERID_INPUT_INVALID
        MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_LOGIN, res)
        return
    end

    -- 向dbsvrgo通过userId查用户DB数据
    ---@type ProtoLua_SelectDbUserRecordLoginReq
    local selectDbUserRecordLoginReq = {
        playerId = playerId,
        clientGID = clientGID,
        workerIdx = workerIdx,
        userId = message.userId,
        password = message.password
    }

    MsgHandler:Send2IPC(
        avant:GetDBSvrGoAppID(), ProtoLua_ProtoCmd.PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_LOGIN_REQ,
        selectDbUserRecordLoginReq
    )
end

-- PROTO_CMD_CS_REQ_MAP_PING 地图内客户端心跳请求
---@param message ProtoLua_ProtoCSReqMapPing
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_MAP_PING] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    local serverTimeMS = player:GetComponents().map:PingReq()

    ---@type ProtoLua_ProtoCSResMapPong
    local res = { clientTime = message.clientTime, serverTime = tostring(serverTimeMS) }

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_MAP_PONG, res)
end

--- ROTO_CMD_CS_REQ_MAP_INPUT 地图内客户端上报输入
---@param message ProtoLua_ProtoCSReqMapInput
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_MAP_INPUT] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    player:GetComponents().map:MapInputReq(message)
end

--- PROTO_CMD_CS_MAP_ENTER_REQ 进入地图请求
---@param message ProtoLua_ProtoCSMapEnterReq
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP_ENTER_REQ] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end
    local enterMapRet = player:GetComponents().map:MapEnterReq(message.mapId)

    ---@type ProtoLua_ProtoCSMapEnterRes
    local res = { ret = enterMapRet, mapId = message.mapId }

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP_ENTER_RES, res)
end

--- PROTO_CMD_CS_MAP_LEAVE_REQ 离开地图请求
---@param message ProtoLua_ProtoCSMapLeaveReq
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP_LEAVE_REQ] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end
    local leaveMapRet = player:GetComponents().map:MapLeaveReq()

    ---@type ProtoLua_ProtoCSMapLeaveRes
    local res = { ret = leaveMapRet }

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP_LEAVE_RES, res)
end

--- PROTO_CMD_CS_REQ_MAP3D_PING 地图3D内心跳请求
---@param message ProtoLua_ProtoCSReqMap3DPing
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_MAP3D_PING] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    local serverTimeMS = player:GetComponents().map3d:PingReq()

    ---@type ProtoLua_ProtoCSResMap3DPong
    local res = { clientTime = message.clientTime, serverTime = tostring(serverTimeMS) }

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_MAP3D_PONG, res)
end

--- PROTO_CMD_CS_REQ_MAP3D_INPUT 地图3D内客户端上报输入
---@param message ProtoLua_ProtoCSReqMap3DInput
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_MAP3D_INPUT] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    player:GetComponents().map3d:MapInputReq(message)
end

--- PROTO_CMD_CS_MAP3D_ENTER_REQ 进入地图3D请求
---@param message ProtoLua_ProtoCSMap3DEnterReq
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_ENTER_REQ] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    local enterMapRet = player:GetComponents().map3d:MapEnterReq(message.mapId)

    ---@type ProtoLua_ProtoCSMap3DEnterRes
    local res = { ret = enterMapRet, mapId = message.mapId }

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_ENTER_RES, res)
end

--- PROTO_CMD_CS_MAP3D_LEAVE_REQ 离开地图3D请求
---@param message ProtoLua_ProtoCSMap3DLeaveReq
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_LEAVE_REQ] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end
    local leaveMapRet = player:GetComponents().map3d:MapLeaveReq()

    ---@type ProtoLua_ProtoCSMap3DLeaveRes
    local res = { ret = leaveMapRet }

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_LEAVE_RES, res)
end

--- PROTO_CMD_CS_REQ_MAP3D_SHOOT 3D地图射击请求
---@param message ProtoLua_ProtoCSReqMap3DShoot
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_MAP3D_SHOOT] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    player:GetComponents().map3d:MapShootReq(message)

    ---@type ProtoLua_ProtoCSResMap3DShoot
    local res = { ret = 0, damage = 100 }

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_MAP3D_SHOOT, res)
end

--- PROTO_CMD_CS_REQ_MAP3D_CHAT 3D地图房间聊天请求
--- 发送者身份取自会话playerId, 服务器广播给房间内所有玩家(含发送者自己)
---@param message ProtoLua_ProtoCSReqMap3DChat
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_MAP3D_CHAT] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    player:GetComponents().map3d:MapChatReq(message)
end

--- PROTO_CMD_CS_REQ_MAP3D_SLEEP 3D地图上下床请求
--- 请求者身份取自会话playerId, 服务器权威校验占用/距离后广播状态
---@param message ProtoLua_ProtoCSReqMap3DSleep
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_MAP3D_SLEEP] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    local player = PlayerMgr.GetPlayerByPlayerId(playerId)
    if player == nil then
        return
    end

    player:GetComponents().map3d:MapSleepReq(message)
end

---@param message ProtoLua_ProtoCSReqCreateUser
MsgHandlerFromClient[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_CREATE_USER] = function (
    playerId, clientGID, workerIdx, cmd, message
)
    if MapSvr.IsSafeStop() == true then
        ---@type ProtoLua_ProtoCSResCreateUser
        local res = avant.CreateNewProtobufByCmd(ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_CREATE_USER)
        res.ret = ProtoLua_ProtoErrCode.ERR_SERVICE_SAFESTOPED

        MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_CREATE_USER, res)
        return
    end

    ---@type integer
    local ret = ProtoLua_ProtoErrCode.OK

    ret = Validator.UserIdValidator(message.userId)

    if ret == ProtoLua_ProtoErrCode.OK then
        ret = Validator.UserPasswordValidator(message.password)
    end

    if ret ~= ProtoLua_ProtoErrCode.OK then
        ---@type ProtoLua_ProtoCSResCreateUser
        local res = avant.CreateNewProtobufByCmd(ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_CREATE_USER)
        res.ret = ret

        return MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_CREATE_USER, res)
    end

    local TimeMgr = require("TimeMgrLogic")

    ---@type ProtoLua_InsertDbUserRecordReq
    local insertDbUserRecordReq = avant.CreateNewProtobufByCmd(ProtoLua_ProtoCmd
            .PROTO_CMD_DBSVRGO_INSERT_DBUSERRECORD_REQ)

    insertDbUserRecordReq.clientGID = clientGID
    insertDbUserRecordReq.workerIdx = workerIdx
    insertDbUserRecordReq.dbUserRecord.id = tostring(TimeMgr.GetMS())
    insertDbUserRecordReq.dbUserRecord.user_id = message.userId
    insertDbUserRecordReq.dbUserRecord.password = message.password

    MsgHandler:Send2IPC(
        avant:GetDBSvrGoAppID(), ProtoLua_ProtoCmd.PROTO_CMD_DBSVRGO_INSERT_DBUSERRECORD_REQ, insertDbUserRecordReq
    )
end

return MsgHandlerFromClient
