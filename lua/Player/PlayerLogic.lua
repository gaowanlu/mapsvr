-- PlayerLogic.lua logic script, reloadable

---@class Player: PlayerType
local Player = require("PlayerData")

local Log = require("Log")
local PlayerCmptInfo = require("PlayerCmptInfoLogic")
local PlayerCmptBag = require("PlayerCmptBagLogic")
local PlayerCmptMap = require("PlayerCmptMapLogic")
local PlayerCmptMap3D = require("PlayerCmptMap3DLogic")
local PlayerCmptFSRoom = require("PlayerCmptFSRoomLogic")
local ConfigTableMgr = require("ConfigTableMgrLogic")

--- Player构造工厂
---@param playerId string
---@return Player
function Player.new(playerId)
    -- 创建一个Player对象 setmetatable({},{__index=Player})
    ---@type Player
    local self = setmetatable({}, Player)

    -- 模拟玩家的DB字段
    self.PlayerCacheData = { id = playerId, clientGID = "0", workerIdx = -1, userId = "" }

    self.DbUserRecord = nil

    -- Player下组件挂载
    self.components = {
        info   = PlayerCmptInfo.new(self),
        bag    = PlayerCmptBag.new(self),
        map    = PlayerCmptMap.new(self),
        map3d  = PlayerCmptMap3D.new(self),
        FSRoom = PlayerCmptFSRoom.new(self)
    }

    return self
end

---@return PlayerComponentsType
function Player:GetComponents()
    return self.components
end

---@return string
function Player:GetPlayerID()
    return self.PlayerCacheData.id
end

---@return ProtoLua_DbUserRecord
function Player:GetDbUserRecord()
    return self.DbUserRecord
end

---@return string
function Player:GetClientGID()
    return self.PlayerCacheData.clientGID
end

---@return integer
function Player:GetWorkerIdx()
    return self.PlayerCacheData.workerIdx
end

---@return string
function Player:GetUserId()
    return self.PlayerCacheData.userId
end

---@param clientGID string
function Player:SetClientGID(clientGID)
    self.PlayerCacheData.clientGID = clientGID
end

---@param workerIdx integer
function Player:SetWorkerIdx(workerIdx)
    self.PlayerCacheData.workerIdx = workerIdx
end

---@param userId string
function Player:SetUserId(userId)
    self.PlayerCacheData.userId = userId
end

function Player:OnTick()
    for _, comp in pairs(self.components) do
        comp:OnTick()
    end
end

---@param DbUserRecord ProtoLua_DbUserRecord
function Player:OnLogin(DbUserRecord)
    self.DbUserRecord = DbUserRecord
    for _, comp in pairs(self.components) do
        comp:OnLogin()
    end
end

function Player:OnLogout()
    local MsgHandler = require("MsgHandlerLogic")

    for _, comp in pairs(self.components) do
        comp:OnLogout()
    end

    local DbUserRecord = self:GetDbUserRecord()
    if DbUserRecord ~= nil then
        Log:Error("logout save to database for playerId %s userId %s", self:GetPlayerID(), self:GetUserId())

        ---@diagnostic disable-next-line: assign-type-mismatch
        ---@type ProtoLua_DbOpType
        local op = ProtoLua_DbOpType.OP_REPLACE

        DbUserRecord.op = op -- replace
        MsgHandler:Send2IPC(
            avant:GetDBSvrGoAppID(), ProtoLua_ProtoCmd.PROTO_CMD_DBSVRGO_WRITE_DBUSERRECORD_REQ, DbUserRecord
        )
    end
end

function Player:OnSafeStop()
    local MsgHandler = require("MsgHandlerLogic")

    -- 关闭客户端的连接
    ---@type ProtoLua_ProtoTunnelOtherLuaVM2WorkerCloseClientConnection
    local ProtoTunnelOtherLuaVM2WorkerCloseClientConnection = {
        gid = self:GetClientGID(),
        workerIdx = self:GetWorkerIdx()
    }

    MsgHandler:Send2Client(
        ProtoTunnelOtherLuaVM2WorkerCloseClientConnection.gid,
        ProtoTunnelOtherLuaVM2WorkerCloseClientConnection.workerIdx,
        ProtoLua_ProtoCmd.PROTO_CMD_TUNNEL_OTHERLUAVM2WORKER_CLOSE_CLIENT_CONNECTION,
        ProtoTunnelOtherLuaVM2WorkerCloseClientConnection
    )
    return
end

return Player
