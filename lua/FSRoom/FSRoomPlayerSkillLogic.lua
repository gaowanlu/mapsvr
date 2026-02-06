---@class FSRoomPlayerSkill
---@field skillsDB table<integer,FSRoomPlayerSkill>
---@field TYPE_DAMAGE string 技能类型 伤害
---@field TYPE_HEAL string 技能类型 治疗
---@field TYPE_BUFF string 技能类型 增益
---@field TYPE_DEBUFF string 技能类型 减益
---@field id integer 技能ID
---@field name string 技能名称
---@field skillType string 技能类型
---@field costMP number MP消耗
---@field cooldown number 冷却时间（秒）
---@field range number 技能施法距离
---@field damage number 造成的伤害值
---@field healAmount number 治疗量
---@field aoeRadius number AOE半径(0表示单体)
local FSRoomPlayerSkill = require("FSRoomPlayerSkillData");

-- Skill types
FSRoomPlayerSkill.TYPE_DAMAGE = "damage";
FSRoomPlayerSkill.TYPE_HEAL = "heal";
FSRoomPlayerSkill.TYPE_BUFF = "buff";
FSRoomPlayerSkill.TYPE_DEBUFF = "debuff";

---@class FSRoomPlayerSkillConfig
---@field costMP number MP消耗
---@field cooldown number 冷却时间（秒）
---@field range number 技能施法距离
---@field damage number 造成的伤害值
---@field healAmount number 治疗量
---@field aoeRadius number AOE半径(0表示单体)

--- 创建新的技能对象
---@return FSRoomPlayerSkill
---@param id integer
---@param name string
---@param skillType string
---@param config FSRoomPlayerSkillConfig
function FSRoomPlayerSkill.new(id, name, skillType, config)
    ---@type FSRoomPlayerSkill
    local self = setmetatable({}, FSRoomPlayerSkill);

    self.id = id;
    self.name = name;
    self.skillType = skillType;

    self.costMP = config.costMP;
    self.cooldown = config.cooldown;
    self.range = config.range;
    self.damage = config.damage;
    self.healAmount = config.healAmount;
    self.aoeRadius = config.aoeRadius;

    return self
end

--- 判断技能是否可以释放
---@param caster FSRoomPlayer
---@param targetX number
---@param targetY number
function FSRoomPlayerSkill:CanCast(caster, targetX, targetY)
    -- 检查MP是否足够
    if caster.MP < self.costMP then
        return false;
    end

    -- 检查技能是否在冷却中
    if not caster:CanUseSkill(self.id) then
        return false;
    end

    -- 检查施法距离
    local casterX, casterY = caster:GetPosition();

    local dx = casterX - targetX
    local dy = casterY - targetY

    local distance = math.sqrt(dx * dx + dy * dy)

    if distance > self.range then
        return false
    end

    return true
end

--- 释放技能
---@param caster FSRoomPlayer 施法者
---@param targets table<integer,FSRoomPlayer> 目标
function FSRoomPlayerSkill:Cast(caster, targets)
    -- 消耗MP
    caster:ConsumeMP(self.costMP);

    -- 设置技能冷却
    caster:SetSkillCooldown(self.id, self.cooldown);

    local results = {};

    if self.skillType == FSRoomPlayerSkill.TYPE_DAMAGE then
        -- 伤害型技能处理
        for _, target in ipairs(targets) do
            local isDead = target:TakeDamage(self.damage);
            table.insert(results, {
                targetUserId = target.userId, -- 目标ID
                damage = self.damage,         -- 实际伤害
                isDead = isDead,              -- 是否死亡
                remainingHP = target.HP       -- 剩余HP
            });
        end
    elseif self.skillType == FSRoomPlayerSkill.TYPE_HEAL then
        -- 治疗型技能处理
        for _, target in ipairs(targets) do
            target:Heal(self.healAmount);
            table.insert(results, {
                targetUserId = target.userId, -- 目标ID
                heal = self.healAmount,       -- 治疗量
                remainingHP = target.HP       -- 治疗后的HP
            });
        end
    end

    return results;
end

-- 初始化技能数据
function FSRoomPlayerSkill.InitSkillsDB()
    FSRoomPlayerSkill.skillsDB = {};

    -- 普通攻击
    FSRoomPlayerSkill.skillsDB[1] = FSRoomPlayerSkill.new(1, "Basic Attack", FSRoomPlayerSkill.TYPE_DAMAGE, {
        costMP = 0,
        cooldown = 0,
        range = 2,
        damage = 50,
        aoeRadius = 0,
        healAmount = 0
    });

    -- 火球术
    FSRoomPlayerSkill.skillsDB[2] = FSRoomPlayerSkill.new(2, "Fireball", FSRoomPlayerSkill.TYPE_DAMAGE, {
        costMP = 50,
        cooldown = 10,
        range = 10,
        damage = 200,
        aoeRadius = 2,
        healAmount = 0
    });

    -- 治疗术
    FSRoomPlayerSkill.skillsDB[3] = FSRoomPlayerSkill.new(3, "Heal", FSRoomPlayerSkill.TYPE_HEAL, {
        costMP = 30,
        cooldown = 15,
        range = 5,
        healAmount = 150,
        aoeRadius = 0,
        damage = 0
    });

    -- 闪电打击
    FSRoomPlayerSkill.skillsDB[4] = FSRoomPlayerSkill.new(4, "Lightning Strike", FSRoomPlayerSkill.TYPE_DAMAGE, {
        costMP = 80,
        cooldown = 20,
        range = 15,
        damage = 300,
        aoeRadius = 0,
        healAmount = 0
    });

    -- 护盾（当前实现为自我治疗）
    FSRoomPlayerSkill.skillsDB[5] = FSRoomPlayerSkill.new(5, "Shield", FSRoomPlayerSkill.TYPE_HEAL, {
        costMP = 40,
        cooldown = 12,
        range = 0,
        healAmount = 100,
        aoeRadius = 0,
        damage = 0
    });
end

--- 根据技能ID获取技能
---@param skillId integer
---@return FSRoomPlayerSkill|nil
function FSRoomPlayerSkill.GetSkill(skillId)
    return FSRoomPlayerSkill.skillsDB[skillId];
end

--- 获取全部技能
---@return table<integer,FSRoomPlayerSkill>
function FSRoomPlayerSkill.GetAllSkills()
    return FSRoomPlayerSkill.skillsDB;
end

--- 初始化技能数据库
FSRoomPlayerSkill.InitSkillsDB();

return FSRoomPlayerSkill;
