---@class Map3DOctreeType
---@field x number 左上前角x
---@field y number 左上前角y
---@field z number 左上前角z
---@field w number 宽度
---@field h number 高度
---@field d number 深度
---@field depth number 当前深度
---@field children table<integer,Map3DOctreeType> 子节点数组，初始为空 未分裂
---@field list table<integer,table> 存放直接属于此节点的对象 对象要有 pos:{x, y, z} map3DOctree userId 字段

---@class Map3DOctree:Map3DOctreeType
Map3DOctree = {
    MAX_DEPTH = 6,   -- 最大分裂深度
    MAX_OBJECTS = 0, -- 节点最多对象数
};

--- 创建一个新的八叉树节点
---@param x number 左上前角x
---@param y number 左上前角y
---@param z number 左上前角z
---@param w number 宽度x方向
---@param h number 高度y方向
---@param d number 深度z方向
---@param depth number 当前深度
---@return Map3DOctree
function Map3DOctree.new(x, y, z, w, h, d, depth)
    ---@type Map3DOctree
    local newOctree = setmetatable({}, { __index = Map3DOctree });
    newOctree.x = x;
    newOctree.y = y;
    newOctree.z = z;
    newOctree.w = w;
    newOctree.h = h;
    newOctree.d = d;
    newOctree.depth = depth or 0;
    newOctree.children = nil;
    newOctree.list = {};
    return newOctree;
end

--- 判断obj是否完全被node包含（点对象）
---@param node Map3DOctree
---@param obj table -- {pos.x,pos.y,pos.z,map3DOctree}
---@return boolean
function Map3DOctree.ContainsNode(node, obj)
    return (
        obj.pos.x >= node.x and obj.pos.x < node.x + node.w and
        obj.pos.y >= node.y and obj.pos.y < node.y + node.h and
        obj.pos.z >= node.z and obj.pos.z < node.z + node.d
    );
end

--- 判断两个AABB盒是否相交
---@param a table -- {x, y, z, w, h, d}
---@param b table -- {x, y, z, w, h, d}
---@return boolean
function Map3DOctree.Intersect(a, b)
    return not (
        b.x > a.x + a.w or a.x > b.x + b.w or
        b.y > a.y + a.h or a.y > b.y + b.h or
        b.z > a.z + a.d or a.z > b.z + b.d
    );
end

--- 向八叉树节点中插入对象
---@param node Map3DOctree
---@param obj table -- {pos.x,pos.y,pos.z,map3DOctree}
function Map3DOctree.OcInsert(node, obj)
    -- 如果已经有子节点（已分裂）
    if node.children ~= nil then
        -- 遍历8个子节点
        for _, child in ipairs(node.children) do
            -- 如果某个子节点完全包含该对象
            if true == Map3DOctree.ContainsNode(child, obj) then
                Map3DOctree.OcInsert(child, obj); -- 递归插入到该子节点（继续下沉）
                return;                           -- 插入后结束（对象只放入完全包含它的子节点）
            end
        end

        -- 如果没有任何子节点能包含该对象，就把对象放在当前节点的list中
        table.insert(node.list, obj);
        obj.map3DOctree = node;
        return;
    end

    -- 如果没有子节点（未分裂），把对象加入当前节点的list
    table.insert(node.list, obj);
    obj.map3DOctree = node;

    -- 如果当前节点的对象数量超过阈值并且深度未达到限制，则分裂节点
    if #node.list > Map3DOctree.MAX_OBJECTS and node.depth < Map3DOctree.MAX_DEPTH then
        Map3DOctree.Subdivide(node);
    end
end

--- 分裂成8个子节点
---@param node Map3DOctree
function Map3DOctree.Subdivide(node)
    -- 分裂过了
    if node.children ~= nil then
        return;
    end
    -- 每个节点大小不能小于2
    if node.w <= 2 or node.h <= 2 or node.d <= 2 then
        return;
    end

    local hw = math.modf(node.w / 2);
    local hh = math.modf(node.h / 2);
    local hd = math.modf(node.d / 2);

    local x, y, z = node.x, node.y, node.z;
    local nd = node.depth + 1;

    -- 分裂成8个孩子
    node.children = {
        Map3DOctree.new(x, y, z, hw, hh, hd, nd),                -- 左上前
        Map3DOctree.new(x + hw, y, z, hw, hh, hd, nd),           -- 右上前
        Map3DOctree.new(x, y + hh, z, hw, hh, hd, nd),           -- 左下前
        Map3DOctree.new(x + hw, y + hh, z, hw, hh, hd, nd),      -- 右下前

        Map3DOctree.new(x, y, z + hd, hw, hh, hd, nd),           -- 左上后
        Map3DOctree.new(x + hw, y, z + hd, hw, hh, hd, nd),      -- 右上后
        Map3DOctree.new(x, y + hh, z + hd, hw, hh, hd, nd),      -- 左下后
        Map3DOctree.new(x + hw, y + hh, z + hd, hw, hh, hd, nd), -- 右下后
    };

    -- old=当前节点已有对象的副本
    local old = {};
    for i = 1, #node.list do
        old[i] = node.list[i];
        node.list[i].map3DOctree = nil; -- 将对象上的绑定的所在节点移除
    end
    -- 清空当前节点对象列表
    node.list = {};

    -- 遍历旧对象并重新分配到8个子节点中
    for _, obj in ipairs(old) do
        local inserted = false; -- 是否被插入到了子节点中

        -- 尝试插入到8个子节点
        for _, child in ipairs(node.children) do
            if Map3DOctree.ContainsNode(child, obj) then
                -- 递归插入
                Map3DOctree.OcInsert(child, obj);
                inserted = true;
                break;
            end
        end

        -- 如果没有子节点完全包住，则放回当前节点
        if not inserted then
            node.list[#node.list + 1] = obj;
            obj.map3DOctree = node;
        end
    end
end

--- 查询与范围相交的对象
---@param node Map3DOctree
---@param range table -- {x, y, z, w, h, d}
---@param out table
---@param seen table
function Map3DOctree.OcQuery(node, range, out, seen)
    -- 如果当前节点不与查询范围相交，直接返回
    if not Map3DOctree.Intersect(node, range) then
        return;
    end

    -- 遍历当前节点直接存储的对象
    for _, obj in ipairs(node.list) do
        repeat
            if not (obj.pos.x >= range.x and obj.pos.x < range.x + range.w and
                    obj.pos.y >= range.y and obj.pos.y < range.y + range.h and
                    obj.pos.z >= range.z and obj.pos.z < range.z + range.d) then
                break;
            end

            -- 去重
            if seen[obj.userId] then
                break;
            end

            seen[obj.userId] = true;
            table.insert(out, obj);
        until true;
    end

    -- 递归查询子节点
    if node.children ~= nil then
        for _, child in ipairs(node.children) do
            Map3DOctree.OcQuery(child, range, out, seen);
        end
    end
end

--- 从octreeNode的list中移除userId
---@param octreeNode Map3DOctree
---@param userId any
---@return nil
function Map3DOctree.RemoveItemFromList(octreeNode, userId)
    -- 从list移除userId为自己的obj 倒序遍历
    for i = #octreeNode.list, 1, -1 do
        if octreeNode.list[i].userId == userId then
            table.remove(octreeNode.list, i);
            return;
        end
    end
end

return Map3DOctree;
