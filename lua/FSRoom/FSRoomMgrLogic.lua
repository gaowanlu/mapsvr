---@class FSRoomMgr
---@field rooms table<integer,FSRoom>
---@field lastCleanupTime number
local FSRoomMgr = require("FSRoomMgrData");

local FSRoom = require("FSRoomLogic");
local Log = require("Log");
local TimeMgr = require("TimeMgrLogic")

FSRoomMgr.rooms = FSRoomMgr.rooms or {};
FSRoomMgr.lastCleanupTime = FSRoomMgr.lastCleanupTime or 0;

---@param roomId integer 房间号
---@return FSRoom|nil 房间
function FSRoomMgr.CreateRoom(roomId)
    if FSRoomMgr.rooms[roomId] then
        Log:Error("Already exists Room roomId %d", roomId)
        return nil
    end

    Log:Error("Create new FSRoom roomId[%d]", roomId);
    local newRoom = FSRoom.new(roomId, 2);
    FSRoomMgr.rooms[roomId] = newRoom;
    return newRoom;
end

---@param roomId number 房间号
---@return FSRoom 房间
function FSRoomMgr.GetRoom(roomId)
    return FSRoomMgr.rooms[roomId]
end

---@param roomId number 房间号
---@return boolean 删除是否成功
function FSRoomMgr.DeleteRoom(roomId)
    ---@type FSRoom|nil
    local room = FSRoomMgr.rooms[roomId];

    if room ~= nil then
        room:DeleteBefore();
        FSRoomMgr.rooms[roomId] = nil
        Log:Error("RemoveRoom from FSRoomMgr roomId %d", roomId)
        return true;
    end
    return false;
end

function FSRoomMgr.OnTick()
    local currTimeS = TimeMgr:GetS();

    for roomId, roomItem in pairs(FSRoomMgr.rooms) do
        ---@type FSRoom
        local roomObj = roomItem;

        roomObj:OnTick();
    end

    if currTimeS - FSRoomMgr.lastCleanupTime > 20 then
        FSRoomMgr.lastCleanupTime = currTimeS;
        FSRoomMgr.CleanupFinishedRooms(currTimeS);
    end
end

function FSRoomMgr.OnStop()
    Log:Error("FSRoomMgr OnStop");
    for roomId, roomObj in pairs(FSRoomMgr.rooms) do
        FSRoomMgr.DeleteRoom(roomId);
    end
end

function FSRoomMgr.OnSafeStop()
    Log:Error("FSRoomMgr.OnSafeStop()");
end

function FSRoomMgr.OnReload()
    local ConfigTableMgr = require("ConfigTableMgrLogic");
    local roomCount = ConfigTableMgr.FSRoomConfig:GetRoomIdCount();

    for i = 1, roomCount, 1 do
        local roomId = ConfigTableMgr.FSRoomConfig:GetRoomIdAt(i);

        -- 初始化一个帧同步房间
        FSRoomMgr.CreateRoom(roomId);
    end
end

--- 找一个状态为WAITING人数还没满的房间
---@return FSRoom|nil
function FSRoomMgr.FindAvailableRoom()
    for _, room in pairs(FSRoomMgr.rooms) do
        if room.state == FSRoom.STATE_WAITING and #room.roomPlayers < room.maxPlayers then
            return room;
        end
    end
    return nil;
end

--- 释放该释放的Room
---@param currTimeS number
function FSRoomMgr.CleanupFinishedRooms(currTimeS)
    local toDelete = {};
    for roomId, room in pairs(FSRoomMgr.rooms) do
        if room.state == FSRoom.STATE_FINISHED and #room.roomPlayers == 0 then
            if currTimeS - room.lastUpdateStateTime > 3 * 60 then
                table.insert(toDelete, roomId);
            end
        end
    end

    for _, roomId in ipairs(toDelete) do
        FSRoomMgr.DeleteRoom(roomId);
    end
end

return FSRoomMgr;
