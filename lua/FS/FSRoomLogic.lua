---@class FSRoom:FSRoomType
---@field STATE_WAITING string
---@field STATE_READY string
---@field STATE_RUNNING string
---@field STATE_FINISHED string
---@field state string
---@field lastUpdateStateTime integer
---@field maxPlayers integer
---@field map FSRoomMap
---@field battle FSRoomBattle
local FSRoom = require("FSRoomData")
local Log = require("Log")
local FSRoomMap = require("FSRoomMapLogic");
local FSRoomBattle = require("FSRoomBattleLogic");

-- Room states
FSRoom.STATE_WAITING = "waiting"
FSRoom.STATE_READY = "ready"
FSRoom.STATE_RUNNING = "running"
FSRoom.STATE_FINISHED = "finished"

-- 构造新的FSRoom对象
---@param roomId integer
---@param maxPlayers integer
---@return FSRoom
function FSRoom.new(roomId, maxPlayers)
    ---@type FSRoom
    local self = setmetatable({}, FSRoom); -- 本质是 setmetatable({},{_index=FSRoom})

    -- 模拟FSRoom的DB字段
    self.FSRoomDbData = {
        id = roomId,
        name = "FSRoom_" .. tostring(roomId)
    };

    self.roomPlayers = {};

    self.state = FSRoom.STATE_WAITING;
    self.lastUpdateStateTime = 0;
    self.maxPlayers = maxPlayers;

    -- 初始化房间地图
    self.map = FSRoomMap.new(100, 100);
    self.map:GenerateBorderWalls();
    self.map:GenerateRandomObstacles(10);

    -- 初始化Battle
    self.battle = FSRoomBattle.new(self, self.map);

    return self
end

---@return string
function FSRoom:GetState()
    return self.state;
end

---@return FSRoomDbDataType
function FSRoom:GetFSRoomDbData()
    return self.FSRoomDbData;
end

function FSRoom:OnTick()
    -- Log:Error("FSRoom %d", self:GetFSRoomDbData().id)
end

---@param playerId string
---@param userId string
function FSRoom:AddPlayerToRoom(playerId, userId)
    -- TODO
end

---@param playerId string
---@param userId string
function FSRoom:RemovePlayerFromRoom(playerId, userId)
    -- TODO
end

---@param userId string
---@return FSRoomPlayer|nil
function FSRoom:GetRoomPlayer(userId)
    -- TODO
end

---被FSRoomMgr删除前调用
function FSRoom:DeleteBefore()
end

return FSRoom;
