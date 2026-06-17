---@class PlayerMgr:PlayerMgrType
local PlayerMgr = require("PlayerMgrData");
local Player = require("PlayerLogic")
local Log = require("Log")

PlayerMgr["players"] = PlayerMgr["players"] or {}
---@type table<string,string>
PlayerMgr["userIdToPlayerId"] = PlayerMgr["userIdToPlayerId"] or {}
---@type table<string,string>
PlayerMgr["playerIdToUserId"] = PlayerMgr["playerIdToUserId"] or {}
PlayerMgr["playerIdOnlineList"] = PlayerMgr["playerIdOnlineList"] or {}

---@param playerId string
---@return Player
function PlayerMgr.CreatePlayer(playerId)
    if PlayerMgr.players[playerId] then
        Log:Error("Already exists Player playerId %s", playerId)
        return PlayerMgr.players[playerId]
    end

    -- Log:Error("Create new Player playerId[%s]", playerId)
    local player = Player.new(playerId)
    PlayerMgr.players[playerId] = player
    return player
end

---@param playerId string
function PlayerMgr.SetPlayerIdOnline(playerId)
    PlayerMgr.playerIdOnlineList[playerId] = true
end

---@param playerId string
function PlayerMgr.SetPlayerIdOffline(playerId)
    PlayerMgr.playerIdOnlineList[playerId] = nil
end

---@param playerId string
---@return boolean
function PlayerMgr.IsPlayerIdOnline(playerId)
    return PlayerMgr.playerIdOnlineList[playerId] ~= nil;
end

---@param playerId string
---@return Player
function PlayerMgr.GetPlayerByPlayerId(playerId)
    return PlayerMgr.players[playerId]
end

---@param playerId string
function PlayerMgr.RemovePlayerByPlayerId(playerId)
    PlayerMgr.players[playerId] = nil
    local userId = PlayerMgr.playerIdToUserId[playerId]
    if userId ~= nil then
        PlayerMgr.userIdToPlayerId[userId] = nil
        PlayerMgr.playerIdToUserId[playerId] = nil
    end

    -- Log:Error("RemovePlayerByPlayerId from PlayerMgr playerId %s userId %s", playerId, userId or "nil");
end

---@param userId string
---@param playerId string
function PlayerMgr.BindUserIdAndPlayerId(userId, playerId)
    if nil == PlayerMgr.GetPlayerByPlayerId(playerId) then
        Log:Error("BindUserIdAndPlayerId failed, playerId %s not exists", playerId);
        return
    end

    PlayerMgr.userIdToPlayerId[userId] = playerId
    PlayerMgr.playerIdToUserId[playerId] = userId
end

---@param userId string
function PlayerMgr.GetPlayerByUserId(userId)
    local playerId = PlayerMgr.userIdToPlayerId[userId]
    if playerId == nil then
        return nil
    end
    return PlayerMgr.GetPlayerByPlayerId(playerId)
end

function PlayerMgr.OnTick()
    -- Log:Error("OnTickAll Player")
    for _, playerItem in pairs(PlayerMgr.players) do
        ---@type Player
        local player = playerItem;
        player:OnTick()
    end
end

function PlayerMgr.OnStop()
    Log:Error("PlayerMgr OnStop")
    for playerId, player in pairs(PlayerMgr.players) do
        PlayerMgr.RemovePlayerByPlayerId(playerId);
    end
end

function PlayerMgr.OnSafeStop()
    Log:Error("PlayerMgr.OnSafeStop()");


    for playerId, playerItem in pairs(PlayerMgr.players) do
        ---@type Player
        local player = playerItem;

        player:OnSafeStop();
    end
end

return PlayerMgr
