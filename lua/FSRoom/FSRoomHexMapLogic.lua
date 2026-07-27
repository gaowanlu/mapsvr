-- https://www.redblobgames.com/grids/parts/

---@class FSRoomHexMapTilePos
---@field q integer
---@field r integer
---@field s integer

---@class FSRoomHexMapTileType
---@field EMPTY  string 可通行
---@field WALL   string 墙
---@field BORDER string 边界墙

---@class FSRoomHexMap
---@field DIRECTION6 table<integer, FSRoomHexMapTilePos>                    六边形方向顶尖朝上
---@field TILETYPES  FSRoomHexMapTileType
---@field width      integer
---@field height     integer
---@field tiles      table<integer, table<integer, table<integer, string>>>
local FSRoomHexMap = require("FSRoomHexMapData")

FSRoomHexMap.DIRECTION6 = {
    { q = 1, r = 0, s = -1 }, -- 东
    { q = 1, r = -1, s = 0 }, -- 东北
    { q = 0, r = -1, s = 1 }, -- 西北
    { q = -1, r = 0, s = 1 }, -- 西
    { q = -1, r = 1, s = 0 }, -- 西南
    { q = 0, r = 1, s = -1 }  -- 东南
}

FSRoomHexMap.TILETYPES = { EMPTY = '0', WALL = '1', BORDER = '2' }

---@param width  integer
---@param height integer
---@return FSRoomHexMap
function FSRoomHexMap.new(width, height)
    ---@type FSRoomHexMap
    local self = setmetatable({}, FSRoomHexMap)

    self.width = width
    self.height = height

    self.tiles = {}

    -- 初始化地图
    for q = 1, width do
        self.tiles[q] = {}
        for r = 1, height do
            self.tiles[q][r] = {}
            self.tiles[q][r][-q - r] = FSRoomHexMap.TILETYPES.EMPTY
        end
    end

    -- 设置边界墙
    self:SetBorderWalls()

    return self
end

-- 设置边界墙
function FSRoomHexMap:SetBorderWalls()
    for q = 1, self.width do
        for r = 1, self.height do
            if q == 1 or q == self.width or r == 1 or r == self.height then
                self:SetTile(q, r, FSRoomHexMap.TILETYPES.BORDER)
            end
        end
    end
end

--- 检查瓦片位置是否合法
---@param q integer
---@param r integer
function FSRoomHexMap:IsInBounds(q, r)
    return q >= 1 and q <= self.width and r >= 1 and r <= self.height
end

--- 设置瓦片
---@param q        integer
---@param r        integer
---@param tileType string
function FSRoomHexMap:SetTile(q, r, tileType)
    if not self:IsInBounds(q, r) then
        return
    end
    self.tiles[q][r][-q - r] = tileType
end

---@param q integer
---@param r integer
---@return string | nil
function FSRoomHexMap:GetTile(q, r)
    if not self:IsInBounds(q, r) then
        return nil
    end
    return self.tiles[q][r][-q - r]
end

---@param q integer
---@param r integer
---@return boolean
function FSRoomHexMap:IsWalkable(q, r)
    if not self:IsInBounds(q, r) then
        return false
    end
    return self.tiles[q][r][-q - r] == FSRoomHexMap.TILETYPES.EMPTY
end

--- 计算两个六边形之间的曼哈顿距离
---@param q1 integer
---@param r1 integer
---@param q2 integer
---@param r2 integer
---@return number
function FSRoomHexMap:Distance(q1, r1, q2, r2)
    local s1 = -q1 - r1
    local s2 = -q2 - r2
    return (math.abs(q1 - q2) + math.abs(r1 - r2) + math.abs(s1 - s2)) / 2
end

---@param q integer
---@param r integer
---@return table<integer, FSRoomHexMapTilePos>
function FSRoomHexMap:GetNeighbors(q, r)
    ---@type table<integer, FSRoomHexMapTilePos>
    local neighbors = {}

    for _, dir in ipairs(FSRoomHexMap.DIRECTION6) do
        local nq = q + dir.q
        local nr = r + dir.r
        if self:IsInBounds(nq, nr) and self:IsWalkable(nq, nr) then
            table.insert(neighbors, { q = nq, r = nr, s = -nq - nr })
        end
    end

    return neighbors
end

--- 打印地图
function FSRoomHexMap:Print()
    print("HexMap (" .. self.width .. "x" .. self.height .. "):")
    for r = 1, self.height do
        local line = ""
        -- 偶数行缩进
        if r % 2 == 0 then
            line = " "
        end

        for q = 1, self.width do
            local tile = self:GetTile(q, r)
            if tile == FSRoomHexMap.TILETYPES.WALL or tile == FSRoomHexMap.TILETYPES.BORDER then
                line = line .. "⌬ "
            else
                line = line .. "⬡ "
            end
        end
        print(line)
    end
end

if not ... then
    local newHexMap = FSRoomHexMap.new(20, 20)
    newHexMap:Print()
end

return FSRoomHexMap
