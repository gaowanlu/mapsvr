---@class PlayerCmptFSRoomType: PlayerCmptBase
---@field nowRoomId integer

local PlayerCmptBase = require("PlayerCmptBaseLogic")

---@class PlayerCmptFSRoom: PlayerCmptFSRoomType
local PlayerCmptFSRoom = require("PlayerCmptFSRoomData")

local Log = require("Log")
local TimeMgr = require("TimeMgrLogic")

---@param owner Player
---@return PlayerCmptFSRoom
function PlayerCmptFSRoom.new(owner)
    local self = setmetatable(PlayerCmptBase.new(owner), PlayerCmptFSRoom)

    -- 组件内数据
    self.nowRoomId = -1

    return self
end

function PlayerCmptFSRoom:OnTick()
    -- Log:Error("PlayerCmptFSRoom userId %s", self:GetPlayer():GetUserId())
end

function PlayerCmptFSRoom:OnLogin()
end

function PlayerCmptFSRoom:OnLogout()
end

return PlayerCmptFSRoom
