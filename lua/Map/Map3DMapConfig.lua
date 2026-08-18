-- Map3D 地图墙体/建筑配置
--
-- 坐标系(地图本地坐标, 与客户端渲染基准一致):
--   x/z : 相对地图中心(即出生点)
--   y   : 相对地面(0 = 地面)
--
-- 修改地图: 直接编辑下方 buildXxx() 内的盒布局, 或新增 mapId 条目。
-- 此配置是服务器权威碰撞(玩家/子弹 vs 墙体)的唯一数据来源,
-- 玩家进入地图时会原样下发给客户端, 客户端用它渲染地图并做本地移动预测。

---@class Map3DBoxConfig
---@field x       number  中心X(相对地图中心)
---@field y       number  中心Y(相对地面)
---@field z       number  中心Z(相对地图中心)
---@field w       number  宽(X方向)
---@field h       number  高(Y方向)
---@field d       number  深(Z方向)
---@field color   integer 颜色(0xRRGGBB)
---@field collide boolean 是否参与碰撞(默认true; 屋顶等装饰盒为false)

---@class Map3DMapConfigType
---@field name  string
---@field boxes table<integer, Map3DBoxConfig>

local Map3DMapConfig = {}

-- 颜色定义
local M_WALL = 0x3b4f68    -- 主墙体 钢蓝
local M_WALL2 = 0x3c3550   -- 次墙体 紫灰
local M_COVER = 0x2e4257   -- 过道掩体 深蓝灰
local M_CRATE = 0x6b5538   -- 木箱 棕
local M_CRATE2 = 0x4f6473  -- 集装箱 灰蓝
local M_TOWER = 0x35455c   -- 哨塔
local M_ROOF = 0x232f41    -- 屋顶板

-- ============================================================
-- 地图4: 工业战区 ARENA-4（固定布局，出生点(0,0)保持开阔）
-- 构成: 边界围墙 + 四个象限建筑(带门洞) + 过道掩体墙
--       + 四角哨塔 + 中央广场掩体 + 散落集装箱
-- ============================================================
local function buildArena4()
    ---@type table<integer, Map3DBoxConfig>
    local boxes = {}

    ---@param x number 中心X
    ---@param yRel number 中心Y(相对地面)
    ---@param z number 中心Z
    ---@param w number 宽
    ---@param h number 高
    ---@param d number 深
    ---@param color integer 颜色
    ---@param collide boolean|nil 是否参与碰撞(默认true)
    local function addBox(x, yRel, z, w, h, d, color, collide)
        boxes[#boxes + 1] = {
            x = x, y = yRel, z = z, w = w, h = h, d = d,
            color = color,
            collide = collide ~= false
        }
    end

    -- 水平墙(沿X) / 垂直墙(沿Z)，t 为厚度
    local function wallH(x1, x2, z, h, t, color)
        addBox((x1 + x2) / 2, h / 2, z, math.abs(x2 - x1), h, t, color)
    end
    local function wallV(z1, z2, x, h, t, color)
        addBox(x, h / 2, (z1 + z2) / 2, t, h, math.abs(z2 - z1), color)
    end

    -- 带门洞的水平/垂直墙：以 (gx,gz) 为中心留 gap 宽的门洞
    local function wallHGap(x1, x2, z, gx, gap, h, t, color)
        local a, b = gx - gap / 2, gx + gap / 2
        if x1 < a then wallH(x1, a, z, h, t, color) end
        if b < x2 then wallH(b, x2, z, h, t, color) end
    end
    local function wallVGap(z1, z2, x, gz, gap, h, t, color)
        local a, b = gz - gap / 2, gz + gap / 2
        if z1 < a then wallV(z1, a, x, h, t, color) end
        if b < z2 then wallV(b, z2, x, h, t, color) end
    end

    -- 四墙建筑(带悬挑屋顶板)；doors: {n,s,e,w} 对应带门洞的墙
    local function building(x, z, w, d, h, color, roof, doors)
        local t, gap = 0.7, 3.0
        local L, R = x - w / 2, x + w / 2
        local T, B = z - d / 2, z + d / 2
        if doors.n then wallHGap(L, R, T, x, gap, h, t, color) else wallH(L, R, T, h, t, color) end
        if doors.s then wallHGap(L, R, B, x, gap, h, t, color) else wallH(L, R, B, h, t, color) end
        if doors.w then wallVGap(T, B, L, z, gap, h, t, color) else wallV(T, B, L, h, t, color) end
        if doors.e then wallVGap(T, B, R, z, gap, h, t, color) else wallV(T, B, R, h, t, color) end
        if roof then addBox(x, h + 0.15, z, w + 1.6, 0.3, d + 1.6, M_ROOF, false) end
    end

    -- ---- 1. 边界围墙(可打，不可翻越) ----
    local WALL_H = 4.5
    wallH(-58, 58, -58, WALL_H, 1.0, M_WALL)   -- 北
    wallH(-58, 58, 58, WALL_H, 1.0, M_WALL)    -- 南
    wallV(-58, 58, -58, WALL_H, 1.0, M_WALL)   -- 西
    wallV(-58, 58, 58, WALL_H, 1.0, M_WALL)    -- 东

    -- ---- 2. 四个象限建筑(朝向中心广场开门) ----
    building(-32, -30, 26, 24, 4.2, M_WALL, true, { e = true, s = true })   -- A 西北
    building(32, -30, 26, 24, 4.2, M_WALL2, true, { w = true, s = true })   -- B 东北
    building(-32, 30, 26, 24, 4.2, M_WALL2, true, { e = true, n = true })   -- C 西南
    building(32, 30, 26, 24, 4.2, M_WALL, true, { w = true, n = true })     -- D 东南

    -- ---- 3. 四角哨塔(地标+掩体) ----
    addBox(-51, 3.5, -51, 3.5, 7, 3.5, M_TOWER)
    addBox(51, 3.5, -51, 3.5, 7, 3.5, M_TOWER)
    addBox(-51, 3.5, 51, 3.5, 7, 3.5, M_TOWER)
    addBox(51, 3.5, 51, 3.5, 7, 3.5, M_TOWER)

    -- ---- 4. 中央广场掩体(出生点(0,0)保持开阔) ----
    for _, cz in ipairs({ 5, -5 }) do
        for _, cx in ipairs({ 5, -5 }) do
            addBox(cx, 1.2, cz, 2.4, 2.4, 2.4, M_CRATE)      -- 木箱四角
        end
    end
    for _, cz in ipairs({ 13, -13 }) do
        for _, cx in ipairs({ 13, -13 }) do
            addBox(cx, 1.75, cz, 1.8, 3.5, 1.8, M_CRATE2)    -- 立柱外围
        end
    end

    -- ---- 5. 建筑间过道掩体墙(中央留缺口通行) ----
    local ALLEY_H, ALLEY_T, ALLEY_GAP = 3.0, 0.7, 5.0
    wallHGap(-19, 19, -30, 0, ALLEY_GAP, ALLEY_H, ALLEY_T, M_COVER)   -- A-B 之间(东西向)
    wallHGap(-19, 19, 30, 0, ALLEY_GAP, ALLEY_H, ALLEY_T, M_COVER)    -- C-D 之间
    wallVGap(-19, 19, -30, 0, ALLEY_GAP, ALLEY_H, ALLEY_T, M_COVER)   -- A-C 之间(南北向)
    wallVGap(-19, 19, 30, 0, ALLEY_GAP, ALLEY_H, ALLEY_T, M_COVER)    -- B-D 之间

    -- ---- 6. 散落集装箱/木箱掩体 ----
    addBox(-24, 1.25, -12, 5, 2.5, 2.5, M_CRATE2)   -- A 东南侧
    addBox(24, 1.25, -12, 5, 2.5, 2.5, M_CRATE2)    -- B 西南侧
    addBox(-24, 1.25, 12, 5, 2.5, 2.5, M_CRATE2)    -- C 东北侧
    addBox(24, 1.25, 12, 5, 2.5, 2.5, M_CRATE2)     -- D 西北侧
    addBox(-40, 0.9, -8, 2.4, 1.8, 2.4, M_CRATE)    -- 西侧过道
    addBox(40, 0.9, -8, 2.4, 1.8, 2.4, M_CRATE)     -- 东侧过道
    addBox(-40, 0.9, 8, 2.4, 1.8, 2.4, M_CRATE)
    addBox(40, 0.9, 8, 2.4, 1.8, 2.4, M_CRATE)

    return { name = "ARENA-4", boxes = boxes }
end

Map3DMapConfig[4] = buildArena4()

--- 获取指定地图的墙体/建筑配置 (没有配置返回nil, 该地图无墙体碰撞)
---@param mapId integer
---@return Map3DMapConfigType | nil
function Map3DMapConfig.GetMapConfig(mapId)
    return Map3DMapConfig[mapId]
end

return Map3DMapConfig
