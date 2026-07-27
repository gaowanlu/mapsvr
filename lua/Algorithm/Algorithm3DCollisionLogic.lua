Algorithm3DCollisionLogic = Algorithm3DCollisionLogic or {}

---@class Algorithm3DCollisionBox
---@field x      number 最小点x
---@field y      number 最小点y
---@field z      number 最小点z
---@field width  number x方向
---@field height number y方向
---@field depth  number z方向

--- 3D AABB盒子碰撞检测
---@param box1 Algorithm3DCollisionBox
---@param box2 Algorithm3DCollisionBox
---@return boolean
function Algorithm3DCollisionLogic.AABBColision3D(box1, box2)
    return not (box1.x + box1.width < box2.x or box1.x > box2.x + box2.width or box1.y + box1.height < box2.y
        or box1.y > box2.y + box2.height or box1.z + box1.depth < box2.z or box1.z > box2.z + box2.depth)
end

-- local box1 = { x = 0, y = 0, z = 0, width = 100, height = 100, depth = 100 }
-- local box2 = { x = 50, y = 50, z = 50, width = 100, height = 100, depth = 100 }
-- print(Algorithm3DCollisionLogic.AABBColision3D(box1, box2)) -- 输出 true

---@class Algorithm3DCollisionSphere
---@field x      number
---@field y      number
---@field z      number
---@field radius number

--- 3D球形与球形碰撞检测
---@param sphere1 Algorithm3DCollisionSphere
---@param sphere2 Algorithm3DCollisionSphere
---@return boolean
function Algorithm3DCollisionLogic.SphereCollision3D(sphere1, sphere2)
    local dx = sphere1.x - sphere2.x
    local dy = sphere1.y - sphere2.y
    local dz = sphere1.z - sphere2.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    return distance < (sphere1.radius + sphere2.radius)
end

-- local sphere1 = { x = 0, y = 0, z = 0, radius = 50 }
-- local sphere2 = { x = 30, y = 30, z = 30, radius = 50 }
-- print(Algorithm3DCollisionLogic.SphereCollision3D(sphere1, sphere2))

--- 3D点是否在AABB矩形内
---@param x   number
---@param y   number
---@param z   number
---@param box Algorithm3DCollisionBox
---@return boolean
function Algorithm3DCollisionLogic.PointInAABB3D(x, y, z, box)
    return x >= box.x and x <= box.x + box.width and y >= box.y and y <= box.y + box.height and z >= box.z
        and z <= box.z + box.depth
end

-- local point = { x = 50, y = 50, z = 50 }
-- local box = { x = 0, y = 0, z = 0, width = 100, height = 100, depth = 100 }
-- print(Algorithm3DCollisionLogic.PointInAABB3D(point.x, point.y, point.z, box)) -- 输出 true

--- 3D 球与 盒子 碰撞检测
---@param sphere Algorithm3DCollisionSphere
---@param box    Algorithm3DCollisionBox
---@return boolean
function Algorithm3DCollisionLogic.SphereRectangleCollision3D(sphere, box)
    local nearestX = math.max(box.x, math.min(sphere.x, box.x + box.width))
    local nearestY = math.max(box.y, math.min(sphere.y, box.y + box.height))
    local nearestZ = math.max(box.z, math.min(sphere.z, box.z + box.depth))

    local dx = sphere.x - nearestX
    local dy = sphere.y - nearestY
    local dz = sphere.z - nearestZ
    return (dx * dx + dy * dy + dz * dz) < (sphere.radius * sphere.radius)
end

-- local sphere = { x = 150, y = 150, z = 150, radius = 50 }
-- local box = { x = 100, y = 100, z = 100, width = 100, height = 100, depth = 100 }
-- print(Algorithm3DCollisionLogic.SphereRectangleCollision3D(sphere, box)) -- 输出 true

--- 判断点是否在球内
---@param px     number
---@param py     number
---@param pz     number
---@param sphere Algorithm3DCollisionSphere
---@return boolean
function Algorithm3DCollisionLogic.PointInSphere3D(px, py, pz, sphere)
    local dx = px - sphere.x
    local dy = py - sphere.y
    local dz = pz - sphere.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    return distance <= sphere.radius
end

-- local point = { x = 3, y = 4, z = 5 }                                         -- 点的坐标
-- local sphere = { x = 0, y = 0, z = 0, radius = 5 }                            -- 球心坐标和半径
-- print(Algorithm3DCollisionLogic.PointInSphere3D(point.x, point.y, point.z, sphere)) -- 输出 true

return Algorithm3DCollisionLogic
