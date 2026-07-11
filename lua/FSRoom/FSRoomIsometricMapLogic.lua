-- https://www.redblobgames.com/grids/parts/

---@class FSRoomIsometricMapTileType
---@field EMPTY string
---@field WALL string
---@field BORDER string

---@class FSRoomIsometricMapTilePos
---@field x integer
---@field y integer

---@class FSRoomIsometricMap
---@field DIRECTION4 table<integer,FSRoomIsometricMapTilePos> 移动方向4方向
---@field DIRECTION8 table<integer,FSRoomIsometricMapTilePos> 移动方向8方向
---@field TILETYPES FSRoomIsometricMapTileType 瓦片类型
---@field width integer 宽度
---@field height integer 高度
---@field allow8Dir boolean 是否允许8方向移动
---@field tiles table<integer,table<integer,string>>
local FSRoomIsometricMap = require("FSRoomIsometricMapData");

FSRoomIsometricMap.DIRECTION4 = {
    { x = 0,  y = -1 },
    { x = 1,  y = 0 },
    { x = 0,  y = 1 },
    { x = -1, y = 0 }
};

FSRoomIsometricMap.DIRECTION8 = {
    { x = 0,  y = -1 },
    { x = 1,  y = -1 },
    { x = 1,  y = 0 },
    { x = 1,  y = 1 },
    { x = 0,  y = 1 },
    { x = -1, y = 1 },
    { x = -1, y = 0 },
    { x = -1, y = -1 }
};

FSRoomIsometricMap.TILETYPES = {
    EMPTY = '0',
    WALL = '1',
    BORDER = '2'
};

---@param width integer
---@param height integer
---@param allow8Dir boolean
function FSRoomIsometricMap.new(width, height, allow8Dir)
    ---@type FSRoomIsometricMap
    local self = setmetatable({}, FSRoomIsometricMap);

    self.width = width;
    self.height = height;
    self.allow8Dir = allow8Dir;
    self.tiles = {};

    -- 初始化地图
    for x = 1, width do
        self.tiles[x] = {};
        for y = 1, height do
            self.tiles[x][y] = FSRoomIsometricMap.TILETYPES.EMPTY;
        end
    end

    -- 设置边界墙
    self:SetBorderWalls();

    return self;
end

function FSRoomIsometricMap:SetBorderWalls()
    for x = 1, self.width do
        for y = 1, self.height do
            if x == 1 or x == self.width or y == 1 or y == self.height then
                self:SetTile(x, y, FSRoomIsometricMap.TILETYPES.BORDER);
            end
        end
    end
end

---@param x integer
---@param y integer
---@return boolean
function FSRoomIsometricMap:IsInBounds(x, y)
    return x >= 1 and x <= self.width and y >= 1 and y <= self.height;
end

---@param x integer
---@param y integer
---@param tileType string
function FSRoomIsometricMap:SetTile(x, y, tileType)
    if not self:IsInBounds(x, y) then
        return;
    end
    self.tiles[x][y] = tileType;
end

---@param x integer
---@param y integer
---@return string|nil
function FSRoomIsometricMap:GetTile(x, y)
    if not self:IsInBounds(x, y) then
        return nil;
    end
    return self.tiles[x][y];
end

---@param x integer
---@param y integer
---@return boolean
function FSRoomIsometricMap:IsWalkable(x, y)
    if not self:IsInBounds(x, y) then
        return false;
    end
    return self.tiles[x][y] == FSRoomIsometricMap.TILETYPES.EMPTY;
end

--- 计算两个瓦片之间的距离（A*启发式函数）
-- 必须保证 h(n) <= 实际代价d(n)，即低估才能保证最优性
---@return number
function FSRoomIsometricMap:Distance(x1, y1, x2, y2)
    local dx = math.abs(x1 - x2);
    local dy = math.abs(y1 - y2);

    if self.allow8Dir then
        -- 对角线移动距离（对角线代价1.414，直线代价1）
        -- 正确的启发式：对角线步数 * 1.414 + 直线步数 * 1
        local minD = math.min(dx, dy);
        local maxD = math.max(dx, dy);
        return minD * 1.414 + (maxD - minD) * 1;
    else
        -- 曼哈顿距离（4方向移动，代价都是1）
        return dx + dy;
    end
end

--- 相邻瓦片计算移动代价
---@param fromX integer
---@param fromY integer
---@param toX integer
---@param toY integer
---@return number
function FSRoomIsometricMap:MoveCost(fromX, fromY, toX, toY)
    if self.allow8Dir then
        local dx = math.abs(toX - fromX);
        local dy = math.abs(toY - fromY);
        if dx > 0 and dy > 0 then
            return 1.414; -- 对角线移动代价√2
        end
    end
    return 1; -- 直线移动代价
end

--- 获取邻居信息
---@param x integer
---@param y integer
---@return table<integer, FSRoomIsometricMapTilePos>
function FSRoomIsometricMap:GetNeighbors(x, y)
    ---@type table<integer,FSRoomIsometricMapTilePos>
    local neighbors = {};

    ---@type table<integer,FSRoomIsometricMapTilePos>
    local directions = self.allow8Dir and FSRoomIsometricMap.DIRECTION8 or FSRoomIsometricMap.DIRECTION4;

    for _, dir in ipairs(directions) do
        local nx = x + dir.x;
        local ny = y + dir.y;

        if self:IsInBounds(nx, ny) and self:IsWalkable(nx, ny) then
            -- 8方向时，检查对角线是否被阻挡
            if self.allow8Dir and (dir.x ~= 0 and dir.y ~= 0) then
                -- 对角线移动需要两侧都可通行
                local side1 = self:IsWalkable(x + dir.x, y);
                local side2 = self:IsWalkable(x, y + dir.y);
                if side1 and side2 then
                    table.insert(neighbors, { x = nx, y = ny });
                end
            else
                table.insert(neighbors, { x = nx, y = ny });
            end
        end
    end

    return neighbors;
end

-- 打印地图 等距视角
function FSRoomIsometricMap:Print()
    print("Isometric Map (" .. self.width .. "x" .. self.height .. ") [" ..
        (self.allow8Dir and "8-DIR" or "4-DIR") .. "]:");

    -- 简化的等距显示（菱形排列）
    for y = 1, self.height do
        local line = string.rep(" ", self.height - y);

        for x = 1, self.width do
            local tile = self:GetTile(x, y);
            if tile == FSRoomIsometricMap.TILETYPES.WALL or tile == FSRoomIsometricMap.TILETYPES.BORDER then
                line = line .. "🔶";
            else
                line = line .. "🔷";
            end
        end
        print(line);
    end
end

-- 打印地图 正交视角
function FSRoomIsometricMap:PrintOrthogonal()
    print("Orthogonal View (" .. self.width .. "x" .. self.height .. "):");
    for y = 1, self.height do
        local line = "";
        for x = 1, self.width do
            local tile = self:GetTile(x, y);
            if tile == FSRoomIsometricMap.TILETYPES.WALL or tile == FSRoomIsometricMap.TILETYPES.BORDER then
                line = line .. "🔶";
            else
                line = line .. "🔷";
            end
        end
        print(line);
    end
end

if not ... then
    local newIsometricMap4Dir = FSRoomIsometricMap.new(20, 20, false);
    newIsometricMap4Dir:Print();
    newIsometricMap4Dir:PrintOrthogonal();

    local newIsometricMap8Dir = FSRoomIsometricMap.new(20, 20, true);
    newIsometricMap8Dir:Print();
    newIsometricMap8Dir:PrintOrthogonal();
end

return FSRoomIsometricMap;
