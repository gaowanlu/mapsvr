---@class MapQuadTreeType
---@field x        number                          节点左上角坐标x
---@field y        number                          节点左上角坐标y
---@field w        number                          节点宽度
---@field h        number                          阶段高度
---@field depth    number                          节点深度，根节点depth=0
---@field children table<integer, MapQuadTreeType> 子节点数组，初始为空 未分裂
---@field list     table<integer, table>           存放直接属于此节点的对象 存放的对象必须有 x y userId mapQuadTree 字段

---@class MapQuadTree: MapQuadTreeType
MapQuadTree = {
    MAX_DEPTH = 6,  -- 最大分裂深度，超过该深度不再继续分裂，防止无限分类
    MAX_OBJECTS = 0 -- 当节点对象数量超过该阈值时尝试分裂
}

---@param x     number 节点左上角坐标x
---@param y     number 节点左上角坐标y
---@param w     number 节点宽度
---@param h     number 节点高度
---@param depth number 节点深度
---@return MapQuadTree
function MapQuadTree.new(x, y, w, h, depth)
    ---@type MapQuadTree
    local newQuadTree = setmetatable({}, { __index = MapQuadTree })
    newQuadTree.x = x
    newQuadTree.y = y
    newQuadTree.w = w
    newQuadTree.h = h
    newQuadTree.depth = depth
    newQuadTree.children = nil
    newQuadTree.list = {}
    return newQuadTree
end

--- 判断对象obj是否完全包含在候选节点qtNode的矩形范围内
---@param qtNode MapQuadTree
---@param obj    table       -- {x, y}
---@return boolean
function MapQuadTree.ContainsNode(qtNode, obj)
    return (
        obj.x >= qtNode.x and           -- 对象左边界在子节点左边界右侧或相等
        obj.y >= qtNode.y and           -- 对象上边界在子节点上边界下方或相等
        obj.x < qtNode.x + qtNode.w and -- 对象左边界小于子节点右边界（严格小于以避免边界冲突）
        obj.y < qtNode.y + qtNode.h     -- 对象上边界小于子节点底边界
    )
end

--- 判断两个矩形A与B是否相交
---@param rectA table 矩形A
---@param rectB table 矩形B
---@return boolean 返回true表示相交或相融false表示完全分离
function MapQuadTree.Intersect(rectA, rectB)
    return not (
        rectB.x > rectA.x + rectA.w or -- b 的左边在 a 的右边之外（不相交）
        rectB.x + rectB.w < rectA.x or -- b 的右边在 a 的左边之外（不相交）
        rectB.y > rectA.y + rectA.h or -- b 的上边在 a 的下边之外（不相交）
        rectB.y + rectB.h < rectA.y    -- b 的下边在 a 的上边之外（不相交）
    )
end

--- 将对象obj插入到四叉树qtNode中
---@param qtNode MapQuadTree
---@param obj    table
function MapQuadTree.QtInert(qtNode, obj)
    if qtNode.children ~= nil then -- 如果已经有子节点（已分裂）
        -- 遍历四个子节点
        for i, v in ipairs(qtNode.children) do
            -- 如果某个子节点完全包含该对象
            if true == MapQuadTree.ContainsNode(v, obj) then
                MapQuadTree.QtInert(v, obj) -- 递归插入到该子节点（继续下沉）
                return -- 插入后结束（对象只放入完全包含它的子节点）
            end
        end

        -- 如果没有任何子节点能包含该对象，就把对象放在当前节点的list中
        table.insert(qtNode.list, obj)
        obj.mapQuadTree = qtNode
        return
    end

    -- 如果没有子节点（未分裂），把对象加入当前节点的list
    table.insert(qtNode.list, obj)
    obj.mapQuadTree = qtNode

    -- 如果当前节点的对象数量超过阈值并且深度未达到限制，则分裂节点
    if #qtNode.list > MapQuadTree.MAX_OBJECTS and qtNode.depth < MapQuadTree.MAX_DEPTH then
        MapQuadTree.Subdivide(qtNode)
    end
end

--- 将节点qtNode分裂为四个子节点 象限划分
---@param qtNode MapQuadTree
function MapQuadTree.Subdivide(qtNode)
    if qtNode.w <= 4 or qtNode.h <= 4 then
        return
    end
    if qtNode.children ~= nil then
        return
    end
    -- 子节点宽=当前宽的一半
    local hw = math.modf(qtNode.w / 2)
    -- 子节点高=当前高的一半
    local hh = math.modf(qtNode.h / 2)

    -- 创建四个子节点（左上，右上，左下，右下）
    qtNode.children = {
        MapQuadTree.new(qtNode.x, qtNode.y, hw, hh, qtNode.depth + 1),          -- 左上象限
        MapQuadTree.new(qtNode.x + hw, qtNode.y, hw, hh, qtNode.depth + 1),     -- 右上象限
        MapQuadTree.new(qtNode.x, qtNode.y + hh, hw, hh, qtNode.depth + 1),     -- 左下象限
        MapQuadTree.new(qtNode.x + hw, qtNode.y + hh, hw, hh, qtNode.depth + 1) -- 右下象限
    }

    -- old=当前节点已有对象的副本
    local old = {}
    for i = 1, #qtNode.list do
        old[i] = qtNode.list[i]
        qtNode.list[i].mapQuadTree = nil -- 将对象上的绑定的所在节点移除
    end
    -- 清空当前节点对象列表
    qtNode.list = {}

    -- 遍历旧对象并重新分配
    for _, obj in ipairs(old) do
        local inserted = false -- 是否被插入到了子节点中

        -- 尝试插入到四个子节点
        for _, child in ipairs(qtNode.children) do
            if MapQuadTree.ContainsNode(child, obj) then
                -- 递归插入
                MapQuadTree.QtInert(child, obj)
                inserted = true
                break
            end
        end

        -- 如果没有子节点完全包住，则放回当前节点
        if not inserted then
            qtNode.list[#qtNode.list + 1] = obj
            obj.mapQuadTree = qtNode
        end
    end
end

--- 在四叉树qtNode中查询与范围range相交的对象，结果加入out数组，seen是一个set（用table实现）
---@param qtNode MapQuadTree
---@param range  table
---@param out    table
---@param seen   table
function MapQuadTree.QtQuery(qtNode, range, out, seen)
    -- 如果当前节点不与查询范围相交，直接返回
    if not MapQuadTree.Intersect(qtNode, range) then
        return
    end

    -- 遍历当前节点直接存储的对象
    for _, obj in ipairs(qtNode.list) do
        repeat
            if not (obj.x >= range.x and obj.x < range.x + range.w and obj.y >= range.y and obj.y < range.y + range.h) then
                break
            end

            -- 去重
            if not seen[obj.userId] then
                seen[obj.userId] = true
                table.insert(out, obj)
            end
        until true
    end

    -- 递归查询子节点
    if qtNode.children ~= nil then
        for _, child in ipairs(qtNode.children) do
            MapQuadTree.QtQuery(child, range, out, seen)
        end
    end
end

--- 从qtNode的list中移除userId
---@param qtNode MapQuadTree
---@param userId any
---@return nil
function MapQuadTree.RemoveItemFromList(qtNode, userId)
    -- 从list移除userId为自己的obj 倒序遍历
    for i = #qtNode.list, 1, -1 do
        if qtNode.list[i].userId == userId then
            table.remove(qtNode.list, i)
            return
        end
    end
end

return MapQuadTree
