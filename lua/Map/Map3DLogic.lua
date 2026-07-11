---@class Map3D: Map3DType
local Map3D = require("Map3DData")
local Log = require("Log")
local TimeMgr = require("TimeMgrLogic")
local Map3DOctree = require("Map3DOctreeLogic")
local NumericBigInt = require("NumericBigIntLogic")
local AlgorithmRandom = require("AlgorithmRandomLogic")

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

    -- 八叉树
    self.map3DOctree = Map3DOctree.new(0, 0, 0, self:GetSize().x, self:GetSize().y, self:GetSize().z, 0)

    return self
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

function Map3D:OnTick()
    local timeMS = TimeMgr.GetMS()
    -- Log:Error("MS %s", tostring(TimeMgr.GetMS()));
    -- Log:Error("S %s", tostring(TimeMgr.GetS()));
    -- Log:Error("NS %s", tostring(TimeMgr.GetNS()));

    if self.MapDbData.lastTickTimeMS <= 0 then
        self.MapDbData.lastTickTimeMS = timeMS
    end

    local frameTime = timeMS - self.MapDbData.lastTickTimeMS
    if frameTime > 250 then
        frameTime = 250 -- 防止卡顿时爆炸
    end

    self.MapDbData.lastTickTimeMS = timeMS
    self.MapDbData.durationAccumulator = self.MapDbData.durationAccumulator + frameTime

    while self.MapDbData.durationAccumulator >= self.MapDbData.DT_MS do
        -- 一次固定步长的逻辑更新
        self:FixedUpdate(timeMS)
        self.MapDbData.durationAccumulator = self.MapDbData.durationAccumulator - self.MapDbData.DT_MS
    end
end

--- 计算出生点
---@return Vec3f
function Map3D:FindSpawnPoint()
    local x = math.floor(self.MapDbData.size.x / 2)
    local y = math.floor(self.MapDbData.size.y / 2)
    local z = math.floor(self.MapDbData.size.z / 2)
    return { x = x, y = y, z = z }
end

-- 新玩家加入地图
---@param playerId string
---@param userId   string
---@return boolean
function Map3D:PlayerJoinMap(playerId, userId)
    if self.players[userId] ~= nil then
        return false
    end

    Log:Error(
        "Map3D PlayerJoinMap id %s playerId %s userId %s", tostring(self.MapDbData.id), tostring(playerId),
        tostring(userId)
    )

    local spawnPoint = self:FindSpawnPoint()

    ---@type Map3DPlayerType
    local newMap3DPlayer = {
        userId = userId,
        pos = spawnPoint,
        v = { x = 0, y = 0, z = 0 },
        gravity = 1,
        weight = 1,
        lastSeq = 0,
        lastClientTime = "0",
        dir = { x = 0, y = 0, z = 0 },
        speedRatio = 1000,
        maxSpeed = 0.05, -- 最大速度 目标最大速度 px/ms 100px/s
        accel = 1,       -- 加速度 px/ms^2
        friction = 1.0,  -- 无摩擦
        bodyRadius = 12,
        octree = nil
    }

    self.players[userId] = newMap3DPlayer

    -- 加入地图八叉树
    Map3DOctree.OcInsert(self.map3DOctree, newMap3DPlayer)

    return true
end

-- 玩家离开地图
---@param userId string
---@return boolean
function Map3D:PlayerExitMap(userId)
    Log:Error("Map3D PlayerExitMap id %s userId %s", tostring(self.MapDbData.id), userId)

    ---@type Map3DPlayerType
    local targetPlayer = self.players[userId]
    if targetPlayer ~= nil then
        -- 将玩家从八叉树中移除
        if targetPlayer.map3DOctree ~= nil then
            Map3DOctree.RemoveItemFromList(targetPlayer.map3DOctree, targetPlayer.userId)

            targetPlayer.map3DOctree = nil
        end

        self.players[userId] = nil
        return true
    end

    return false
end

---@param userId     string
---@param dirX       number
---@param dirY       number
---@param dirZ       number
---@param seq        integer
---@param clientTime string
function Map3D:MapPlayerInput(userId, dirX, dirY, dirZ, seq, clientTime)
    local map3DPlayer = self.players[userId]

    if map3DPlayer == nil then
        return
    end

    if map3DPlayer.lastSeq >= avant.UINT32_MAX then
        map3DPlayer.lastSeq = 0
    end

    if seq ~= map3DPlayer.lastSeq + 1 then
        Log:Error(
            "userId %s map3DPlayer.lastSeq %s + 1 ~= seq %s in mapId %s", tostring(userId),
            tostring(map3DPlayer.lastSeq), tostring(seq), tostring(self:GetMapId())
        )
        return
    end

    -- 计算向量长度
    local len = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)

    if len > 0.0001 then
        -- 服务器强制归一化
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
    map3DPlayer.lastSeq = seq
    map3DPlayer.lastClientTime = clientTime
end

---@param mapPlayer Map3DPlayerType
function Map3D:PlayerPhysicsMove(mapPlayer)
    --- 返回v的符号(1,-1,0)
    ---@return number
    local function sign(v)
        if v > 0 then
            return 1
        elseif v < 0 then
            return -1
        else
            return 0
        end
    end

    -- 计算目标速度（由方向输入 dirX、dirY、dirZ 和 最大速度 maxSpeed 决定）
    -- 目标的X、Y、Z速度
    local targetVx = (mapPlayer.dir.x * mapPlayer.speedRatio) * mapPlayer.maxSpeed
    local targetVy = (mapPlayer.dir.y * mapPlayer.speedRatio) * mapPlayer.maxSpeed
    local targetVz = (mapPlayer.dir.z * mapPlayer.speedRatio) * mapPlayer.maxSpeed

    targetVx = math.floor(targetVx)
    targetVy = math.floor(targetVy)
    targetVz = math.floor(targetVz)

    -- 当前速度到目标速度的差值
    local deltaVx = targetVx - mapPlayer.v.x -- 当前vX需要朝哪个方向变化
    local deltaVy = targetVy - mapPlayer.v.y -- 当前vY需要朝哪个方向变化
    local deltaVz = targetVz - mapPlayer.v.z -- 当前vZ需要朝哪个方向变化

    -- 每帧最大可改变的速度（加速度限制）
    -- accel * DT = 每帧最多加多少速度
    local maxDeltaV = mapPlayer.accel * self:GetMapDbData().DT_MS
    maxDeltaV = math.floor(maxDeltaV)

    local maxDeltaVX = math.abs(math.floor(maxDeltaV * mapPlayer.dir.x))
    local maxDeltaVY = math.abs(math.floor(maxDeltaV * mapPlayer.dir.y))
    local maxDeltaVZ = math.abs(math.floor(maxDeltaV * mapPlayer.dir.z))

    -- X轴速度更新（带加速度限制）
    if maxDeltaVX ~= 0 and math.abs(deltaVx) > maxDeltaVX then
        -- 需要加速，按符号方向增加 maxDeltaV
        mapPlayer.v.x = mapPlayer.v.x + sign(deltaVx) * maxDeltaVX
    else
        -- 可以直接到达目标速度
        mapPlayer.v.x = targetVx
    end

    -- Y轴速度更新（加速度限制）
    if maxDeltaVY ~= 0 and math.abs(deltaVy) > maxDeltaVY then
        mapPlayer.v.y = mapPlayer.v.y + sign(deltaVy) * maxDeltaVY
    else
        mapPlayer.v.y = targetVy
    end

    -- Z轴速度更新（加速度限制）
    if maxDeltaVZ ~= 0 and math.abs(deltaVz) > maxDeltaVZ then
        mapPlayer.v.z = mapPlayer.v.z + sign(deltaVz) * maxDeltaVZ
    else
        mapPlayer.v.z = targetVz
    end

    -- 根据速度移动位置
    -- mapPlayer.pos.x / mapPlayer.pos.y / mapPlayer.pos.z 是坐标，速度 * DT_MS 是位移
    mapPlayer.pos.x = mapPlayer.pos.x + math.floor((mapPlayer.v.x * self:GetMapDbData().DT_MS) / mapPlayer.speedRatio)
    mapPlayer.pos.y = mapPlayer.pos.y + math.floor((mapPlayer.v.y * self:GetMapDbData().DT_MS) / mapPlayer.speedRatio)
    mapPlayer.pos.z = mapPlayer.pos.z + math.floor((mapPlayer.v.z * self:GetMapDbData().DT_MS) / mapPlayer.speedRatio)

    -- 摩擦力（阻尼）
    -- 每帧速度*=friction,使速度逐渐衰减
    mapPlayer.v.x = math.floor(mapPlayer.v.x * mapPlayer.friction)
    mapPlayer.v.y = math.floor(mapPlayer.v.y * mapPlayer.friction)
    mapPlayer.v.z = math.floor(mapPlayer.v.z * mapPlayer.friction)

    -- 地图边界控制，限制物体不允许跑出地图
    local mapSize = self:GetSize()
    local playerRadius = mapPlayer.bodyRadius -- 玩家半径（防止部分穿出）

    if mapPlayer.pos.x < playerRadius then mapPlayer.pos.x = playerRadius end -- 左边界
    if mapPlayer.pos.y < playerRadius then mapPlayer.pos.y = playerRadius end -- 上边界
    if mapPlayer.pos.z < playerRadius then mapPlayer.pos.z = playerRadius end -- 前边界
    if mapPlayer.pos.x > mapSize.x - playerRadius then mapPlayer.pos.x = mapSize.x - playerRadius end -- 右边界
    if mapPlayer.pos.y > mapSize.y - playerRadius then mapPlayer.pos.y = mapSize.y - playerRadius end -- 下边界
    if mapPlayer.pos.z > mapSize.z - playerRadius then mapPlayer.pos.z = mapSize.z - playerRadius end -- 后边界

    -- 从八叉树中先移除这个玩家 然后再插入 做到Octree更新
    if mapPlayer.map3DOctree ~= nil then
        Map3DOctree.RemoveItemFromList(mapPlayer.map3DOctree, mapPlayer.userId)

        mapPlayer.map3DOctree = nil
    end

    Map3DOctree.OcInsert(self.map3DOctree, mapPlayer)
end

---@param timeMS integer
function Map3D:FixedUpdate(timeMS)
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")

    -- Log:Error("Map3D:FixedUpdate mapId %s", tostring(self.MapDbData.id));
    for userId, mapPlayer in pairs(self.players) do
        self:PlayerPhysicsMove(mapPlayer)
    end

    -- 为地图中每个玩家同步状态 PROTO_CMD_CS_MAP3D_NOTIFY_STATE_DATA
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
                x = math.floor(pl.pos.x) or 0,
                y = math.floor(pl.pos.y) or 0,
                z = math.floor(pl.pos.z) or 0,
                vX = math.floor(pl.v.x) or 0,
                vY = math.floor(pl.v.y) or 0,
                vZ = math.floor(pl.v.z) or 0,
                lastSeq = pl.lastSeq or 0,
                lastClientTime = pl.lastClientTime
            }
        end

        if #playersPayload == 0 then
            Log:Error('players playersPayload len %d', #playersPayload)
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
