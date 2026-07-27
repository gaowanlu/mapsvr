AlgorithmCollisionLogic = AlgorithmCollisionLogic or {}

---@class AlgorithmCollisionBox
---@field x      number 左上角x坐标
---@field y      number 左上角y坐标
---@field width  number 矩形宽度 x方向
---@field height number 矩形高度 y方向

--- 2D AABB 碰撞检测
---@param box1 AlgorithmCollisionBox
---@param box2 AlgorithmCollisionBox
---@return boolean
function AlgorithmCollisionLogic.AABBCollision2D(box1, box2)
    return not (box1.x + box1.width < box2.x or box1.x > box2.x + box2.width
        or box1.y + box1.height < box2.y or box1.y > box2.y + box2.height)
end

---@class AlgorithmCollisionCircle
---@field x      number
---@field y      number
---@field radius number

--- 2D圆形碰撞检测
---@param circle1 AlgorithmCollisionCircle
---@param circle2 AlgorithmCollisionCircle
---@return boolean
function AlgorithmCollisionLogic.CircleCollision2D(circle1, circle2)
    local dx = circle1.x - circle2.x
    local dy = circle1.y - circle2.y
    local distance = math.sqrt(dx * dx + dy * dy)
    return distance < (circle1.radius + circle2.radius)
end

--- 2D点在矩形内检测点是否在矩形内部
---@param x   number
---@param y   number
---@param box AlgorithmCollisionBox
---@return boolean
function AlgorithmCollisionLogic.PointInAABB2D(x, y, box)
    return x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height
end

--- 2D原与矩形的碰撞检测
---@param circle AlgorithmCollisionCircle
---@param box    AlgorithmCollisionBox
---@return boolean
function AlgorithmCollisionLogic.CircleRectangleCollision2D(circle, box)
    -- 计算矩形边界范围内，距离圆心最近的点
    -- nearestX: 取圆心x坐标与矩形左边界(box.x)和右边界(box.x+box.width)之间的最小值，表示圆心x坐标所在的水平范围
    -- 如果圆心在矩形的左侧，nearestX 就是矩形的左边界
    -- 如果圆心在矩形的右侧，nearestX 就是矩形的右边界
    -- 如果圆心在矩形的宽度范围内，nearestX 就是圆心的 x 坐标
    local nearestX = math.max(box.x, math.min(circle.x, box.x + box.width))

    -- nearestY：类似地，取圆心y坐标与矩形上边界(box.y)和下边界(box.y + box.height)之间的最小值，表示圆心 y 坐标所在的垂直范围。
    local nearestY = math.max(box.y, math.min(circle.y, box.y + box.height))

    -- 计算圆心与最近点的距离
    local dx = circle.x - nearestX -- 水平距离
    local dy = circle.y - nearestY -- 垂直距离

    -- 判断距离的平方是否小于圆的半径的平方
    -- 如果小于，说明圆与矩形发生了碰撞；否则，未发生碰撞。
    return (dx * dx + dy * dy) < (circle.radius * circle.radius)
end

--- 判断点是否在圆形内
---@param px     number
---@param py     number
---@param circle AlgorithmCollisionCircle
function AlgorithmCollisionLogic.PointInCircle2D(px, py, circle)
    local dx = px - circle.x
    local dy = py - circle.y
    local distance = math.sqrt(dx * dx + dy * dy)
    return distance <= circle.radius
end

if not ... then -- 如果是直接运行而非被 require
    ---@diagnostic disable-next-line: unnecessary-if
    if true then
        -- AABB 碰撞测试
        local box1 = { x = 0, y = 0, width = 100, height = 100 }
        local box2 = { x = 50, y = 50, width = 100, height = 100 }
        print("expect true->", AlgorithmCollisionLogic.AABBCollision2D(box1, box2)) -- 输出 true

        -- 测试不重叠的 AABB
        local box3 = { x = 200, y = 200, width = 100, height = 100 }
        print("expect false->", AlgorithmCollisionLogic.AABBCollision2D(box1, box3)) -- 输出 false
    end

    ---@diagnostic disable-next-line: unnecessary-if
    if true then
        -- 圆形碰撞测试
        local circle1 = { x = 0, y = 0, radius = 50 }
        local circle2 = { x = 30, y = 30, radius = 50 }
        print("expect true->", AlgorithmCollisionLogic.CircleCollision2D(circle1, circle2)) -- 输出 true

        -- 测试不重叠的圆形
        local circle3 = { x = 200, y = 200, radius = 50 }
        print("expect false->", AlgorithmCollisionLogic.CircleCollision2D(circle1, circle3)) -- 输出 false
    end

    ---@diagnostic disable-next-line: unnecessary-if
    if true then
        -- 测试点是否在矩形内部
        local point = { x = 50, y = 50 }
        local box = { x = 0, y = 0, width = 100, height = 100 }
        print("expect true->", AlgorithmCollisionLogic.PointInAABB2D(point.x, point.y, box)) -- 输出 true

        -- 测试点不在矩形内部
        local point2 = { x = 150, y = 150 }
        print("expect false->", AlgorithmCollisionLogic.PointInAABB2D(point2.x, point2.y, box)) -- 输出 false
    end

    ---@diagnostic disable-next-line: unnecessary-if
    if true then
        -- 圆形与矩形的碰撞检测
        local circle = { x = 150, y = 150, radius = 50 }
        local box = { x = 100, y = 100, width = 100, height = 100 }
        print("expect true->", AlgorithmCollisionLogic.CircleRectangleCollision2D(circle, box)) -- 输出 true

        -- 圆形与矩形不碰撞
        local circle2 = { x = 300, y = 300, radius = 50 }
        print("expect false->", AlgorithmCollisionLogic.CircleRectangleCollision2D(circle2, box)) -- 输出 false
    end

    ---@diagnostic disable-next-line: unnecessary-if
    if true then
        -- 测试点是否在圆形内部
        local point = { x = 3, y = 4 }              -- 点的坐标
        local circle = { x = 0, y = 0, radius = 5 } -- 圆心坐标和半径
        print("expect true->", AlgorithmCollisionLogic.PointInCircle2D(point.x, point.y, circle)) -- 输出 true

        -- 测试点不在圆形内部
        local point2 = { x = 6, y = 6 }
        print("expect false->", AlgorithmCollisionLogic.PointInCircle2D(point2.x, point2.y, circle)) -- 输出 false
    end

    ---@diagnostic disable-next-line: unnecessary-if
    if true then
        -- 测试更多的 AABB 碰撞
        local box1 = { x = 0, y = 0, width = 150, height = 150 }
        local box2 = { x = 100, y = 100, width = 200, height = 200 }
        print("expect true->", AlgorithmCollisionLogic.AABBCollision2D(box1, box2)) -- 输出 true

        -- 测试超大矩形碰撞
        local box3 = { x = 1000, y = 1000, width = 500, height = 500 }
        print("expect false->", AlgorithmCollisionLogic.AABBCollision2D(box1, box3)) -- 输出 false
    end

    ---@diagnostic disable-next-line: unnecessary-if
    if true then
        -- 圆形碰撞在不同位置的测试
        local circle1 = { x = 10, y = 10, radius = 5 }
        local circle2 = { x = 15, y = 10, radius = 5 }
        print("expect true->", AlgorithmCollisionLogic.CircleCollision2D(circle1, circle2)) -- 输出 true

        -- 完全不重叠的圆形
        local circle3 = { x = 100, y = 100, radius = 5 }
        print("expect false->", AlgorithmCollisionLogic.CircleCollision2D(circle1, circle3)) -- 输出 false
    end
end

return AlgorithmCollisionLogic
