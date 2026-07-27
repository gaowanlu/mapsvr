---@class FSRoomBattle
---@field room FSRoom
---@field map  FSRoomSquareMap
local FSRoomBattle = require("FSRoomBattleData")

local FSRoomSquareMapAStar = require("FSRoomSquareMapAStarLogic")
local FSRoomPlayerSkill = require("FSRoomPlayerSkillLogic")

--- 创建新的FSRoomBattle对象
---@param room FSRoom
---@param map  FSRoomSquareMap
---@return FSRoomBattle
function FSRoomBattle.new(room, map)
    ---@type FSRoomBattle
    local self = setmetatable({}, FSRoomBattle)

    self.room = room
    self.map = map

    return self
end

--- 房间接收到新的帧指令
---@param command FSRoomSyncFrameCommandType
function FSRoomBattle:ProcessCommand(command)
    local player = self.room:GetRoomPlayer(command.userId)
    if not player or not player:IsAlive() then
        return { success = false, error = "RoomPlayer not found or dead" }
    end

    local result = { success = true, commandType = command.commandType }

    -- 临时使用字面常量作为 commandType 的判断条件
    if command.commandType == "move" then
        result = self:ProcessMove(player, command.data)
    elseif command.commandType == "skill" then
        result = self:ProcessSkill(player, command.data)
    end

    return result
end

--- 房间玩家接收到新的移动命令
---@param player FSRoomPlayer
---@return table
function FSRoomBattle:ProcessMove(player, data)
    local targetX = math.floor(data.targetX or 0)
    local targetY = math.floor(data.targetY or 0)

    -- 校验客户端想去的位置是否能走
    if not self.map:IsWalkable(targetX, targetY) then
        return { success = false, error = "Target position not walkable", userId = player.userId }
    end

    -- 检查玩家当前位置距离目标位置有多远，简单的 假设每帧只能移动一个瓦片
    local currentX, currentY = player:GetPosition()
    currentX = math.floor(currentX)
    currentY = math.floor(currentY)
    local distance = self.map:Distance(currentX, currentY, targetX, targetY)

    if distance <= 1 then
        -- 在此简单处理 直接设置位置 其实应该将玩家的行走方向设置 和 目标位置设置
        -- 让玩家自己走 在此直接设置目标位置 假设每帧移动一个瓦片
        player:SetPosition(targetX, targetY)

        return { success = true, userId = player.userId, position = { x = targetX, y = targetY } }
    end

    -- 如果当前位置到目标位置要走1个格子以上 则使用导航 走一个格子
    -- 查找路径 然后走一个格子
    local squareMapAStar = FSRoomSquareMapAStar.new()
    local path = squareMapAStar:FindPath(self.map, currentX, currentY, targetX, targetY)

    -- 无路径可走
    if not path or not path[2] then
        return { success = false, error = "Cannot find path", userId = player.userId }
    end

    targetX = path[2].x -- 玩家需要朝着下一个格子走
    targetY = path[2].y

    -- 在此简单处理 直接设置位置 其实应该将玩家的行走方向设置 和 目标位置设置
    -- 让玩家自己走 在此直接设置目标位置 假设每帧移动一个瓦片
    player:SetPosition(targetX, targetY)

    return { success = true, userId = player.userId, position = { x = targetX, y = targetY } }
end

--- 房间玩家接收到新的技能命令 这只是简单处理的样例
---@param player FSRoomPlayer
---@return table
function FSRoomBattle:ProcessSkill(player, data)
    local skillId = data.skillId
    local targetX = math.floor(data.targetX or 0)
    local targetY = math.floor(data.targetY or 0)
    local targetUserId = data.targetUserId

    -- 查找技能
    local skill = FSRoomPlayerSkill.GetSkill(skillId)
    if not skill then
        return { success = false, error = "Invalid skill", userId = player.userId }
    end

    -- 检查玩家技能是否可以释放
    local canCast = skill:CanCast(player, targetX, targetY)
    if not canCast then
        return { success = false, error = "Skill cannot be cast", userId = player.userId }
    end

    -- 查找目标玩家
    ---@type table<integer, FSRoomPlayer>
    local targets = {}

    -- 查找技能范围内的所有玩家
    if skill.aoeRadius > 0 then
        for _, p in pairs(self.room.roomPlayers) do
            -- 目标玩家活着且不是自己
            if p:IsAlive() and p.userId ~= player.userId then
                local px, py = p:GetPosition()
                local distance = self.map:Distance(px, py, targetX, targetY)

                if distance <= skill.aoeRadius then
                    if not targetUserId or p.userId == targetUserId then
                        table.insert(targets, p)
                    end
                end
            end
        end
    end

    -- 释放技能
    local skillResults = skill:Cast(player, targets)

    return {
        success = true,
        userId = player.userId,
        skillId = skill.id,
        skillName = skill.name,
        results = skillResults
    }
end

function FSRoomBattle:UpdateFrame()
    -- 为所有玩家更新技能冷却
    for _, player in pairs(self.room.roomPlayers) do
        if player:IsAlive() then
            player:SubCooldownsForAllSkillID(1) -- 假设每帧减少1秒的冷却时间
        end
    end
end

--- 检查游戏是否结束了 只剩一个人或一个人不剩
---@return boolean 是否结束, string | nil 胜利者userId
function FSRoomBattle:CheckGameEnd()
    -- 还活着的玩家
    ---@type table<integer, FSRoomPlayer>
    local alivePlayers = {}
    for _, player in pairs(self.room.roomPlayers) do
        if player:IsAlive() then
            table.insert(alivePlayers, player)
        end
    end

    -- 如果只剩一个玩家活着 则游戏结束 胜利者就是这个玩家
    if #alivePlayers == 1 then
        local winnerUserId = nil
        if #alivePlayers == 1 then
            winnerUserId = alivePlayers[1].userId
        end
        return true, winnerUserId
    end

    -- 如果没有玩家活着 则游戏结束 没有胜利者
    return false, nil
end

return FSRoomBattle
