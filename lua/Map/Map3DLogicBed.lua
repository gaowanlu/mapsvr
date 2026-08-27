-- Map3D 床系统 (服务器权威)
--
-- 职责: 地图内床的创建/查询、上下床请求校验与状态变更、占用管理、
--       上下床事件广播。与 Map3DOctreeLogic 同模式: 独立模块, 函数接收地图对象。
--
-- 规则:
--   * 一张床同一时间只能有一个人睡 (占用由服务器权威维护)
--   * 上床: 玩家须站在床附近 (XZ 距离 ≤ BED_INTERACT_RADIUS), 床未被占用
--   * 睡觉中: 玩家位置被服务器移到床上并冻结 (不物理移动/不参与分离/免疫子弹),
--     由 Map3DLogic 的冻结守卫读取 map.beds[bedId].sleeper 实现
--   * 下床: 只有床上的人自己可以下床, 下床后留在床原位 (不额外位移)
--
-- 床数据: 本地坐标 (x/z 相对地图中心, y 相对地面) 存于 Map3D.beds,
-- 下发给客户端时按 MAP_DATA_SCALE(×1000) 取整, 与墙体盒同基准。

local Log = require("Log")

local Map3DLogicBed = {}

-- 上下床交互半径 (XZ 平面, 本地坐标单位): 玩家须站在这个范围内才能上床
Map3DLogicBed.INTERACT_RADIUS = 3.5
-- 床面高度 (相对地面, 与客户端渲染的床面一致)
Map3DLogicBed.BED_SURFACE_Y = 0.5
-- 下发坐标缩放 (与 Map3DLogic.MAP_DATA_SCALE 保持一致)
local MAP_DATA_SCALE = 1000

--- 地图初始化时创建床 (从地图配置, 本地坐标)
--- 同时建立 本地坐标→绝对坐标 的换算 (与 collideBoxes 同基准)
---@param map Map3D
function Map3DLogicBed.InitBeds(map)
    local size = map:GetSize()
    local centerX = math.floor(size.x / 2)
    local centerZ = math.floor(size.z / 2)
    local groundY = map.groundY

    map.beds = {}
    local mapConfig = require("Map3DMapConfig").GetMapConfig(map:GetMapId())
    local bedConfigs = mapConfig and mapConfig.beds or nil

    local count = 0
    if bedConfigs ~= nil then
        for i, cfg in ipairs(bedConfigs) do
            local bedId = "bed" .. tostring(i)
            map.beds[bedId] = {
                bedId = bedId,
                -- 本地坐标 (相对地图中心/地面), 用于交互距离判定与渲染下发
                x = cfg.x,
                z = cfg.z,
                w = cfg.w,
                d = cfg.d,
                rotY = cfg.rotY or 0,
                color = cfg.color or 0x7a5c3e,
                -- 绝对坐标 (用于睡觉时玩家定位)
                absX = cfg.x + centerX,
                absZ = cfg.z + centerZ,
                absY = groundY + Map3DLogicBed.BED_SURFACE_Y,
                -- 占用: 睡觉玩家的userId, nil=空床
                sleeper = nil
            }
            count = count + 1
        end
    end

    Log:Error("Map3D[%d] beds[%d] created", map:GetMapId(), count)
end

--- 获取床
---@param map   Map3D
---@param bedId string
---@return Map3DBedType | nil
function Map3DLogicBed.GetBed(map, bedId)
    return map.beds[bedId]
end

--- 上下床请求 (服务器权威校验)
---@param map       Map3D
---@param userId    string  请求者userId (取自会话, 不信任客户端)
---@param bedId     string  目标床ID
---@param wantSleep boolean true=上床睡觉 false=下床起床
function Map3DLogicBed.PlayerSleepReq(map, userId, bedId, wantSleep)
    local player = map:GetMapPlayerByUserId(userId)
    if player == nil then
        return
    end

    local bed = Map3DLogicBed.GetBed(map, bedId)
    if bed == nil then
        Log:Error(
            "Map3D[%d] PlayerSleepReq unknown bed[%s] userId[%s]", map:GetMapId(), tostring(bedId), tostring(userId)
        )
        return
    end

    if wantSleep then
        -- 已经在别的床上睡 → 先下床再上 (不允许同时占两床)
        if player.sleepBedId ~= nil then
            Map3DLogicBed.WakePlayer(map, userId)
        end
        -- 床已被别人占用 → 拒绝 (一床一人)
        if bed.sleeper ~= nil then
            return
        end
        -- 距离校验: 玩家须站在床附近
        local dx = player.pos.x - bed.absX
        local dz = player.pos.z - bed.absZ
        local r = Map3DLogicBed.INTERACT_RADIUS
        if dx * dx + dz * dz > r * r then
            return
        end
        Map3DLogicBed.SleepPlayer(map, userId, bed)
    else
        -- 下床: 只有床上的人自己可以下
        if bed.sleeper == userId then
            Map3DLogicBed.WakePlayer(map, userId)
        end
    end
end

--- 上床睡觉: 冻结玩家, 移到床上, 广播
---@param map    Map3D
---@param userId string
---@param bed    Map3DBedType
function Map3DLogicBed.SleepPlayer(map, userId, bed)
    local player = map:GetMapPlayerByUserId(userId)
    if player == nil then
        return
    end

    -- 移到床上 (服务器权威位置, 客户端靠状态同步/NOTIFY_SLEEP 收敛)
    player.pos.x = bed.absX
    player.pos.y = bed.absY
    player.pos.z = bed.absZ
    player.prevPos.x = player.pos.x
    player.prevPos.y = player.pos.y
    player.prevPos.z = player.pos.z
    player.v.x = 0
    player.v.y = 0
    player.v.z = 0
    player.dir.x = 0
    player.dir.y = 0
    player.dir.z = 0
    player.sleepBedId = bed.bedId
    bed.sleeper = userId

    -- 位置变了, 重插八叉树 (保证状态广播/子弹查询仍能查到该玩家)
    map:UpdatePlayerOctree(player)

    Map3DLogicBed.NotifySleep(map, bed.bedId, userId, true, player.pos)
end

--- 下床起床: 解冻玩家 (留在床原位), 广播
---@param map    Map3D
---@param userId string
function Map3DLogicBed.WakePlayer(map, userId)
    local player = map:GetMapPlayerByUserId(userId)
    if player == nil or player.sleepBedId == nil then
        return
    end

    local bed = Map3DLogicBed.GetBed(map, player.sleepBedId)
    player.sleepBedId = nil
    if bed ~= nil and bed.sleeper == userId then
        bed.sleeper = nil
    end

    Map3DLogicBed.NotifySleep(map, bed and bed.bedId or "", userId, false, player.pos)
end

--- 广播上下床状态给当前地图内所有玩家 (含本人)
---@param map      Map3D
---@param bedId    string
---@param userId   string
---@param sleeping boolean
---@param pos      Vec3f   玩家当前位置(绝对坐标)
function Map3DLogicBed.NotifySleep(map, bedId, userId, sleeping, pos)
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")

    ---@type ProtoLua_ProtoCSMap3DNotifySleep
    local sleepPayload = {
        bedId = bedId,
        userId = userId,
        sleeping = sleeping,
        x = math.floor(pos.x),
        y = math.floor(pos.y),
        z = math.floor(pos.z)
    }

    for targetId in pairs(map.players) do
        local target = PlayerMgr.GetPlayerByUserId(targetId)
        if target ~= nil then
            MsgHandler:Send2Client(
                target:GetClientGID(), target:GetWorkerIdx(), ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_SLEEP,
                sleepPayload
            )
        end
    end
end

--- 构造床数据下发 (地图本地坐标×1000 整数, 与墙体盒同基准, 进入地图时随 MAP_DATA 发送)
---@param map Map3D
---@return table<integer, ProtoLua_ProtoMap3DBedData>
function Map3DLogicBed.GetBedsPayload(map)
    ---@type table<integer, ProtoLua_ProtoMap3DBedData>
    local bedsPayload = {}
    for _, bed in pairs(map.beds) do
        bedsPayload[#bedsPayload + 1] = {
            bedId = bed.bedId,
            x = math.floor(bed.x * MAP_DATA_SCALE + 0.5),
            -- 床面高度(相对地面)
            y = math.floor((Map3DLogicBed.BED_SURFACE_Y) * MAP_DATA_SCALE + 0.5),
            z = math.floor(bed.z * MAP_DATA_SCALE + 0.5),
            w = math.floor(bed.w * MAP_DATA_SCALE + 0.5),
            -- 床体总高 (床面+床垫)
            h = math.floor(1.0 * MAP_DATA_SCALE + 0.5),
            d = math.floor(bed.d * MAP_DATA_SCALE + 0.5),
            rotY = math.floor(bed.rotY * 1000),
            color = bed.color
        }
    end
    return bedsPayload
end

return Map3DLogicBed
