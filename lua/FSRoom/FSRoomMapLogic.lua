---@class FSRoomMap
---@field TILE_EMPTY string 地图瓦片什么都没有
---@field TILE_WALL string 地图瓦片墙
---@field TILE_WATER string 地图瓦片水
---@field width integer 地图宽
---@field height integer 地图高
---@field tiles table<integer,table<integer,string>>
local FSRoomMap = require("FSRoomMapData");

local AlgorithmRandom = require("AlgorithmRandomLogic");

FSRoomMap.TILE_EMPTY = '0';
FSRoomMap.TILE_WALL = '1';
FSRoomMap.TILE_WATER = '2';

---@param width integer 地图宽
---@param height integer 地图高
---@return FSRoomMap
function FSRoomMap.new(width, height)
    ---@type FSRoomMap
    local self = setmetatable({}, FSRoomMap);

    self.width = width;
    self.height = height;
    self.tiles = {};

    -- 初始化空地图
    for y = 1, height do
        self.tiles[y] = {}
        for x = 1, width do
            self.tiles[y][x] = FSRoomMap.TILE_EMPTY;
        end
    end

    return self;
end

---@param x integer
---@param y integer
function FSRoomMap:IsValidPosition(x, y)
    return x >= 1 and x <= self.width and y >= 1 and y <= self.height;
end

---@param x integer
---@param y integer
---@param tileType string
function FSRoomMap:SetTile(x, y, tileType)
    if self:IsValidPosition(x, y) then
        self.tiles[y][x] = tileType;
    end
end

---@param x integer
---@param y integer
---@return string tileType
function FSRoomMap:GetTile(x, y)
    if self:IsValidPosition(x, y) then
        return self.tiles[y][x];
    end
    return FSRoomMap.TILE_WALL;
end

---@param x integer
---@param y integer
---@return boolean
function FSRoomMap:IsWalkable(x, y)
    if not self:IsValidPosition(x, y) then
        return false;
    end

    local tile = self:GetTile(x, y);
    return tile == FSRoomMap.TILE_EMPTY;
end

--- 两点直线距离
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return number
function FSRoomMap:GetDistance(x1, y1, x2, y2)
    local dx = x2 - x1;
    local dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
end

--- 两点曼哈顿距离
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return integer
function FSRoomMap:GetManhattanDistance(x1, y1, x2, y2)
    return math.ceil(math.abs(x2 - x1) + math.abs(y2 - y1));
end

--- 为地图生成边界墙
function FSRoomMap:GenerateBorderWalls()
    for x = 1, self.width do
        self:SetTile(x, 1, FSRoomMap.TILE_WALL);
        self:SetTile(x, self.height, FSRoomMap.TILE_WALL);
    end
    for y = 1, self.height do
        self:SetTile(1, y, FSRoomMap.TILE_WALL);
        self:SetTile(self.width, y, FSRoomMap.TILE_WALL);
    end
end

--- 随机设置一些障碍墙
---@param count integer 尝试随机生成n次
function FSRoomMap:GenerateRandomObstacles(count)
    for i = 1, count do
        local x = AlgorithmRandom.Random(2, self.width - 1);
        local y = AlgorithmRandom.Random(2, self.height - 1);
        self:SetTile(x, y, FSRoomMap.TILE_WALL);
    end
end

---@class FSRoomMapPoint
---@field x integer
---@field y integer

--- 简单的A* 路径查找 暂不支持对角线移动 暂不支持地形权重
---@param startX integer
---@param startY integer
---@param endX integer
---@param endY integer
---@return table<integer,FSRoomMapPoint>|nil
function FSRoomMap:FindPath(startX, startY, endX, endY)
    -- 如果终点不可行走，直接返回nil
    if not self:IsWalkable(endX, endY) then
        return nil;
    end

    -- 起点就是终点，路径就是自己
    if startX == endX and startY == endY then
        return { { x = startX, y = startY } };
    end

    -- 待评估节点集合
    ---@type table<integer,FSRoomMapPoint>
    local openSet = {};
    -- 已评估节点集合
    ---@type table<integer,boolean>
    local closedSet = {};

    -- 路径追踪表，记录每个节点来自哪里
    ---@type table<integer,FSRoomMapPoint>
    local cameFrom = {};

    -- 从起点到当前节点的实际代价
    ---@type table<integer,integer>
    local gScore = {};

    -- fScore = gScore + 启发式估价（曼哈顿距离）
    ---@type table<integer,integer>
    local fScore = {};

    -- 将二维坐标映射为唯一key，方便table索引
    local function NodeKey(x, y)
        return y * self.width + x
    end

    -- 从终点反向重建路径
    local function ReconstructPath(currentX, currentY)
        local path = { { x = currentX, y = currentY } };
        local key = NodeKey(currentX, currentY);

        -- 不断回溯 cameFrom 直到起点
        while cameFrom[key] ~= nil do
            local from = cameFrom[key];
            table.insert(path, 1, { x = from.x, y = from.y });
            key = NodeKey(from.x, from.y);
        end

        return path;
    end

    -- 初始化起点
    local startKey = NodeKey(startX, startY);
    openSet[startKey] = { x = startX, y = startY };
    gScore[startKey] = 0;
    fScore[startKey] = self:GetManhattanDistance(
        startX,
        startY,
        endX,
        endY
    );

    -- 主循环 只要 openSet 里还有节点就继续
    while next(openSet) do
        -- 从openSet中找fScore最小的节点
        ---@type integer|nil
        local currenyKey

        ---@type FSRoomMapPoint|nil
        local current
        local lowestF = math.huge

        for key, node in pairs(openSet) do
            if fScore[key] < lowestF then
                lowestF = fScore[key]
                currenyKey = key
                current = node
            end
        end

        if not current then break end

        -- 如果到达终点，回溯路径并返回
        if current.x == endX and current.y == endY then
            return ReconstructPath(current.x, current.y);
        end

        -- 将当前节点从 openSet 移入 closedSet
        openSet[currenyKey] = nil;
        closedSet[currenyKey] = true

        -- 四方向邻居（上下左右）
        ---@type table<integer,FSRoomMapPoint>
        local neighbors = {
            { x = current.x - 1, y = current.y },
            { x = current.x + 1, y = current.y },
            { x = current.x,     y = current.y - 1 },
            { x = current.x,     y = current.y + 1 }
        };

        -- 遍历邻居节点
        for _, neighbor in ipairs(neighbors) do
            local nx, ny = neighbor.x, neighbor.y;

            repeat
                if not self:IsWalkable(nx, ny) then
                    break;
                end

                -- 只处理可行走的格子
                local neighborKey = NodeKey(nx, ny);

                -- 已处理的节点直接跳过
                if closedSet[neighborKey] then
                    break;
                end

                -- 从当前节点走到邻居的代价
                local tentativeGScore = gScore[currenyKey] + 1

                -- 如果是新节点 或找到更短路径
                if not gScore[neighborKey] or tentativeGScore < gScore[neighborKey] then
                    -- 记录路径的来源
                    cameFrom[neighborKey] = {
                        x = current.x,
                        y = current.y
                    };

                    -- 更新g/f分数
                    gScore[neighborKey] = tentativeGScore
                    fScore[neighborKey] = self:GetManhattanDistance(nx, ny, endX, endY) + tentativeGScore;

                    -- 加入 openSet
                    openSet[neighborKey] = { x = nx, y = ny }
                end
            until true;
        end
    end

    -- openSet 为空仍未到达终点，说明无路可走
    return nil;
end

return FSRoomMap;
