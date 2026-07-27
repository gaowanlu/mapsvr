-- https://www.redblobgames.com/grids/parts/

---@class FSRoomSquareMapTileType
---@field EMPTY  string
---@field WALL   string
---@field BORDER string

---@class FSRoomSquareMapTilePos
---@field x integer
---@field y integer

---@class FSRoomSquareMap
---@field DIRECTION4 table<integer, FSRoomSquareMapTilePos> 移动方向4方向
---@field DIRECTION8 table<integer, FSRoomSquareMapTilePos> 移动方向8方向
---@field TILETYPES  FSRoomSquareMapTileType                瓦片类型
---@field width      integer                                宽度
---@field height     integer                                高度
---@field allow8Dir  boolean                                是否允许8方向移动
---@field tiles      table<integer, table<integer, string>>
local FSRoomSquareMap = require("FSRoomSquareMapData")

FSRoomSquareMap.DIRECTION4 = {
    { x = 0, y = -1 }, -- 北
    { x = 1, y = 0 },  -- 东
    { x = 0, y = 1 },  -- 南
    { x = -1, y = 0 }  -- 西
}

FSRoomSquareMap.DIRECTION8 = {
    { x = 0, y = -1 }, -- 北
    { x = 1, y = -1 }, -- 东北
    { x = 1, y = 0 },  -- 东
    { x = 1, y = 1 },  -- 东南
    { x = 0, y = 1 },  -- 南
    { x = -1, y = 1 }, -- 西南
    { x = -1, y = 0 }, -- 西
    { x = -1, y = -1 } -- 西北
}

FSRoomSquareMap.TILETYPES = {
    EMPTY = '0', -- 可通行
    WALL = '1',  -- 墙（不可通行）
    BORDER = '2' -- 边界墙
}

---@param width     integer
---@param height    integer
---@param allow8Dir boolean
---@return FSRoomSquareMap
function FSRoomSquareMap.new(width, height, allow8Dir)
    ---@type FSRoomSquareMap
    local self = setmetatable({}, FSRoomSquareMap)
    self.width = width
    self.height = height
    self.allow8Dir = allow8Dir
    self.tiles = {}

    -- 初始化地图
    for x = 1, width do
        self.tiles[x] = {}
        for y = 1, height do
            self.tiles[x][y] = FSRoomSquareMap.TILETYPES.EMPTY
        end
    end

    -- 设置边界墙
    self:SetBorderWalls()

    return self
end

function FSRoomSquareMap:SetBorderWalls()
    for x = 1, self.width do
        for y = 1, self.height do
            if x == 1 or x == self.width or y == 1 or y == self.height then
                self:SetTile(x, y, FSRoomSquareMap.TILETYPES.BORDER)
            end
        end
    end
end

--- 检查瓦片位置是否合法
---@param x integer
---@param y integer
---@return boolean
function FSRoomSquareMap:IsInBounds(x, y)
    if x <= 0 or x > self.width then
        return false
    end
    if y <= 0 or y > self.height then
        return false
    end
    return true
end

---@param x        integer
---@param y        integer
---@param tileType string
function FSRoomSquareMap:SetTile(x, y, tileType)
    if not self:IsInBounds(x, y) then
        return
    end
    self.tiles[x][y] = tileType
end

---@param x integer
---@param y integer
---@return string | nil
function FSRoomSquareMap:GetTile(x, y)
    if not self:IsInBounds(x, y) then
        return nil
    end
    return self.tiles[x][y]
end

--- 检查瓦片是否可通行
---@param x integer
---@param y integer
---@return boolean
function FSRoomSquareMap:IsWalkable(x, y)
    if not self:IsInBounds(x, y) then
        return false
    end
    return self.tiles[x][y] == FSRoomSquareMap.TILETYPES.EMPTY
end

-- 计算两个瓦片之间的距离（A*启发式函数）
-- 必须保证 h(n) <= 实际代价d(n)，即低估才能保证最优性
---@return number
function FSRoomSquareMap:Distance(x1, y1, x2, y2)
    local dx = math.abs(x1 - x2)
    local dy = math.abs(y1 - y2)

    if self.allow8Dir then
        -- 对角线移动距离（对角线代价1.414，直线代价1）
        -- 正确的启发式：对角线步数 * 1.414 + 直线步数 * 1
        local minD = math.min(dx, dy)
        local maxD = math.max(dx, dy)
        return minD * 1.414 + (maxD - minD) * 1
    else
        -- 曼哈顿距离（4方向移动，代价都是1）
        return dx + dy
    end
end

--- 相邻瓦片计算移动代价
---@param fromX integer
---@param fromY integer
---@param toX   integer
---@param toY   integer
---@return number
function FSRoomSquareMap:MoveCost(fromX, fromY, toX, toY)
    if self.allow8Dir then
        local dx = math.abs(toX - fromX)
        local dy = math.abs(toY - fromY)
        if dx > 0 and dy > 0 then
            return 1.414 -- 对角线移动代价√2
        end
    end
    return 1 -- 直线移动代价
end

--- 获取邻居信息
---@param x integer
---@param y integer
---@return table<integer, FSRoomSquareMapTilePos>
function FSRoomSquareMap:GetNeighbors(x, y)
    ---@type table<integer, FSRoomSquareMapTilePos>
    local neighbors = {}

    ---@type table<integer, FSRoomSquareMapTilePos>
    local directions = self.allow8Dir and FSRoomSquareMap.DIRECTION8 or FSRoomSquareMap.DIRECTION4

    for _, dir in ipairs(directions) do
        local nx = x + dir.x
        local ny = y + dir.y

        if self:IsInBounds(nx, ny) and self:IsWalkable(nx, ny) then
            -- 8方向移动时，检查对角线是否被阻挡
            if self.allow8Dir and (dir.x ~= 0 and dir.y ~= 0) then
                -- 对角线移动需要两侧可通行
                local side1 = self:IsWalkable(x + dir.x, y)
                local side2 = self:IsWalkable(x, y + dir.y)
                if side1 and side2 then
                    table.insert(neighbors, { x = nx, y = ny })
                end
            else
                table.insert(neighbors, { x = nx, y = ny })
            end
        end
    end
    return neighbors
end

--- 打印地图
function FSRoomSquareMap:Print()
    print(
        "Square Map (" .. self.width .. "x" .. self.height .. ") [" .. (self.allow8Dir and "8-DIR" or "4-DIR") .. "]:"
    )
    for x = 1, self.width do
        local line = ""
        for y = 1, self.height do
            local tileType = self.tiles[x][y]
            if tileType == FSRoomSquareMap.TILETYPES.WALL or tileType == FSRoomSquareMap.TILETYPES.BORDER then
                line = line .. "🟨"
            else
                line = line .. "🟦"
            end
        end
        print(line)
    end
end

if not ... then
    local testDir4Map = FSRoomSquareMap.new(20, 20, true)
    testDir4Map:SetTile(10, 10, FSRoomSquareMap.TILETYPES.WALL)
    local testDir8Map = FSRoomSquareMap.new(20, 20, false)
    testDir8Map:SetTile(10, 10, FSRoomSquareMap.TILETYPES.WALL)
    testDir4Map:Print()
    testDir8Map:Print()
end

return FSRoomSquareMap
