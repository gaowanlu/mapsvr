---@class Map:MapType
local Map         = require("MapData")
local Log         = require("Log")

local TimeMgr     = require("TimeMgrLogic")
local MapQuadTree = require("MapQuadTreeLogic")

-- 构造新的Map对象
---@param mapId integer 地图ID
---@return Map 新的地图对象
function Map.new(mapId)
    ---@type Map
    local self = setmetatable({}, Map); -- 本质是 setmetatable({}, {__index = Map})

    -- 模拟Map的DB字段
    self.MapDbData = {
        id = mapId,
        name = "Map_" .. tostring(mapId),
        TICK_RATE = 20,
        DT_MS = 50,
        lastTickTimeMS = 0,
        durationAccumulator = 0
    };

    -- 地图相关信息
    ---@type TileMapType
    self.tileMap = {
        tileSize = 50,
        width = 4000,  -- 地图宽瓦片个数
        height = 4000, -- 地图高瓦片个数
        data = {}      -- 4000*4000=1600 0000
    };
    -- 初始化tileMap.data
    -- for i = 0, self.tileMap.width * self.tileMap.height do
    --     self.tileMap.data[i] = 0 -- 设为默认值
    -- end

    -- 地图内的Player
    ---@type table<string,MapPlayerType>
    self.players = {};

    -- 四叉树
    self.mapQuadTree = MapQuadTree.new(0, 0, self.tileMap.width * self.tileMap.tileSize,
        self.tileMap.height * self.tileMap.tileSize, 0);

    return self
end

---@return MapDbDataType
function Map:GetMapDbData()
    return self.MapDbData;
end

---@return integer
function Map:GetLastTickTimeMS()
    return self:GetMapDbData().lastTickTimeMS;
end

---@return integer
function Map:GetMapId()
    return self:GetMapDbData().id;
end

---@return integer
function Map:GetTileSize()
    return self.tileMap.tileSize;
end

---@return integer
function Map:GetTileMapWidth()
    return self.tileMap.width;
end

---@return integer
function Map:GetTileMapHeight()
    return self.tileMap.height;
end

---@param userId string
---@return MapPlayerType
function Map:GetMapPlayerByUserId(userId)
    return self.players[userId]
end

function Map:OnTick()
    local timeMS = TimeMgr.GetMS()

    if self.MapDbData.lastTickTimeMS <= 0 then
        self.MapDbData.lastTickTimeMS = timeMS;
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

-- 所有玩家出生点相同（地图中心）
function Map:FindSpawnPoint()
    local mapW = self.tileMap.width * self.tileMap.tileSize
    local mapH = self.tileMap.height * self.tileMap.tileSize
    return { x = math.floor(mapW / 2), y = math.floor(mapH / 2) }
end

-- 新玩家加入地图
---@param playerId string
---@param userId string
---@return boolean
function Map:PlayerJoinMap(playerId, userId)
    if self.players[userId] ~= nil then
        return false;
    end

    Log:Error("NewPlayerJoinMap id %d playerId %s userId %s", self.MapDbData.id, playerId, userId)

    local spawnPoint = self:FindSpawnPoint();

    ---@type MapPlayerType
    local newMapPlayer = {
        playerId = playerId,
        userId = userId,
        x = spawnPoint.x,
        y = spawnPoint.y,
        vX = 0,
        vY = 0,
        dirX = 0,
        dirY = 0,
        maxSpeed = 0.1,    -- 最大速度 目标最大速度 px/ms 100px/s
        accel = 1,         -- 加速度 px/ms^2
        speedRatio = 1000, -- 放大倍数

        bodyRadius = 12,
        bodyMass = 1,
        friction = 1.0, -- 无摩擦
        bounce = 0.40,

        lastSeq = 0,
        lastClientTime = "0",
        quadTree = nil
    };

    self.players[userId] = newMapPlayer;

    -- 加入地图四叉树
    MapQuadTree.QtInert(self.mapQuadTree, newMapPlayer);

    return true
end

-- 玩家离开地图
---@param userId string
---@return boolean
function Map:PlayerExitMap(userId)
    Log:Error("PlayerExitMap id %d userId %s", self.MapDbData.id, userId)

    ---@type MapPlayerType
    local targetPlayer = self.players[userId]

    if targetPlayer ~= nil then
        -- 将玩家从地图四叉树中移除
        if targetPlayer.mapQuadTree ~= nil then
            MapQuadTree.RemoveItemFromList(targetPlayer.mapQuadTree, targetPlayer.userId);

            targetPlayer.mapQuadTree = nil;
        end

        self.players[userId] = nil
        return true
    end

    return false
end

---@param mapPlayer MapPlayerType
function Map:PlayerPhysicsMove(mapPlayer)
    --- 内联 math.sign：返回v的符号(1,-1,0)
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

    -- 计算目标速度（由方向输入 dirX、dirY 和 最大速度maxSpeed决定）
    -- 目标的X速度
    local targetVx = (mapPlayer.dirX * mapPlayer.speedRatio) * mapPlayer.maxSpeed
    -- 目标的Y速度
    local targetVy = (mapPlayer.dirY * mapPlayer.speedRatio) * mapPlayer.maxSpeed
    targetVx = math.floor(targetVx);
    targetVy = math.floor(targetVy);

    -- 当前速度到目标速度的差值
    local deltaVx = targetVx - mapPlayer.vX -- 当前vX需要朝哪个方向变化
    local deltaVy = targetVy - mapPlayer.vY -- 当前vY需要朝哪个方向变化

    -- 每帧最大可改变的速度（加速度限制）
    -- accel * DT = 每帧最多加多少速度
    local maxDeltaV = mapPlayer.accel * self:GetMapDbData().DT_MS;
    maxDeltaV = math.floor(maxDeltaV);

    local maxDeltaVX = math.abs(math.floor(maxDeltaV * mapPlayer.dirX));
    local maxDeltaVY = math.abs(math.floor(maxDeltaV * mapPlayer.dirY));

    -- X轴速度更新（带加速度限制）
    if maxDeltaVX ~= 0 and math.abs(deltaVx) > maxDeltaVX then
        -- 需要加速：按符号方向增加 maxDeltaV
        mapPlayer.vX = mapPlayer.vX + sign(deltaVx) * maxDeltaVX;
    else
        -- 可以直接到达目标速度
        mapPlayer.vX = targetVx;
    end

    -- Y轴速度更新（加速度限制）
    if maxDeltaVY ~= 0 and math.abs(deltaVy) > maxDeltaVY then
        mapPlayer.vY = mapPlayer.vY + sign(deltaVy) * maxDeltaVY;
    else
        mapPlayer.vY = targetVy;
    end

    -- 根据速度移动位置
    -- mapPlayer.x / mapPlayer.y 是坐标，速度 * DT_MS 是位移
    mapPlayer.x = mapPlayer.x + math.floor((mapPlayer.vX * self:GetMapDbData().DT_MS) / mapPlayer.speedRatio);
    mapPlayer.y = mapPlayer.y + math.floor((mapPlayer.vY * self:GetMapDbData().DT_MS) / mapPlayer.speedRatio);

    -- 摩擦力（阻尼）
    -- 每帧速度 *= friction，使速度逐渐衰减
    mapPlayer.vX = math.floor(mapPlayer.vX * mapPlayer.friction);
    mapPlayer.vY = math.floor(mapPlayer.vY * mapPlayer.friction);

    -- 地图边界控制：限制物体不允许跑出地图
    local mapPxWidth = self.tileMap.width * self.tileMap.tileSize                                 -- 地图像素宽度
    local mapPxHeight = self.tileMap.height * self.tileMap.tileSize                               -- 地图像素高度
    local playerRadius = mapPlayer.bodyRadius                                                     -- 玩家半径（防止部分穿出）

    if mapPlayer.x < playerRadius then mapPlayer.x = playerRadius end                             -- 左边界
    if mapPlayer.y < playerRadius then mapPlayer.y = playerRadius end                             -- 上边界
    if mapPlayer.x > mapPxWidth - playerRadius then mapPlayer.x = mapPxWidth - playerRadius end   -- 右边界
    if mapPlayer.y > mapPxHeight - playerRadius then mapPlayer.y = mapPxHeight - playerRadius end -- 下边界

    -- 从四叉树中先移除这个玩家 然后再插入 做到QuadTree更新
    if mapPlayer.mapQuadTree ~= nil then
        MapQuadTree.RemoveItemFromList(mapPlayer.mapQuadTree, mapPlayer.userId);

        mapPlayer.mapQuadTree = nil;
    end

    MapQuadTree.QtInert(self.mapQuadTree, mapPlayer);
end

---@param timeMS integer
function Map:FixedUpdate(timeMS)
    local MsgHandler = require("MsgHandlerLogic")
    local PlayerMgr = require("PlayerMgrLogic")

    -- Log:Error("MapId %d FixedUpdate FinSpawnPoint x %d y %d", self.MapDbData.id, self:FindSpawnPoint().x,
    --     self:FindSpawnPoint().y)

    for userId, mapPlayer in pairs(self.players) do
        self:PlayerPhysicsMove(mapPlayer);
    end

    -- 为地图中每个玩家同步状态
    for userId, mapPlayer in pairs(self.players) do
        local range = { x = mapPlayer.x - 600, y = mapPlayer.y - 600, w = 1200, h = 1200 };
        local list = {}
        local seen = {}

        MapQuadTree.QtQuery(self.mapQuadTree, range, list, seen)

        ---@type table<integer,ProtoLua_ProtoMapPlayerPayload>
        local playersPayload = {}
        for _, o in ipairs(list) do
            ---@type MapPlayerType
            local pl = self.players[o.userId];

            playersPayload[#playersPayload + 1] = {
                userId = o.userId,
                x = math.modf(pl.x) or 0,
                y = math.modf(pl.y) or 0,
                vX = math.modf(pl.vX) or 0,
                vY = math.modf(pl.vY) or 0,
                lastSeq = math.modf(pl.lastSeq) or 0,
                lastClientTime = pl.lastClientTime
            };
        end

        if #playersPayload == 0 then
            Log:Error('players playersPayload len %d', #playersPayload)
        end

        ---@type ProtoLua_ProtoCSMapNotifyStateData
        local protoCSMapNotifyStateData = {
            serverTime = tostring(timeMS),
            players = playersPayload
        };

        local loopPlayer = PlayerMgr.GetPlayerByUserId(userId)
        if loopPlayer ~= nil then
            MsgHandler:Send2Client(loopPlayer:GetClientGID(), loopPlayer:GetWorkerIdx(),
                ProtoLua_ProtoCmd.PROTO_CMD_CS_MAP_NOTIFY_STATE_DATA, protoCSMapNotifyStateData);
        end
    end
end

---@param userId string
---@param dirX number
---@param dirY number
---@param seq number
---@param clientTime string
function Map:MapPlayerInput(userId, dirX, dirY, seq, clientTime)
    local mapPlayer = self:GetMapPlayerByUserId(userId);
    if mapPlayer == nil then
        return
    end

    if mapPlayer.lastSeq >= avant.UINT32_MAX then
        mapPlayer.lastSeq = 0;
    end

    if mapPlayer.lastSeq + 1 ~= seq then
        return
    end

    -- 计算向量长度
    local len = math.sqrt(dirX * dirX + dirY * dirY);

    if len > 0.0001 then
        -- 服务器强制归一化
        dirX = dirX / len;
        dirY = dirY / len;
    else
        dirX = 0;
        dirY = 0;
    end

    mapPlayer.dirX = dirX;
    mapPlayer.dirY = dirY;
    mapPlayer.lastSeq = seq;
    mapPlayer.lastClientTime = clientTime;
end

return Map;
