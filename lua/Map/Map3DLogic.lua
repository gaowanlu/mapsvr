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

    -- 子弹管理
    ---@type table<string, Map3DBulletType>
    self.bullets = {}

    -- 八叉树
    self.map3DOctree = Map3DOctree.new(0, 0, 0, self:GetSize().x, self:GetSize().y, self:GetSize().z, 0)

    self.nextBulletIdSeq = 0

    return self
end

-- 获取最大射击距离（单位：px）
---@return integer
function Map3D:GetMaxShootDist()
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

--- 计算出生点
---@return Vec3f
function Map3D:FindSpawnPoint()
    local x = math.floor(self.MapDbData.size.x / 2)
    local y = math.floor(self.MapDbData.size.y / 2)
    local z = math.floor(self.MapDbData.size.z / 2)
    return { x = x, y = y, z = z }
end

-- 新玩家加入地图
---@param userId string
---@return boolean
function Map3D:PlayerJoinMap(userId)
    if self:GetMapPlayerByUserId(userId) ~= nil then
        Log:Error("Map3D PlayerJoinMap id %s userId %s already in map", tostring(self.MapDbData.id), tostring(userId))
        return false
    end

    local spawnPoint = self:FindSpawnPoint()

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
        groundY = spawnPoint.y,
        octree = nil
    }

    self.players[userId] = newMap3DPlayer
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
    local mapSize = self:GetSize()
    local playerRadius = mapPlayer.bodyRadius

    if mapPlayer.pos.x < playerRadius then mapPlayer.pos.x = playerRadius end
    if mapPlayer.pos.z < playerRadius then mapPlayer.pos.z = playerRadius end
    if mapPlayer.pos.x > mapSize.x - playerRadius then mapPlayer.pos.x = mapSize.x - playerRadius end
    if mapPlayer.pos.z > mapSize.z - playerRadius then mapPlayer.pos.z = mapSize.z - playerRadius end

    -- 更新八叉树
    if mapPlayer.map3DOctree ~= nil then
        Map3DOctree.RemoveItemFromList(mapPlayer.map3DOctree, mapPlayer.userId)
        mapPlayer.map3DOctree = nil
    end
    Map3DOctree.OcInsert(self.map3DOctree, mapPlayer)
end

-- 玩家射击
---@param shooterId  string 发射子弹的玩家的userId
---@param dirX       number 子弹方向向量X分量
---@param dirY       number 子弹方向向量Y分量
---@param dirZ       number 子弹方向向量Z分量
---@param shootDist  number 射击距离
---@param clientTime string 客户端射击时间
---@return string | nil 返回子弹ID
function Map3D:PlayerShoot(shooterId, dirX, dirY, dirZ, shootDist, clientTime)
    local shooter = self:GetMapPlayerByUserId(shooterId)
    if shooter == nil then return nil end

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

    self.nextBulletIdSeq = self.nextBulletIdSeq + 1
    local bulletId = tostring(self.nextBulletIdSeq)
    local now = TimeMgr.GetMS()

    -- 起点加上眼睛高度
    local muzzleOffset = shooter.bodyRadius
    local startPosX = shooter.pos.x + dirX * muzzleOffset
    local startPosY = shooter.pos.y + 2.0 + dirY * muzzleOffset
    local startPosZ = shooter.pos.z + dirZ * muzzleOffset

    local bulletSpeedPerMs = self:GetBulletSpeedRatio() / 1000
    local distLifeTime = math.floor(shootDist / bulletSpeedPerMs)
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
        isExpired = false
    }

    self.bullets[bulletId] = newBullet

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

        if timeMS - bullet.spawnTime > bullet.lifeTime then
            bullet.isExpired = true
            toRemove[#toRemove + 1] = bulletId
            goto continue
        end

        local speed = bullet.speedRatio / 1000 * self:GetMapDbData().DT_MS
        bullet.prevPos.x = bullet.pos.x
        bullet.prevPos.y = bullet.pos.y
        bullet.prevPos.z = bullet.pos.z
        bullet.pos.x = bullet.pos.x + bullet.dir.x * speed
        bullet.pos.y = bullet.pos.y + bullet.dir.y * speed
        bullet.pos.z = bullet.pos.z + bullet.dir.z * speed

        for userId, player in pairs(self.players) do
            if userId ~= bullet.shooterId then
                local hit, hitRatio = self:CheckBulletPlayerCCD(bullet, player)
                if hit then
                    local hitPos = {
                        x = bullet.prevPos.x + (bullet.pos.x - bullet.prevPos.x) * hitRatio,
                        y = bullet.prevPos.y + (bullet.pos.y - bullet.prevPos.y) * hitRatio,
                        z = bullet.prevPos.z + (bullet.pos.z - bullet.prevPos.z) * hitRatio
                    }
                    self:NotifyPlayerHit(bulletId, userId, hitPos)
                    bullet.isExpired = true
                    toRemove[#toRemove + 1] = bulletId
                    goto continue
                end
            end
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

    for _, bulletId in ipairs(toRemove) do
        self.bullets[bulletId] = nil
    end
end

--- CCD碰撞检测
function Map3D:CheckBulletPlayerCCD(bullet, player)
    local dx = bullet.pos.x - bullet.prevPos.x
    local dy = bullet.pos.y - bullet.prevPos.y
    local dz = bullet.pos.z - bullet.prevPos.z

    -- 玩家碰撞中心点在身体中部
    local playerCenterY = player.pos.y + 1.0

    local px = player.pos.x - bullet.prevPos.x
    local py = playerCenterY - bullet.prevPos.y
    local pz = player.pos.z - bullet.prevPos.z

    local dirLenSq = dx * dx + dy * dy + dz * dz
    if dirLenSq < 0.0001 then
        local dist = math.sqrt(px * px + py * py + pz * pz)
        local collisionRadius = bullet.collisionRadius + player.bodyRadius
        return dist <= collisionRadius, 0
    end

    local t = (px * dx + py * dy + pz * dz) / dirLenSq
    t = math.max(0, math.min(1, t))

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
        self:PlayerPhysicsMove(mapPlayer)
    end

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
                vX = math.floor(pl.v.x),
                vY = math.floor(pl.v.y),
                vZ = math.floor(pl.v.z),
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
