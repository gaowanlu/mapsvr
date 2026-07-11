local PlayerCmptBase = require("PlayerCmptBaseLogic")
local Log = require("Log")

---@class PlayerCmptInfoType:PlayerCmptBase

---@class PlayerCmptInfo:PlayerCmptInfoType
local PlayerCmptInfo = require("PlayerCmptInfoData")

---@param owner Player
---@return PlayerCmptInfo
function PlayerCmptInfo.new(owner)
    -- 本质是 setmetatable(PlayerCmptBase.new(owner), {__index=PlayerCmptInfo})
    local self = setmetatable(PlayerCmptBase.new(owner), PlayerCmptInfo)
    return self
end

---@return ProtoLua_DbPlayerBaseInfo
function PlayerCmptInfo:GetDbBaseInfoData()
    local dbUserRecord = self.owner:GetDbUserRecord();
    return dbUserRecord.base_info;
end

---@param lv integer
function PlayerCmptInfo:SetLevel(lv)
    local dbData = self:GetDbBaseInfoData()
    dbData.level = lv
end

function PlayerCmptInfo:UpLevel()
    local dbData = self:GetDbBaseInfoData()
    dbData.level = dbData.level + 1
end

---@return integer
function PlayerCmptInfo:GetLevel()
    local dbData = self:GetDbBaseInfoData()
    return dbData.level
end

-- PlayerCmptInfo.OnTick = nil
-- 如果热更新把OnTick置为nil则会调用PlayerCmptBase的OnTick
function PlayerCmptInfo:OnTick()
    -- 调试测试代码 模拟玩家不断升级
    self:UpLevel()

    if (self:GetLevel() >= 100) then
        self:SetLevel(0)
    end

    -- Log:Error("PlayerCmptInfo userId %s Level %d", self:GetPlayer():GetUserId(), self:GetLevel())
end

function PlayerCmptInfo:OnLogin()
    Log:Error("PlayerCmptInfo:OnLogin userId %s Level %d", self:GetPlayer():GetUserId(), self:GetLevel())
end

function PlayerCmptInfo:OnLogout()
    Log:Error("PlayerCmptInfo:OnLogout userId %s Level %d", self:GetPlayer():GetUserId(), self:GetLevel())
end

return PlayerCmptInfo
