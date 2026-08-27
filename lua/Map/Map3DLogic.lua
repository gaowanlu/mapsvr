---@class Map3D: Map3DType
local Map3D = require("Map3DData")
local Log = require("Log")
local TimeMgr = require("TimeMgrLogic")
local Map3DOctree = require("Map3DOctreeLogic")
local Map3DLogicBed = require("Map3DLogicBed")
local Map3DMapConfig = require("Map3DMapConfig")
local NumericBigInt = require("NumericBigIntLogic")
local AlgorithmRandom = require("AlgorithmRandomLogic")

-- 下发给客户端的坐标缩放: 本地坐标×1000 转为整数
local MAP_DATA_SCALE = 1000

-- 下发给客户端的速度缩放: 本地速度(px/s)×1000 转为整数
-- (直接 math.floor 原始速度会把 +0.4→0 / -0.4→-1, 正负量化不对称; 放大后误差 ≤0.001 px/s)
local VEL_DATA_SCALE = 1000

-- 玩家命中中心高度偏移: 身体中点相对脚底 pos.y 的高度,
-- 命中判定与八叉树查询扩展必须共用同一常量, 防止两处漂移导致漏判
local PLAYER_HIT_CENTER_OFFSET = 1.0

-- 构造新的3DMap对象
---@param mapId integer 地图ID
---@return Map3D 新的地图对象
function Map3D.new(mapId)
    ---@type Map3D
    local self = setmetatable({}, Map3D)

    self.MapDbData = {
        id = mapId,
        TICK_RATE = 20,
        DT_MS = 50,
        lastTickTimeMS = 0,
        durationAccumulator = 0,
        size = { x = 1000000, y = 1000000, z = 1000000 }
    }

    -- 地图内的player
    ---@type table<string, Map3DPlayerType>
    self.players = {}

    -- 子弹管理
    ---@type table<string, Map3DBulletType>
    self.bullets = {}

    -- 八叉树
    self.map3DOctree = Map3DOctree.new(0, 0, 0, self:GetSize().x, self:GetSize().y, self:GetSize().z, 0)

    self.nextBulletIdSeq = 0
    self.bulletCount = 0
    self.maxBodyRadius = 0

    -- 加载地图墙体/建筑配置 (服务器权威碰撞数据)
    local size = self:GetSize()
    local centerX = math.floor(size.x / 2)
    local centerZ = math.floor(size.z / 2)
    local groundY = math.floor(size.y / 2)

    self.groundY = groundY
    self.mapName = "MAP" .. tostring(mapId)

    -- 参与玩家/子弹碰撞的AABB盒 (绝对坐标)
    ---@type table<integer, Map3DCollideBoxType>
    self.collideBoxes = {}
    -- 下发给客户端渲染的盒 (地图本地坐标)
    ---@type table<integer, Map3DBoxConfig>
    self.renderBoxes = {}

    local mapConfig = Map3DMapConfig.GetMapConfig(mapId)
    if mapConfig ~= nil then
        self.mapName = mapConfig.name
        for _, box in ipairs(mapConfig.boxes) do
            self.renderBoxes[#self.renderBoxes + 1] = box
            if box.collide ~= false then
                self.collideBoxes[#self.collideBoxes + 1] = {
                    x = box.x + centerX,
                    y = box.y + groundY,
                    z = box.z + centerZ,
                    hw = box.w / 2,
                    hh = box.h / 2,
                    hd = box.d / 2
                }
            end
        end
        Log:Error(
            "Map3D[%d] loaded map config[%s] boxes[%d] collideBoxes[%d]", mapId, mapConfig.name, #self.renderBoxes,
            #self.collideBoxes
        )
    else
        Log:Error("Map3D[%d] no map config found, map has no wall/building collision", mapId)
    end

    -- 创建地图内的床 (服务器权威占用, 可上床睡觉)
    Map3DLogicBed.InitBeds(self)

    return self
end

-- 获取最大射击距离（单位：px）
---@return integer
function Map3D:GetMaxShootDist()
    return 200
end

-- 获取开火冷却（单位：ms）: 同一玩家两次射击的最小间隔,
-- 防止客户端高频刷射击消息打满单线程 Other VM (每发子弹 = 广播 + 每 tick 全量 CCD)
---@return integer
function Map3D:GetFireCooldownMS()
    return 150
end

-- 获取单地图存活子弹上限: 达到后拒绝新射击 (兜底, 防止 tick 成本随子弹数无界增长)
---@return integer
function Map3D:GetMaxBulletsPerMap()
    return 200
end

-- 获取子弹碰撞半径
---@param _bulletType string | nil
---@return number
function Map3D:GetBulletCollisionRadius(_bulletType)
    return 0.5
end

-- 获取子弹的存活时间（单位：ms）
---@return integer
function Map3D:GetBulletLifeTime()
    return 1000
end

-- 获取子弹速度Ratio
---@return integer
function Map3D:GetBulletSpeedRatio()
    return 50000
end

---@return Map3DDbDataType
function Map3D:GetMapDbData()
    return self.MapDbData
end

---@return integer
function Map3D:GetLastTickTimeMS()
    return self:GetMapDbData().lastTickTimeMS
end

---@return Vec3i
function Map3D:GetSize()
    return self:GetMapDbData().size
end

---@return integer 地图ID
function Map3D:GetMapId()
    return self.MapDbData.id
end

---@param userId string
---@return Map3DPlayerType | nil
function Map3D:GetMapPlayerByUserId(userId)
    return self.players[userId]
end

--- 构造地图墙体/建筑配置下发数据 (地图本地坐标×1000 整数, 玩家进入地图时发送)
---@return ProtoLua_ProtoCSMap3DNotifyMapData
function Map3D:GetMapDataPayload()
    ---@type table<integer, ProtoLua_ProtoMap3DBoxData>
    local boxesPayload = {}
    for i = 1, #self.renderBoxes do
        local b = self.renderBoxes[i]
        boxesPayload[#boxesPayload + 1] = {
            x = math.floor(b.x * MAP_DATA_SCALE + 0.5),
            y = math.floor(b.y * MAP_DATA_SCALE + 0.5),
            z = math.floor(b.z * MAP_DATA_SCALE + 0.5),
            w = math.floor(b.w * MAP_DATA_SCALE + 0.5),
            h = math.floor(b.h * MAP_DATA_SCALE + 0.5),
            d = math.floor(b.d * MAP_DATA_SCALE + 0.5),
            color = b.color,
            collide = b.collide ~= false
        }
    end

    local size = self:GetSize()
    return {
        mapId = self:GetMapId(),
        name = self.mapName,
        groundY = math.floor(self.groundY),
        boxes = boxesPayload,
        -- 地图中心绝对坐标: 玩家可能出生在环状偏移点上, 客户端需要用地图中心校准本地原点
        centerX = math.floor(size.x / 2),
        centerZ = math.floor(size.z / 2),
        beds = Map3DLogicBed.GetBedsPayload(self)
    }
end

function Map3D:OnTick()
    local timeMS = TimeMgr.GetMS()

    if self.MapDbData.lastTickTimeMS <= 0 then
        self.MapDbData.lastTickTimeMS = timeMS
    end

    local frameTime = timeMS - self.MapDbData.lastTickTimeMS
    if frameTime > 250 then
        frameTime = 250
    end

    self.MapDbData.lastTickTimeMS = timeMS
    self.MapDbData.durationAccumulator = self.MapDbData.durationAccumulator + frameTime

    while self.MapDbData.durationAccumulator >= self.MapDbData.DT_MS do
        self:FixedUpdate(timeMS)
        self.MapDbData.durationAccumulator = self.MapDbData.durationAccumulator - self.MapDbData.DT_MS
    end
end

-- 出生点环形错开参数
local SPAWN_RING_RADIUS = 14 -- 出生环半径(本地坐标), 落在地图中心无掩体的开阔区
local SPAWN_RING_SLOTS = 20  -- 环上的出生槽位数

--- 计算出生点 (绝对坐标)
--- 首个玩家出生在地图中心, 后续玩家按序号在中心周围环形错开,
--- 避免所有玩家同点出生 (同点出生 + 无玩家间碰撞会触发 t=0 任意方向误伤)
---@param index integer 当前地图内已有玩家数(0-based 序号)
---@return Vec3f
function Map3D:FindSpawnPoint(index)
    local x = math.floor(self.MapDbData.size.x / 2)
    local y = math.floor(self.MapDbData.size.y / 2)
    local z = math.floor(self.MapDbData.size.z / 2)

    if index <= 0 then
        return { x = x, y = y, z = z }
    end

    local slot = index % SPAWN_RING_SLOTS
    local angle = slot * (math.pi * 2 / SPAWN_RING_SLOTS)
    return { x = x + SPAWN_RING_RADIUS * math.cos(angle), y = y, z = z + SPAWN_RING_RADIUS * math.sin(angle) }
end

-- 新玩家加入地图
---@param userId string
---@return boolean
function Map3D:PlayerJoinMap(userId)
    if self:GetMapPlayerByUserId(userId) ~= nil then
        Log:Error("Map3D PlayerJoinMap id %s userId %s already in map", tostring(self.MapDbData.id), tostring(userId))
        return false
    end

    -- 统计当前地图内玩家数, 用于环形错开出生点
    local playerCount = 0
    for _ in pairs(self.players) do
        playerCount = playerCount + 1
    end
    local spawnPoint = self:FindSpawnPoint(playerCount)

    ---@type Map3DPlayerType
    local newMap3DPlayer = {
        userId = userId,
        pos = { x = spawnPoint.x, y = spawnPoint.y, z = spawnPoint.z },
        prevPos = { x = spawnPoint.x, y = spawnPoint.y, z = spawnPoint.z },
        v = { x = 0, y = 0, z = 0 },
        gravity = 1,
        weight = 1,
        lastSeq = 0,
        lastClientTime = "0",
        dir = { x = 0, y = 0, z = 0 },
        speedRatio = 1000,
        -- 匹配客户端 7单位/秒
        maxSpeed = 7,
        accel = 1,
        friction = 1.0,
        -- 匹配客户端人物模型宽度
        bodyRadius = 1.0,
        -- 记录地面Y，用于服务器的重力模拟
        groundY = spawnPoint.y
    }

    self.players[userId] = newMap3DPlayer
    if newMap3DPlayer.bodyRadius > self.maxBodyRadius then
        self.maxBodyRadius = newMap3DPlayer.bodyRadius
    end
    Map3DOctree.OcInsert(self.map3DOctree, newMap3DPlayer)

    return true
end

-- 玩家离开地图
---@param userId string
---@return boolean
function Map3D:PlayerExitMap(userId)
    ---@type Map3DPlayerType
    local targetPlayer = self.players[userId]
    if targetPlayer ~= nil then
        if targetPlayer.map3DOctree ~= nil then
            Map3DOctree.RemoveItemFromList(targetPlayer.map3DOctree, targetPlayer.userId)
            targetPlayer.map3DOctree = nil
        end
        self.players[userId] = nil
        return true
    end
    return false
end

---@param userId     string  用户ID
---@param dirX       number  x方向
---@param dirY       number  y方向
---@param dirZ       number  z方向
---@param seq        integer 序列号
---@param clientTime string  客户端时间戳
function Map3D:MapPlayerInput(userId, dirX, dirY, dirZ, seq, clientTime)
    local map3DPlayer = self.players[userId]
    if map3DPlayer == nil then return end

    if map3DPlayer.lastSeq >= avant.UINT32_MAX then
        map3DPlayer.lastSeq = 0
    end

    -- 允许跳跃的 seq 或者积压的 seq，防止丢包导致一直卡住
    if seq <= map3DPlayer.lastSeq then
        return
    end
    map3DPlayer.lastSeq = seq

    local len = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if len > 0.0001 then
        dirX = dirX / len
        dirY = dirY / len
        dirZ = dirZ / len
    else
        dirX = 0
        dirY = 0
        dirZ = 0
    end

    map3DPlayer.dir.x = dirX
    map3DPlayer.dir.y = dirY
    map3DPlayer.dir.z = dirZ
    map3DPlayer.lastClientTime = clientTime
end

--- 把玩家位置夹回世界范围: X/Z 夹回地图边界内(留身体半径余量), Y 不低于地面
---@param mapPlayer Map3DPlayerType
function Map3D:ClampPlayerToWorld(mapPlayer)
    local mapSize = self:GetSize()
    local r = mapPlayer.bodyRadius

    if mapPlayer.pos.x < r then mapPlayer.pos.x = r end
    if mapPlayer.pos.z < r then mapPlayer.pos.z = r end
    if mapPlayer.pos.x > mapSize.x - r then mapPlayer.pos.x = mapSize.x - r end
    if mapPlayer.pos.z > mapSize.z - r then mapPlayer.pos.z = mapSize.z - r end
    if mapPlayer.pos.y < mapPlayer.groundY then mapPlayer.pos.y = mapPlayer.groundY end
end

--- 重新插入八叉树 (先移出旧节点再插入新节点)
---@param mapPlayer Map3DPlayerType
function Map3D:UpdatePlayerOctree(mapPlayer)
    if mapPlayer.map3DOctree ~= nil then
        Map3DOctree.RemoveItemFromList(mapPlayer.map3DOctree, mapPlayer.userId)
        mapPlayer.map3DOctree = nil
    end
    Map3DOctree.OcInsert(self.map3DOctree, mapPlayer)
end

---@param mapPlayer Map3DPlayerType
function Map3D:PlayerPhysicsMove(mapPlayer)
    -- 转为秒，避免 math.floor 截断导致位移为0
    local dt = self:GetMapDbData().DT_MS / 1000.0

    -- 目标速度
    local targetVx = mapPlayer.dir.x * mapPlayer.maxSpeed
    local targetVz = mapPlayer.dir.z * mapPlayer.maxSpeed

    -- X/Z 轴速度平滑插值
    local smoothFactor = 0.25
    mapPlayer.v.x = mapPlayer.v.x + (targetVx - mapPlayer.v.x) * smoothFactor
    mapPlayer.v.z = mapPlayer.v.z + (targetVz - mapPlayer.v.z) * smoothFactor

    -- 保存上一帧位置
    mapPlayer.prevPos.x = mapPlayer.pos.x
    mapPlayer.prevPos.y = mapPlayer.pos.y
    mapPlayer.prevPos.z = mapPlayer.pos.z

    -- 更新位置 (不进行 floor 截断，保留精度)
    mapPlayer.pos.x = mapPlayer.pos.x + mapPlayer.v.x * dt
    mapPlayer.pos.z = mapPlayer.pos.z + mapPlayer.v.z * dt

    -- Y轴物理模拟 (与客户端重力一致)
    if mapPlayer.dir.y > 0 and mapPlayer.v.y == 0 and mapPlayer.pos.y <= mapPlayer.groundY then
        mapPlayer.v.y = 10 -- 起跳初速度
    end

    mapPlayer.v.y = mapPlayer.v.y - 28 * dt -- 重力加速度
    mapPlayer.pos.y = mapPlayer.pos.y + mapPlayer.v.y * dt

    if mapPlayer.pos.y <= mapPlayer.groundY then
        mapPlayer.pos.y = mapPlayer.groundY
        mapPlayer.v.y = 0
    end

    -- 地图边界控制
    self:ClampPlayerToWorld(mapPlayer)

    -- 墙体/建筑碰撞 (服务器权威, 防止穿墙)
    self:PlayerCollide(mapPlayer)

    -- 更新八叉树
    self:UpdatePlayerOctree(mapPlayer)
end

--- 玩家与墙体/建筑的碰撞解析 (最小穿透轴, 服务器权威)
--- 每次把重叠按 X/Z 中穿透较浅的一轴完全移出, 保证玩家绝不进入墙体/建筑,
--- 也不会从墙角滑穿到墙外; 贴墙时可平滑滑动。与客户端本地预测使用同一套盒数据。
---@param mapPlayer Map3DPlayerType
function Map3D:PlayerCollide(mapPlayer)
    local pos = mapPlayer.pos
    local r = mapPlayer.bodyRadius

    for i = 1, #self.collideBoxes do
        local b = self.collideBoxes[i]
        local dx = pos.x - b.x
        local dz = pos.z - b.z
        local hx = b.hw + r
        local hz = b.hd + r

        if dx > -hx and dx < hx and dz > -hz and dz < hz then
            local px = hx - math.abs(dx)
            local pz = hz - math.abs(dz)
            if px < pz then
                pos.x = pos.x + (dx > 0 and px or -px)
            else
                pos.z = pos.z + (dz > 0 and pz or -pz)
            end
        end
    end
end

--- 玩家间分离碰撞: 把两个在 XZ 平面上重叠的身体沿连线各推开一半
--- (与 PlayerCollide 一致, 只在 XZ 平面处理, 半径取身体球半径 bodyRadius)
--- 分离后双方重新夹回世界范围并做一次墙体碰撞, 防止被推进墙里/地下
---@param a Map3DPlayerType
---@param b Map3DPlayerType
---@return boolean 是否发生了推开
function Map3D:SeparatePlayers(a, b)
    local ax, az = a.pos.x, a.pos.z
    local bx, bz = b.pos.x, b.pos.z

    local dx = bx - ax
    local dz = bz - az
    local minDist = a.bodyRadius + b.bodyRadius
    local distSq = dx * dx + dz * dz
    if distSq >= minDist * minDist then
        return false
    end

    local dist = math.sqrt(distSq)
    local ux, uz
    if dist <= 0.0001 then
        -- 完全重合: 单位向量无定义, 用固定方向兜底
        ux, uz = 1, 0
        dist = 0
    else
        ux, uz = dx / dist, dz / dist
    end

    -- 各推开一半重叠量
    local push = (minDist - dist) * 0.5
    a.pos.x = a.pos.x - ux * push
    a.pos.z = a.pos.z - uz * push
    b.pos.x = b.pos.x + ux * push
    b.pos.z = b.pos.z + uz * push

    -- 防止分离把玩家推进边界外/地下/墙里
    self:ClampPlayerToWorld(a)
    self:ClampPlayerToWorld(b)
    self:PlayerCollide(a)
    self:PlayerCollide(b)

    return true
end

--- 每帧对所有玩家做两两分离 (O(n^2), 地图内玩家数小可接受),
--- 避免玩家穿模重叠; 发生过位置变化的玩家最后统一重插八叉树
function Map3D:UpdatePlayerSeparation()
    ---@type table<integer, string>
    local users = {}
    for userId in pairs(self.players) do
        users[#users + 1] = userId
    end

    local moved = {}
    for i = 1, #users do
        local a = self.players[users[i]]
        if a.sleepBedId ~= nil then
            goto continue_sep_a
        end
        for j = i + 1, #users do
            local b = self.players[users[j]]
            if b.sleepBedId ~= nil then
                goto continue_sep_b
            end
            if self:SeparatePlayers(a, b) then
                moved[a.userId] = true
                moved[b.userId] = true
            end
            ::continue_sep_b::
        end
        ::continue_sep_a::
    end

    for userId in pairs(moved) do
        local mapPlayer = self.players[userId]
        if mapPlayer ~= nil then
            self:UpdatePlayerOctree(mapPlayer)
        end
    end
end

-- 玩家射击
---@param shooterId string 发射子弹的玩家的userId
---@param dirX      number 子弹方向向量X分量
---@param dirY      number 子弹方向向量Y分量
---@param dirZ      number 子弹方向向量Z分量
---@param shootDist number 射击距离
---@return string | nil 返回子弹ID (被限频/超上限拒绝时返回nil)
function Map3D:PlayerShoot(shooterId, dirX, dirY, dirZ, shootDist)
    local shooter = self:GetMapPlayerByUserId(shooterId)
    if shooter == nil then return nil end

    -- 开火限频: 同一玩家两次射击至少间隔 GetFireCooldownMS() ms,
    -- 防止恶意客户端按网络速率刷射击消息打满单线程 Other VM (与聊天限频同一模式)
    local now = TimeMgr.GetMS()
    if shooter.lastShootMS ~= nil and now - shooter.lastShootMS < self:GetFireCooldownMS() then
        return nil
    end

    if shootDist <= 0 or shootDist > self:GetMaxShootDist() then
        return nil
    end

    local len = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)

    if len < 0.0001 then
        return nil
    end
    dirX = dirX / len
    dirY = dirY / len
    dirZ = dirZ / len

    -- 子弹上限: 地图存活子弹数达到 GetMaxBulletsPerMap() 时拒绝新射击
    if self.bulletCount >= self:GetMaxBulletsPerMap() then
        return nil
    end

    self.nextBulletIdSeq = self.nextBulletIdSeq + 1
    local bulletId = tostring(self.nextBulletIdSeq)

    -- 起点加上眼睛高度
    local muzzleOffset = shooter.bodyRadius
    local startPosX = shooter.pos.x + dirX * muzzleOffset
    local startPosY = shooter.pos.y + 2.0 + dirY * muzzleOffset
    local startPosZ = shooter.pos.z + dirZ * muzzleOffset

    local bulletSpeedPerMs = self:GetBulletSpeedRatio() / 1000
    local distLifeTime = math.floor(shootDist / bulletSpeedPerMs)
    -- lifeTime 仅用于下发给客户端的显示时长(>=1 个 tick), 服务器实际射程由 remainingDist 决定
    local lifeTime = math.min(self:GetBulletLifeTime(), distLifeTime)
    lifeTime = math.max(self:GetMapDbData().DT_MS, lifeTime)

    ---@type Map3DBulletType
    local newBullet = {
        bulletId = bulletId,
        shooterId = shooterId,
        pos = { x = startPosX, y = startPosY, z = startPosZ },
        prevPos = { x = startPosX, y = startPosY, z = startPosZ },
        dir = { x = dirX, y = dirY, z = dirZ },
        lifeTime = lifeTime,
        spawnTime = now,
        speedRatio = self:GetBulletSpeedRatio(),
        collisionRadius = self:GetBulletCollisionRadius(),
        isExpired = false,
        -- 剩余射程: 距离模型的权威射程, 保证子弹总位移 == shootDist (而非按 tick 数硬凑)
        remainingDist = shootDist
    }

    self.bullets[bulletId] = newBullet
    self.bulletCount = self.bulletCount + 1
    shooter.lastShootMS = now

    -- 广播给周围玩家
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")
    local range = {
        x = newBullet.pos.x - 10000,
        y = newBullet.pos.y - 10000,
        z = newBullet.pos.z - 10000,
        w = 20000,
        h = 20000,
        d = 20000
    }
    local list = {}
    local seen = {}
    Map3DOctree.OcQuery(self.map3DOctree, range, list, seen)

    ---@type ProtoLua_ProtoCSMap3DNotifyBullet
    local bulletPayload = {
        bulletId = bulletId,
        shooterId = shooterId,
        x = math.floor(newBullet.pos.x),
        y = math.floor(newBullet.pos.y),
        z = math.floor(newBullet.pos.z),
        dirX = math.floor(newBullet.dir.x * 10000),
        dirY = math.floor(newBullet.dir.y * 10000),
        dirZ = math.floor(newBullet.dir.z * 10000),
        lifeTime = tostring(newBullet.lifeTime),
        spawnTime = tostring(now)
    }

    for _, pl in pairs(list) do
        local player = PlayerMgr.GetPlayerByUserId(pl.userId)
        if player ~= nil then
            MsgHandler:Send2Client(
                player:GetClientGID(), player:GetWorkerIdx(), ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_BULLET,
                bulletPayload
            )
        end
    end

    return bulletId
end

-- 房间文字聊天: 广播给当前地图(房间)内的所有玩家
---@param senderId string 发送者userId
---@param message  string 聊天内容
function Map3D:SendChat(senderId, message)
    local mapPlayer = self:GetMapPlayerByUserId(senderId)
    if mapPlayer == nil then return end

    -- 简单限频: 同一玩家至少间隔300ms才能再发, 防止刷屏
    local now = TimeMgr.GetMS()
    if mapPlayer.lastChatMS ~= nil and now - mapPlayer.lastChatMS < 300 then
        return
    end
    mapPlayer.lastChatMS = now

    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")

    ---@type ProtoLua_ProtoCSMap3DNotifyChat
    local chatPayload = { senderId = senderId, message = message }

    for userId in pairs(self.players) do
        local player = PlayerMgr.GetPlayerByUserId(userId)
        if player ~= nil then
            MsgHandler:Send2Client(
                player:GetClientGID(), player:GetWorkerIdx(), ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_CHAT,
                chatPayload
            )
        end
    end
end

-- 上下床请求 (服务器权威: 校验占用/距离, 冻结睡觉玩家)
--- 详见 Map3DLogicBed.lua
---@param userId    string  请求者userId (取自会话, 不信任客户端)
---@param bedId     string  目标床ID
---@param wantSleep boolean true=上床睡觉 false=下床起床
function Map3D:PlayerSleepReq(userId, bedId, wantSleep)
    Map3DLogicBed.PlayerSleepReq(self, userId, bedId, wantSleep)
end

-- 更新子弹
function Map3D:UpdateBullets()
    local timeMS = TimeMgr.GetMS()
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")
    local toRemove = {}

    for bulletId, bullet in pairs(self.bullets) do
        if bullet.isExpired then
            toRemove[#toRemove + 1] = bulletId
            goto continue
        end

        -- 安全上限检查: 正常销毁由剩余射程耗尽触发,
        -- 这里只用子弹最大生命(GetBulletLifeTime)兜底, 防止异常子弹无限存活
        -- (不能用 bullet.lifeTime 判断: 它现在仅表示下发给客户端的显示时长)
        if timeMS - bullet.spawnTime > self:GetBulletLifeTime() then
            bullet.isExpired = true
            toRemove[#toRemove + 1] = bulletId
            goto continue
        end

        -- 距离模型: 本 tick 位移不超过剩余射程, 保证子弹总位移 == shootDist
        local speed = bullet.speedRatio / 1000 * self:GetMapDbData().DT_MS
        local step = math.min(speed, bullet.remainingDist)
        bullet.prevPos.x = bullet.pos.x
        bullet.prevPos.y = bullet.pos.y
        bullet.prevPos.z = bullet.pos.z
        bullet.pos.x = bullet.pos.x + bullet.dir.x * step
        bullet.pos.y = bullet.pos.y + bullet.dir.y * step
        bullet.pos.z = bullet.pos.z + bullet.dir.z * step
        bullet.remainingDist = bullet.remainingDist - step

        -- 1. Find the earliest collision (wall / env / player)
        ---@type number
        local minT = 2
        local hitType = nil -- "wall" / "env" / "player"
        local hitData = {}

        -- Check walls
        local wallT = self:CheckBulletWallCCD(bullet)
        if wallT ~= nil and wallT < minT then
            minT = wallT
            hitType = "wall"
        end

        -- Check environment: ground plane + map boundary
        local envT = self:CheckBulletEnvCCD(bullet)
        if envT ~= nil and envT < minT then
            minT = envT
            hitType = "env"
        end

        -- Check players (八叉树范围查询, 把 O(子弹×全图玩家) 降为 O(子弹×附近玩家)):
        -- 命中中心 C = player.pos + (0, PLAYER_HIT_CENTER_OFFSET, 0), 若线段在 Q* 处命中 C,
        -- 则 |Q*-player.pos| ≤ collisionRadius + bodyRadius + PLAYER_HIT_CENTER_OFFSET,
        -- 故把子弹线段AABB按 R = collisionRadius + maxBodyRadius + PLAYER_HIT_CENTER_OFFSET 扩展后,
        -- 所有可能命中的玩家 pos 必落在其中 (maxBodyRadius ≥ 任一玩家的 bodyRadius)
        local expand = bullet.collisionRadius + self.maxBodyRadius + PLAYER_HIT_CENTER_OFFSET
        local rangeMinX = math.min(bullet.prevPos.x, bullet.pos.x) - expand
        local rangeMinY = math.min(bullet.prevPos.y, bullet.pos.y) - expand
        local rangeMinZ = math.min(bullet.prevPos.z, bullet.pos.z) - expand
        local rangeMaxX = math.max(bullet.prevPos.x, bullet.pos.x) + expand
        local rangeMaxY = math.max(bullet.prevPos.y, bullet.pos.y) + expand
        local rangeMaxZ = math.max(bullet.prevPos.z, bullet.pos.z) + expand
        local candidates = {}
        local seen = {}
        Map3DOctree.OcQuery(self.map3DOctree, {
            x = rangeMinX,
            y = rangeMinY,
            z = rangeMinZ,
            w = rangeMaxX - rangeMinX,
            h = rangeMaxY - rangeMinY,
            d = rangeMaxZ - rangeMinZ
        }, candidates, seen
        )

        for _, o in ipairs(candidates) do
            local player = self.players[o.userId]
            -- 睡觉中的玩家免疫子弹 (冻结在床上)
            if player ~= nil and o.userId ~= bullet.shooterId and player.sleepBedId == nil then
                local hit, t = self:CheckBulletPlayerCCD(bullet, player)
                if hit and t < minT then
                    minT = t
                    hitType = "player"
                    hitData.userId = o.userId
                    hitData.hitPos = {
                        x = bullet.prevPos.x + (bullet.pos.x - bullet.prevPos.x) * t,
                        y = bullet.prevPos.y + (bullet.pos.y - bullet.prevPos.y) * t,
                        z = bullet.prevPos.z + (bullet.pos.z - bullet.prevPos.z) * t
                    }
                end
            end
        end

        -- 2. Process the earliest hit
        if hitType == "wall" or hitType == "env" then
            -- 墙体与地面/边界同属环境碰撞, 复用墙体命中的击发效果通知
            local hitPos = {
                x = bullet.prevPos.x + (bullet.pos.x - bullet.prevPos.x) * minT,
                y = bullet.prevPos.y + (bullet.pos.y - bullet.prevPos.y) * minT,
                z = bullet.prevPos.z + (bullet.pos.z - bullet.prevPos.z) * minT
            }
            self:NotifyBulletWallHit(bulletId, bullet.shooterId, hitPos)
            bullet.isExpired = true
            toRemove[#toRemove + 1] = bulletId
        elseif hitType == "player" then
            self:NotifyPlayerHit(bulletId, hitData.userId, hitData.hitPos)
            bullet.isExpired = true
            toRemove[#toRemove + 1] = bulletId
        end

        -- 剩余射程耗尽: 距离模型的正常销毁条件 (子弹已飞满 shootDist)
        if not bullet.isExpired and bullet.remainingDist <= 0.0001 then
            bullet.isExpired = true
            toRemove[#toRemove + 1] = bulletId
        end

        if bullet.isExpired then
            goto continue
        end

        local range = {
            x = bullet.pos.x - 10000,
            y = bullet.pos.y - 10000,
            z = bullet.pos.z - 10000,
            w = 20000,
            h = 20000,
            d = 20000
        }
        local list = {}
        local seen = {}
        Map3DOctree.OcQuery(self.map3DOctree, range, list, seen)

        if #list ~= 0 then
            ---@type ProtoLua_ProtoCSMap3DNotifyBullet
            local playersPayload = {
                bulletId = bulletId,
                shooterId = bullet.shooterId,
                x = math.floor(bullet.pos.x),
                y = math.floor(bullet.pos.y),
                z = math.floor(bullet.pos.z),
                dirX = math.floor(bullet.dir.x * 10000),
                dirY = math.floor(bullet.dir.y * 10000),
                dirZ = math.floor(bullet.dir.z * 10000),
                lifeTime = tostring(bullet.lifeTime - (timeMS - bullet.spawnTime)),
                spawnTime = tostring(bullet.spawnTime)
            }

            for userId, pl in pairs(list) do
                local player = PlayerMgr.GetPlayerByUserId(pl.userId)
                if player ~= nil then
                    MsgHandler:Send2Client(
                        player:GetClientGID(), player:GetWorkerIdx(), ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_BULLET,
                        playersPayload
                    )
                end
            end
        end

        ::continue::
    end

    -- 每颗子弹本 tick 至多入队一次 (各分支均 goto continue / isExpired 守卫), 直接按数量扣减
    for _, bulletId in ipairs(toRemove) do
        self.bullets[bulletId] = nil
    end
    if #toRemove > 0 then
        self.bulletCount = self.bulletCount - #toRemove
    end
end

--- CCD碰撞检测
function Map3D:CheckBulletPlayerCCD(bullet, player)
    local dx = bullet.pos.x - bullet.prevPos.x
    local dy = bullet.pos.y - bullet.prevPos.y
    local dz = bullet.pos.z - bullet.prevPos.z

    -- 玩家碰撞中心点在身体中部 (与八叉树查询扩展共用 PLAYER_HIT_CENTER_OFFSET)
    local playerCenterY = player.pos.y + PLAYER_HIT_CENTER_OFFSET

    local px = player.pos.x - bullet.prevPos.x
    local py = playerCenterY - bullet.prevPos.y
    local pz = player.pos.z - bullet.prevPos.z

    local dirLenSq = dx * dx + dy * dy + dz * dz
    if dirLenSq < 0.0001 then
        local dist = math.sqrt(px * px + py * py + pz * pz)
        local collisionRadius = bullet.collisionRadius + player.bodyRadius
        return dist <= collisionRadius, 0
    end

    local tRaw = (px * dx + py * dy + pz * dz) / dirLenSq
    -- 球心在枪口后方(tRaw<0)时不判定命中:
    -- 起点位于球内时, 只有目标位于枪口前方才算命中,
    -- 防止同位置玩家朝任意方向开枪都因 t=0 命中
    if tRaw < 0 then
        return false, 0
    end
    ---@type number
    local t = math.min(1, tRaw)

    local closestX = bullet.prevPos.x + t * dx
    local closestY = bullet.prevPos.y + t * dy
    local closestZ = bullet.prevPos.z + t * dz

    local distX = player.pos.x - closestX
    local distY = playerCenterY - closestY
    local distZ = player.pos.z - closestZ
    local distSq = distX * distX + distY * distY + distZ * distZ

    local collisionRadius = bullet.collisionRadius + player.bodyRadius
    if distSq <= collisionRadius * collisionRadius then
        return true, t
    end

    return false, 0
end

--- 线段 vs AABB 碰撞检测 (slab法), 盒按 r 向外扩展
---@param ox number              起点X
---@param oy number              起点Y
---@param oz number              起点Z
---@param dx number              位移X
---@param dy number              位移Y
---@param dz number              位移Z
---@param b  Map3DCollideBoxType 目标盒(绝对坐标)
---@param r  number              扩展半径
---@return number | nil 命中比例t(0~1), 未命中返回nil
function Map3D:RayAABB(ox, oy, oz, dx, dy, dz, b, r)
    ---@type number
    local tmin = 0
    ---@type number
    local tmax = 1

    -- X 轴
    if math.abs(dx) < 0.000001 then
        if ox < b.x - b.hw - r or ox > b.x + b.hw + r then return nil end
    else
        local inv = 1 / dx
        local t1 = (b.x - b.hw - r - ox) * inv
        local t2 = (b.x + b.hw + r - ox) * inv
        if t1 > t2 then
            t1, t2 = t2, t1
        end
        if t1 > tmin then tmin = t1 end
        if t2 < tmax then tmax = t2 end
        if tmin > tmax then return nil end
    end

    -- Y 轴
    if math.abs(dy) < 0.000001 then
        if oy < b.y - b.hh - r or oy > b.y + b.hh + r then return nil end
    else
        local inv = 1 / dy
        local t1 = (b.y - b.hh - r - oy) * inv
        local t2 = (b.y + b.hh + r - oy) * inv
        if t1 > t2 then
            t1, t2 = t2, t1
        end
        if t1 > tmin then tmin = t1 end
        if t2 < tmax then tmax = t2 end
        if tmin > tmax then return nil end
    end

    -- Z 轴
    if math.abs(dz) < 0.000001 then
        if oz < b.z - b.hd - r or oz > b.z + b.hd + r then return nil end
    else
        local inv = 1 / dz
        local t1 = (b.z - b.hd - r - oz) * inv
        local t2 = (b.z + b.hd + r - oz) * inv
        if t1 > t2 then
            t1, t2 = t2, t1
        end
        if t1 > tmin then tmin = t1 end
        if t2 < tmax then tmax = t2 end
        if tmin > tmax then return nil end
    end

    if tmin <= 1 then
        return tmin
    end
    return nil
end

--- 子弹与墙体/建筑碰撞检测 (CCD): 检测子弹本帧位移线段是否穿过任何碰撞盒
---@param bullet Map3DBulletType
---@return number | nil 最近命中比例t(0~1), 未命中返回nil
function Map3D:CheckBulletWallCCD(bullet)
    local dx = bullet.pos.x - bullet.prevPos.x
    local dy = bullet.pos.y - bullet.prevPos.y
    local dz = bullet.pos.z - bullet.prevPos.z

    local r = bullet.collisionRadius
    ---@type number
    local bestT = 2

    for i = 1, #self.collideBoxes do
        local b = self.collideBoxes[i]
        local t = self:RayAABB(bullet.prevPos.x, bullet.prevPos.y, bullet.prevPos.z, dx, dy, dz, b, r)
        if t ~= nil and t < bestT then
            bestT = t
        end
    end

    if bestT <= 1 then
        return bestT
    end
    return nil
end

--- 子弹与环境(地面/地图边界)碰撞检测 (CCD)
--- 检测本帧位移线段是否穿过:
---   1. 地面平面 y = groundY (防止向下射击子弹钻入地下)
---   2. 地图边界盒 [0, size] 的六个面 (防止向上/出界射击子弹飞出地图)
--- 与墙体碰撞一样返回 [0,1] 内的命中比例t, 参与 minT 仲裁
---@param bullet Map3DBulletType
---@return number | nil 最近命中比例t(0~1), 未命中返回nil
function Map3D:CheckBulletEnvCCD(bullet)
    local dx = bullet.pos.x - bullet.prevPos.x
    local dy = bullet.pos.y - bullet.prevPos.y
    local dz = bullet.pos.z - bullet.prevPos.z
    local ox = bullet.prevPos.x
    local oy = bullet.prevPos.y
    local oz = bullet.prevPos.z

    local mapSize = self:GetSize()
    ---@type number
    local bestT = 2

    -- 地面平面: 只有向下运动才可能命中
    if dy < -0.000001 then
        local t = (self.groundY - oy) / dy
        if t > 0 and t <= 1 and t < bestT then
            bestT = t
        end
    end

    -- 地图边界: 各轴离开 [0, size] 的方向上的面
    local function checkAxisExit(o, d, max)
        if math.abs(d) >= 0.000001 then
            local t = d > 0 and (max - o) / d or -o / d
            if t > 0 and t <= 1 and t < bestT then
                bestT = t
            end
        end
    end
    checkAxisExit(ox, dx, mapSize.x)
    checkAxisExit(oy, dy, mapSize.y)
    checkAxisExit(oz, dz, mapSize.z)

    if bestT <= 1 then
        return bestT
    end
    return nil
end

-- 通知周围玩家子弹击中墙体/建筑
---@param bulletId  string
---@param shooterId string
---@param pos       Vec3f  碰撞点(绝对坐标)
function Map3D:NotifyBulletWallHit(bulletId, shooterId, pos)
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")

    local range = { x = pos.x - 10000, y = pos.y - 10000, z = pos.z - 10000, w = 20000, h = 20000, d = 20000 }
    local list = {}
    local seen = {}
    Map3DOctree.OcQuery(self.map3DOctree, range, list, seen)

    ---@type ProtoLua_ProtoCSMap3DNotifyBulletWallHit
    local wallHitPayload = {
        bulletId = bulletId,
        shooterId = shooterId,
        x = math.floor(pos.x),
        y = math.floor(pos.y),
        z = math.floor(pos.z)
    }

    for _, pl in pairs(list) do
        local player = PlayerMgr.GetPlayerByUserId(pl.userId)
        if player ~= nil then
            MsgHandler:Send2Client(
                player:GetClientGID(), player:GetWorkerIdx(),
                ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_BULLET_WALL_HIT, wallHitPayload
            )
        end
    end
end

-- 通知玩家被击中
function Map3D:NotifyPlayerHit(bulletId, targetId, pos)
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")

    local targetPlayer = PlayerMgr.GetPlayerByUserId(targetId)
    if targetPlayer == nil then return end

    ---@type ProtoLua_ProtoCSMap3DNotifyHitPlayer
    local hitProto = {
        bulletId = bulletId,
        targetId = targetId,
        damage = 100,
        targetX = math.floor(pos.x),
        targetY = math.floor(pos.y),
        targetZ = math.floor(pos.z)
    }
    MsgHandler:Send2Client(
        targetPlayer:GetClientGID(), targetPlayer:GetWorkerIdx(), ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_HIT_PLAYER,
        hitProto
    )

    ---@type ProtoLua_ProtoCSMap3DNotifyPlayerHurt
    local hurtProto = {
        targetId = targetId,
        hp = 90,
        maxHp = 200,
        damage = 100,
        x = math.floor(pos.x),
        y = math.floor(pos.y),
        z = math.floor(pos.z)
    }
    MsgHandler:Send2Client(
        targetPlayer:GetClientGID(), targetPlayer:GetWorkerIdx(),
        ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_PLAYER_HURT, hurtProto
    )
end

---@param timeMS integer
function Map3D:FixedUpdate(timeMS)
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")

    for userId, mapPlayer in pairs(self.players) do
        -- 睡觉中的玩家被服务器冻结: 不物理移动 (位置锁定在床上)
        if mapPlayer.sleepBedId == nil then
            self:PlayerPhysicsMove(mapPlayer)
        end
    end

    -- 玩家间分离碰撞, 防止穿模重叠 (在子弹碰撞检测前, 保证用最新位置判定)
    self:UpdatePlayerSeparation()

    self:UpdateBullets()

    for userId, mapPlayer in pairs(self.players) do
        local range = {
            x = mapPlayer.pos.x - 600,
            y = mapPlayer.pos.y - 600,
            z = mapPlayer.pos.z - 600,
            w = 1200,
            h = 1200,
            d = 1200
        }
        local list = {}
        local seen = {}
        Map3DOctree.OcQuery(self.map3DOctree, range, list, seen)

        ---@type table<integer, ProtoLua_ProtoMap3DPlayerPayload>
        local playersPayload = {}
        for _, o in ipairs(list) do
            ---@type Map3DPlayerType
            local pl = self.players[o.userId]
            playersPayload[#playersPayload + 1] = {
                userId = pl.userId,
                x = math.floor(pl.pos.x),
                y = math.floor(pl.pos.y),
                z = math.floor(pl.pos.z),
                -- 速度×VEL_DATA_SCALE(1000)后取整: 原始速度多为小数, 直接 floor 正负量化不对称
                vX = math.floor(pl.v.x * VEL_DATA_SCALE),
                vY = math.floor(pl.v.y * VEL_DATA_SCALE),
                vZ = math.floor(pl.v.z * VEL_DATA_SCALE),
                lastSeq = pl.lastSeq,
                lastClientTime = pl.lastClientTime
            }
        end

        ---@type ProtoLua_ProtoCSMap3DNotifyStateData
        local protoCSMap3DNotifyStateData = { serverTime = tostring(timeMS), players = playersPayload }

        local loopPlayer = PlayerMgr.GetPlayerByUserId(userId)
        if loopPlayer ~= nil then
            MsgHandler:Send2Client(
                loopPlayer:GetClientGID(), loopPlayer:GetWorkerIdx(),
                ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP3D_NOTIFY_STATE_DATA, protoCSMap3DNotifyStateData
            )
        end
    end
end

return Map3D
