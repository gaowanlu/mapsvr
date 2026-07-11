---@class FSRoomPlayer
---@field playerId string
---@field userId string userId
---@field name string 玩家名字
---@field room FSRoom player所属房间
---@field positionX number x坐标
---@field positionY number y坐标
---@field HP number 剩余血量
---@field maxHP number 最大血量
---@field MP number 技能蓝值
---@field maxMP number 最大技能蓝值
---@field skills table<integer,boolean> 技能
---@field skillCooldowns table<integer,number> 技能冷却时间
---@field lastFrameId number 客户端最后确认接收到的帧ID
---@field isReady boolean 是否已经就绪
---@field isConnected boolean 是否连接正常
---@field lastHeartbeat number 最后心跳上报时间
local FSRoomPlayer = require("FSRoomPlayerData")

local TimeMgr = require("TimeMgrLogic");

---构造新的FSRoomPlayer对象
---@param playerId string
---@param userId string
---@param room FSRoom
---@return FSRoomPlayer
function FSRoomPlayer.new(playerId, userId, room)
    ---@type FSRoomPlayer
    local newObj          = setmetatable({}, FSRoomPlayer);

    newObj.playerId       = playerId;
    newObj.userId         = userId;
    newObj.name           = "";
    newObj.room           = room;
    newObj.positionX      = 0;
    newObj.positionY      = 0;
    newObj.HP             = 0;
    newObj.maxHP          = 0;
    newObj.MP             = 0;
    newObj.maxMP          = 0;
    newObj.skills         = {};
    newObj.skillCooldowns = {};
    newObj.lastFrameId    = 0;
    newObj.isReady        = false;
    newObj.isConnected    = false;
    newObj.lastHeartbeat  = 0;

    return newObj;
end

---@param x number 新的x坐标
---@param y number 新的y坐标
function FSRoomPlayer:SetPosition(x, y)
    self.positionX = x;
    self.positionY = y;
end

---@return number x坐标,number y坐标
function FSRoomPlayer:GetPosition()
    return self.positionX, self.positionY
end

---@param damage number 收到伤害
---@return boolean 血量是否被打完了归零了
function FSRoomPlayer:TakeDamage(damage)
    self.HP = math.max(0, self.HP - damage);
    return self.HP <= 0;
end

---@param amount number 恢复血量值
function FSRoomPlayer:Heal(amount)
    self.HP = math.min(self.maxHP, self.HP + amount);
end

---@param amount number 消耗技能蓝值
---@return boolean 是否消耗成功
function FSRoomPlayer:ConsumeMP(amount)
    if self.MP >= amount then
        self.MP = self.MP - amount;
        return true;
    end
    return false;
end

---@param amount number 恢复技能蓝值
function FSRoomPlayer:RestoreMP(amount)
    self.MP = math.min(self.maxMP, self.MP + amount);
end

---@param skillId integer 技能ID
function FSRoomPlayer:AddSkill(skillId)
    if not self.skills[skillId] then
        self.skills[skillId] = true;
        self.skillCooldowns[skillId] = 0;
    end
end

---@param skillId integer 检查是否可以使用技能
function FSRoomPlayer:CanUseSkill(skillId)
    return self.skills[skillId] and self.skillCooldowns[skillId] <= 0;
end

---@param skillId integer 技能ID
---@param cooldown number 冷却值
---@return boolean 设置是否成功
function FSRoomPlayer:SetSkillCooldown(skillId, cooldown)
    if not self.skills[skillId] then
        return false;
    end
    self.skillCooldowns[skillId] = cooldown;
    return true;
end

---为所有技能ID冷却值减少 cooldownReduction
---@param cooldownReduction number 冷却减少值
---@return boolean 是否成功
function FSRoomPlayer:SubCooldownsForAllSkillID(cooldownReduction)
    if cooldownReduction <= 0 then
        return false;
    end

    for skillId, cooldown in pairs(self.skillCooldowns) do
        if cooldown > 0 then
            if cooldownReduction >= cooldown then
                self.skillCooldowns[skillId] = 0;
            else
                self.skillCooldowns[skillId] = cooldown - cooldownReduction;
            end
        end
    end

    return true;
end

---检查玩家是否还存活着
---@return boolean
function FSRoomPlayer:IsAlive()
    return self.HP > 0;
end

---更新客户端向服务器心跳时间
function FSRoomPlayer:UpdateHeartbeat()
    self.lastHeartbeat = TimeMgr.GetS();
end

---检查玩家是否超时
function FSRoomPlayer:IsTimeout()
    local now = TimeMgr.GetS();
    --10秒没心跳就是超时 这里可以用配置
    return (now - self.lastHeartbeat) > 10;
end

---玩家断开连接了
function FSRoomPlayer:Disconnect()
    self.isConnected = false;
end

---玩家进行了重连
function FSRoomPlayer:Reconnect()
    self.isConnected = true;
    self:UpdateHeartbeat();
end

function FSRoomPlayer:OnTick()
end

return FSRoomPlayer;
