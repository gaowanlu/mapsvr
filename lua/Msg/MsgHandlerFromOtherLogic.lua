local MsgHandler = require("MsgHandlerLogic")
local MapSvr = require("MapSvr");
local Log = require("Log");
local Debug = require("DebugLogic");

---@type table<number,function>
MsgHandlerFromOther = {};

---@param message ProtoLua_ProtoCSReqExample
MsgHandlerFromOther[ProtoLua_ProtoCmd.PROTO_CMD_CS_REQ_EXAMPLE] = function(cmd, message, app_id)
    ---@type ProtoLua_ProtoCSResExample
    local t = {
        testContext = message.testContext
    }

    -- 原逻辑是 Send2IPC 但发送的是 message，而不是 t
    MsgHandler:Send2IPC(app_id, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_EXAMPLE, message)
end

---@param message ProtoLua_SelectDbUserRecordRes
MsgHandlerFromOther[ProtoLua_ProtoCmd.PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_RES] = function(cmd, message, app_id)
    local str = Debug:DebugTableToString(message)
    if str ~= nil then
        Log:Error("%s", str);
    end
end

---@param message ProtoLua_InsertDbUserRecordRes
MsgHandlerFromOther[ProtoLua_ProtoCmd.PROTO_CMD_DBSVRGO_INSERT_DBUSERRECORD_RES] = function(cmd, message, app_id)
    ---@type ProtoLua_ProtoCSResCreateUser
    local protoCSResCreateUser = {
        ret = message.ret,
        userId = message.dbUserRecord.user_id,
        password = message.dbUserRecord.password,
        userRecordID = message.dbUserRecord.id
    };

    MsgHandler:Send2Client(message.clientGID, message.workerIdx,
        ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_CREATE_USER, protoCSResCreateUser);
end

---@param message ProtoLua_SelectDbUserRecordLoginRes
MsgHandlerFromOther[ProtoLua_ProtoCmd.PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_LOGIN_RES] = function(cmd, message, app_id)
    local debugStr = Debug:DebugTableToString(message);
    if debugStr ~= nil then
        Log:Error("login callback %s", debugStr)
    end
    -- Log:Error("登录回调 PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_LOGIN_RES");

    local playerId = message.playerId;
    local clientGID = message.clientGID;
    local workerIdx = message.workerIdx;
    local userId = message.userId;

    if MapSvr.IsSafeStop() == true then
        ---@type ProtoLua_ProtoCSResLogin
        local res = {
            ret = ProtoLua_ProtoErrCode.EERR_SERVICE_SAFESTOPED,
            sessionId = playerId
        };
        MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_LOGIN, res);
        return;
    end

    -- 判断密码是否正确
    ---@type ProtoLua_ProtoCSResLogin
    local protoCSResLogin = {
        ret = ProtoLua_ProtoErrCode.OK,
        sessionId = playerId
    };

    local PlayerMgr = require("PlayerMgrLogic");

    if message.ret ~= 0 then
        protoCSResLogin.ret = ProtoLua_ProtoErrCode.ERR_USERID_OR_PASSWORD_NOTMATCH;
    elseif message.password ~= message.userRecord.password then
        protoCSResLogin.ret = ProtoLua_ProtoErrCode.ERR_USERID_OR_PASSWORD_NOTMATCH;
    elseif not PlayerMgr.IsPlayerIdOnline(playerId) then
        Log:Error("Login callback playerId %s not online", playerId);
    elseif nil ~= PlayerMgr.GetPlayerByPlayerId(playerId) then
        Log:Error("already online playerId %s", playerId);
    elseif nil ~= PlayerMgr.GetPlayerByUserId(userId) then
        Log:Error("already online userId %s", userId);
    else
        -- 创建玩家对象
        local createPlayer = PlayerMgr.CreatePlayer(playerId)
        if createPlayer == nil then
            Log:Error("Failed to create player for gid[%s] workerIdx[%d]", clientGID, workerIdx)
            return
        end

        -- 将 gid_workerIdx 和 userId 关联到 Player 对象上
        -- PlayerMgr 的 userId 与 playerId的双向映射
        PlayerMgr.BindUserIdAndPlayerId(userId, playerId);
        -- 设置 Player 的 userId、clientGID、workerIdx
        createPlayer:SetUserId(userId)
        createPlayer:SetClientGID(clientGID)
        createPlayer:SetWorkerIdx(workerIdx)

        MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_LOGIN, protoCSResLogin);

        ---@type ProtoLua_DbUserRecord
        local dbUserRecord = message.userRecord;
        -- 将数据库玩家数据赋值到其Player对象上
        createPlayer:OnLogin(dbUserRecord)
        return;
    end

    MsgHandler:Send2Client(clientGID, workerIdx, ProtoLua_ProtoCmd.PROTO_CMD_CS_RES_LOGIN, protoCSResLogin);
end

return MsgHandlerFromOther;
