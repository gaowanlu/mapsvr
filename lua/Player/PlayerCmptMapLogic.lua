---@class PlayerCmptMapType: PlayerCmptBase
---@field nowMapId integer

local PlayerCmptBase = require("PlayerCmptBaseLogic")

---@class PlayerCmptMap: PlayerCmptMapType
local PlayerCmptMap = require("PlayerCmptMapData")

local Log = require("Log")
local TimeMgr = require("TimeMgrLogic")

local MapMgr = require("MapMgrLogic")

---@param owner Player
---@return PlayerCmptMap
function PlayerCmptMap.new(owner)
    -- 本质是 setmetatable(PlayerCmptBase.new(owner), {__index=PlayerCmptMap})
    local self = setmetatable(PlayerCmptBase.new(owner), PlayerCmptMap)

    -- 组件内数据
    self.nowMapId = -1

    return self
end

function PlayerCmptMap:OnTick()
end

function PlayerCmptMap:OnLogin()
    self:LeaveCurrMap()
end

function PlayerCmptMap:OnLogout()
    self:LeaveCurrMap()
end

---@return boolean
function PlayerCmptMap:HasInMap()
    return self.nowMapId > 0
end

function PlayerCmptMap:LeaveCurrMap()
    if self:HasInMap() then
        local map = MapMgr.GetMap(self.nowMapId)
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
function PlayerCmptMap:EnterNewMap(mapId)
    local map = MapMgr.GetMap(mapId)
    if map == nil then
        return ProtoLua_ProtoErrCode.ERR_TARGET_MAP_NOT_FOUND
    end
    if map:PlayerJoinMap(self:GetPlayer():GetPlayerID(), self:GetPlayer():GetUserId()) ~= true then
        return ProtoLua_ProtoErrCode.ERR_UNKNOW
    end

    local mapPlayer = map:GetMapPlayerByUserId(self:GetPlayer():GetUserId())
    if mapPlayer == nil then
        Log:Error("mapPlayer == nil")
        return ProtoLua_ProtoErrCode.ERR_UNKNOW
    end

    -- 设置玩家所在的地图ID
    self.nowMapId = mapId

    -- 进入地图直接发一次MapInitData
    ---@type ProtoLua_ProtoCSMapNotifyInitData
    local protoCSMapNotifyInitData = {
        userId = self:GetPlayer():GetUserId(),
        x = math.ceil(mapPlayer.x),
        y = math.ceil(mapPlayer.y),
        serverTime = tostring(map:GetLastTickTimeMS()),
        tileSize = map:GetTileSize(),
        width = map:GetTileMapWidth(),
        height = map:GetTileMapHeight(),
        mapId = map:GetMapId()
    }
    local MsgHandler = require("MsgHandlerLogic")
    MsgHandler:Send2Client(
        self:GetPlayer():GetClientGID(), self:GetPlayer():GetWorkerIdx(),
        ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP_NOTIFY_INIT_DATA, protoCSMapNotifyInitData
    )

    return ProtoLua_ProtoErrCode.OK
end

---@param mapId integer
---@return integer
function PlayerCmptMap:MapEnterReq(mapId)
    -- 只要请求加入地图就离开当前地图
    self:LeaveCurrMap()
    -- 加入目标地图
    return self:EnterNewMap(mapId)
end

---@return integer
function PlayerCmptMap:MapLeaveReq()
    self:LeaveCurrMap()
    return ProtoLua_ProtoErrCode.OK
end

---@return integer
function PlayerCmptMap:PingReq()
    if self:HasInMap() then
        local currMap = MapMgr.GetMap(self.nowMapId)
        if currMap == nil then
            return TimeMgr.GetMS()
        end
        return currMap:GetLastTickTimeMS()
    end
    return TimeMgr.GetMS()
end

---@param message ProtoLua_ProtoCSReqMapInput
function PlayerCmptMap:MapInputReq(message)
    -- 如果目前没有加入任何地图则直接拒绝处理
    if false == self:HasInMap() then
        return
    end

    local currMap = MapMgr.GetMap(self.nowMapId)
    if currMap == nil then
        return
    end

    local dirX = message.dirX
    local dirY = message.dirY
    local seq = message.seq
    local clientTime = message.clientTime

    currMap:MapPlayerInput(self:GetPlayer():GetUserId(), dirX, dirY, seq, clientTime)
end

return PlayerCmptMap
