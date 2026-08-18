---@class PlayerCmptMap3DType: PlayerCmptBase
---@field nowMapId integer

local PlayerCmptBase = require("PlayerCmptBaseLogic")

---@class PlayerCmptMap3D: PlayerCmptMap3DType
local PlayerCmptMap3D = require("PlayerCmptMap3DData")

local Log = require("Log")
local TimeMgr = require("TimeMgrLogic")

local Map3DMgr = require("Map3DMgrLogic")

---@param owner Player
---@return PlayerCmptMap3D
function PlayerCmptMap3D.new(owner)
    local self = setmetatable(PlayerCmptBase.new(owner), PlayerCmptMap3D)

    self.nowMapId = -1

    return self
end

function PlayerCmptMap3D:OnTick()
end

function PlayerCmptMap3D:OnLogin()
    self:LeaveCurrMap()
end

function PlayerCmptMap3D:OnLogout()
    self:LeaveCurrMap()
end

---@return boolean
function PlayerCmptMap3D:HasInMap()
    return self.nowMapId > 0
end

function PlayerCmptMap3D:LeaveCurrMap()
    if self:HasInMap() then
        local map = Map3DMgr.GetMap(self.nowMapId)
        if map == nil then
            return
        end
        if map:PlayerExitMap(self:GetPlayer():GetUserId()) then
            self.nowMapId = -1
        end
    end
end

---@param mapId integer
---@return integer
function PlayerCmptMap3D:EnterNewMap(mapId)
    local map = Map3DMgr.GetMap(mapId)
    if map == nil then
        return ProtoLua_ProtoErrCode.ERR_TARGET_MAP_NOT_FOUND
    end

    if map:PlayerJoinMap(self:GetPlayer():GetUserId()) ~= true then
        return ProtoLua_ProtoErrCode.ERR_UNKNOW
    end

    local mapPlayer = map:GetMapPlayerByUserId(self:GetPlayer():GetUserId())
    if mapPlayer == nil then
        Log:Error("mapPlayer == nil")
        return ProtoLua_ProtoErrCode.ERR_UNKNOW
    end

    -- 设置玩家所在的地图ID
    self.nowMapId = mapId

    -- 进地图直接发一次Map3DInitData PROTO_CMD_CS_MAP3D_NOTIFY_INIT_DATA
    ---@type ProtoLua_ProtoCSMap3DNotifyInitData
    local protoCSMap3DNotifyInitData = {
        userId = self:GetPlayer():GetUserId(),
        x = math.ceil(mapPlayer.pos.x),
        y = math.ceil(mapPlayer.pos.y),
        z = math.ceil(mapPlayer.pos.z),
        serverTime = tostring(map:GetLastTickTimeMS()),
        xSize = map:GetSize().x,
        ySize = map:GetSize().y,
        zSize = map:GetSize().z,
        mapId = map:GetMapId()
    }

    local MsgHandler = require("MsgHandlerLogic")
    MsgHandler:Send2Client(
        self:GetPlayer():GetClientGID(), self:GetPlayer():GetWorkerIdx(),
        ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_INIT_DATA, protoCSMap3DNotifyInitData
    )

    -- 下发地图墙体/建筑配置, 客户端据此渲染地图并做本地预测
    -- PROTO_CMD_CS_MAP3D_NOTIFY_MAP_DATA
    ---@type ProtoLua_ProtoCSMap3DNotifyMapData
    local mapDataPayload = map:GetMapDataPayload()
    MsgHandler:Send2Client(
        self:GetPlayer():GetClientGID(), self:GetPlayer():GetWorkerIdx(),
        ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_MAP_DATA, mapDataPayload
    )

    return ProtoLua_ProtoErrCode.OK
end

---@param mapId integer
---@return integer
function PlayerCmptMap3D:MapEnterReq(mapId)
    -- 只要请求加入地图就离开当前地图
    self:LeaveCurrMap()
    -- 加入目标地图
    return self:EnterNewMap(mapId)
end

---@return integer
function PlayerCmptMap3D:MapLeaveReq()
    self:LeaveCurrMap()
    return ProtoLua_ProtoErrCode.OK
end

---@return integer
function PlayerCmptMap3D:PingReq()
    if self:HasInMap() then
        local currMap = Map3DMgr.GetMap(self.nowMapId)
        if currMap == nil then
            return TimeMgr.GetMS()
        end
        return currMap:GetLastTickTimeMS()
    end
    return TimeMgr.GetMS()
end

---@param message ProtoLua_ProtoCSReqMap3DInput
function PlayerCmptMap3D:MapInputReq(message)
    -- 如果目前没有加入任何地图则直接拒绝处理
    if false == self:HasInMap() then
        return
    end

    local currMap = Map3DMgr.GetMap(self.nowMapId)
    if currMap == nil then
        return
    end

    local dirX = message.dirX
    local dirY = message.dirY
    local dirZ = message.dirZ
    local seq = message.seq
    local clientTime = message.clientTime

    currMap:MapPlayerInput(self:GetPlayer():GetUserId(), dirX, dirY, dirZ, seq, clientTime)
end

---@param message ProtoLua_ProtoCSReqMap3DShoot
function PlayerCmptMap3D:MapShootReq(message)
    -- 如果目前没有加入任何地图则直接拒绝处理
    if false == self:HasInMap() then
        return
    end

    ---@type Map3D
    local currMap = Map3DMgr.GetMap(self.nowMapId)
    if currMap == nil then
        return
    end

    currMap:PlayerShoot(
        self:GetPlayer():GetUserId(), message.dirX, message.dirY, message.dirZ, message.shootDist, message.clientTime
    )
end

return PlayerCmptMap3D
