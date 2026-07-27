---@class PlayerCmptBaseType
---@field owner Player

---@class PlayerCmptBase: PlayerCmptBaseType
local PlayerCmptBase = require("PlayerCmptBaseData")
local Log = require("Log")

---@param owner Player
---@return PlayerCmptBase
function PlayerCmptBase.new(owner)
    -- 本质是 setmetatable({}, {__index=PlayerCmptBase})
    local self = setmetatable({}, PlayerCmptBase)
    self.owner = owner
    return self
end

function PlayerCmptBase:OnTick()
    -- 可选重写
    -- Log:Error("PlayerCmptBase:OnTick")
end

function PlayerCmptBase:OnLogin()
    -- 可选重写
end

function PlayerCmptBase:OnLogout()
    -- 可选重写
end

function PlayerCmptBase:OnSave()
    -- 可选重写
end

---@return Player
function PlayerCmptBase:GetPlayer()
    return self.owner
end

return PlayerCmptBase
