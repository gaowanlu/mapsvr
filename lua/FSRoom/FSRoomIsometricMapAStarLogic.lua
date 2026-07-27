---@class FSRoomIsometricMapAStar
local FSRoomIsometricMapAStar = require("FSRoomIsometricMapAStarData")

---@class FSRoomIsometricMapAStarPriorityQueueNode
---@field pos      FSRoomIsometricMapTilePos
---@field priority number

---@class FSRoomIsometricMapAStarPriorityQueue
---@field heap        table<integer, FSRoomIsometricMapAStarPriorityQueueNode>
---@field positionMap table<string, integer>
local FSRoomIsometricMapAStarPriorityQueue = {}
FSRoomIsometricMapAStarPriorityQueue.__index = FSRoomIsometricMapAStarPriorityQueue

--- 为pos生成唯一键
---@param pos FSRoomIsometricMapTilePos
---@return string
local function FSRoomIsometricMapAStar_MakeNodeKey(pos)
    return pos.x .. "," .. pos.y
end

---@return FSRoomIsometricMapAStarPriorityQueue
function FSRoomIsometricMapAStarPriorityQueue.new()
    ---@type FSRoomIsometricMapAStarPriorityQueue
    local self = setmetatable({}, FSRoomIsometricMapAStarPriorityQueue)

    self.heap = {}
    self.positionMap = {}

    return self
end

--- 向队列中添加元素
---@param pos      FSRoomIsometricMapTilePos 要存储的数据项
---@param priority number                    优先级值 越小优先级越高
function FSRoomIsometricMapAStarPriorityQueue:Push(pos, priority)
    local key = FSRoomIsometricMapAStar_MakeNodeKey(pos)

    -- 如果已经存在于堆中，则更新新优先级
    if self.positionMap[key] ~= nil then
        self:UpdatePriority(pos, priority)
        return
    end

    ---@type FSRoomIsometricMapAStarPriorityQueueNode
    local node = { pos = pos, priority = priority }
    table.insert(self.heap, node) -- 添加到堆尾
    local index = #self.heap
    self.positionMap[key] = index -- 记录位置
    self:BubbleUp(#self.heap) -- 向上调整堆结构
end

--- 更新已存在节点的优先级
---@param pos      FSRoomIsometricMapTilePos
---@param priority number
function FSRoomIsometricMapAStarPriorityQueue:UpdatePriority(pos, priority)
    local key = FSRoomIsometricMapAStar_MakeNodeKey(pos)
    local index = self.positionMap[key]

    if not index then
        return -- 节点不在堆中
    end

    local oldPriority = self.heap[index].priority
    -- 设置新的优先级
    self.heap[index].priority = priority

    -- 根据优先级变化决定向上还是向下调整
    if priority < oldPriority then
        self:BubbleUp(index) -- 优先级提高，向上调整
    else
        self:BubbleDown(index) -- 优先级降低，向下调整
    end
end

--- 检查某个位置是否在队列中
---@param pos FSRoomIsometricMapTilePos
---@return boolean
function FSRoomIsometricMapAStarPriorityQueue:Contains(pos)
    local key = FSRoomIsometricMapAStar_MakeNodeKey(pos)
    return self.positionMap[key] ~= nil
end

--- 弹出优先级最高（值最小）的元素
---@return FSRoomIsometricMapTilePos | nil
function FSRoomIsometricMapAStarPriorityQueue:Pop()
    -- 堆空
    if #self.heap == 0 then
        return nil
    end

    local root = self.heap[1]
    local rootKey = FSRoomIsometricMapAStar_MakeNodeKey(root.pos)
    self.positionMap[rootKey] = nil -- 从位置映射中移除

    -- 移除并返回最后一个
    local last = table.remove(self.heap)

    if #self.heap > 0 then
        self.heap[1] = last -- 将最后节点移到根部
        local lastKey = FSRoomIsometricMapAStar_MakeNodeKey(last.pos)
        self.positionMap[lastKey] = 1 -- 更新位置映射
        self:BubbleDown(1) -- 向下调整堆结构
    end

    return root.pos
end

--- 检查队列是否为空
---@return boolean
function FSRoomIsometricMapAStarPriorityQueue:IsEmpty()
    return #self.heap == 0
end

--- 向上调整堆
---@param index integer 需要调整的节点索引
function FSRoomIsometricMapAStarPriorityQueue:BubbleUp(index)
    if index <= 1 then
        return -- 已到达根节点
    end

    local parentIndex = math.floor(index / 2) -- 计算父节点索引

    -- 如果当前节点比父节点优先级高则交换
    if self.heap[index].priority < self.heap[parentIndex].priority then
        -- 交换节点
        self:SwapNode(index, parentIndex)
        self:BubbleUp(parentIndex)
    end
end

--- 向下调整堆
---@param index integer
function FSRoomIsometricMapAStarPriorityQueue:BubbleDown(index)
    local leftIndex = index * 2      -- 左孩子节点索引
    local rightIndex = leftIndex + 1 -- 右孩子节点索引
    local smallest = index           -- 记录最小值的索引

    -- 比较左子节点
    if leftIndex <= #self.heap and self.heap[leftIndex].priority < self.heap[smallest].priority then
        smallest = leftIndex
    end

    -- 比较右子节点
    if rightIndex <= #self.heap and self.heap[rightIndex].priority < self.heap[smallest].priority then
        smallest = rightIndex
    end

    -- 如果最小值不是当前节点，则交换并继续向下调整
    if smallest ~= index then
        self:SwapNode(index, smallest)
        -- 递归向下调整
        self:BubbleDown(smallest)
    end
end

--- 交换两个节点并更新位置映射
---@param i integer
---@param j integer
function FSRoomIsometricMapAStarPriorityQueue:SwapNode(i, j)
    local iNode = self.heap[i]
    local jNode = self.heap[j]

    -- 交换堆中的节点
    self.heap[i], self.heap[j] = jNode, iNode

    -- 更新位置映射
    local iKey = FSRoomIsometricMapAStar_MakeNodeKey(iNode.pos)
    local jKey = FSRoomIsometricMapAStar_MakeNodeKey(jNode.pos)
    self.positionMap[iKey] = j
    self.positionMap[jKey] = i
end

---@return FSRoomIsometricMapAStar
function FSRoomIsometricMapAStar.new()
    ---@type FSRoomIsometricMapAStar
    local self = setmetatable({}, FSRoomIsometricMapAStar)

    return self
end

--- 执行A*路径查找
---@param isometricMap FSRoomIsometricMap
---@param startX       integer
---@param startY       integer
---@param goalX        integer
---@param goalY        integer
---@return table<integer, FSRoomIsometricMapTilePos> | nil
function FSRoomIsometricMapAStar:FindPath(isometricMap, startX, startY, goalX, goalY)
    -- 检查起点和终点是否可行走
    if not isometricMap:IsWalkable(startX, startY) or not isometricMap:IsWalkable(goalX, goalY) then
        return nil -- 无路可走
    end

    -- 待评估节点的优先队列
    local openSet = FSRoomIsometricMapAStarPriorityQueue.new()
    -- 已经评估的节点标记
    ---@type table<string, boolean>
    local closedSet = {}

    -- 记录每个节点的前驱节点用于重建路径
    ---@type table<string, FSRoomIsometricMapTilePos>
    local cameFrom = {}

    -- 记录从起点到各节点的实际代价
    ---@type table<string, number>
    local gScore = {}

    -- 记录各节点的总估计 f = g + h
    ---@type table<string, number>
    local fScore = {}

    local startKey = FSRoomIsometricMapAStar_MakeNodeKey({ x = startX, y = startY })
    local goalKey = FSRoomIsometricMapAStar_MakeNodeKey({ x = goalX, y = goalY })

    -- 初始化起点
    gScore[startKey] = 0
    fScore[startKey] = isometricMap:Distance(startX, startY, goalX, goalY)
    openSet:Push({ x = startX, y = startY }, fScore[startKey])

    -- 不断处理 openSet 中 f 值最小的节点
    while not openSet:IsEmpty() do
        -- 从堆中弹出一个未处理过f最小的
        local current = openSet:Pop()

        if current == nil then
            return nil
        end

        local currentKey = FSRoomIsometricMapAStar_MakeNodeKey(current)
        closedSet[currentKey] = true -- 标记已评估

        -- 检查是否到达目标
        if currentKey == goalKey then
            return self:ReconstructPath(cameFrom, current)
        end

        -- 检查当前节点的所有邻居
        local neighbors = isometricMap:GetNeighbors(current.x, current.y)
        for _, neighbor in ipairs(neighbors) do
            repeat
                local neighborKey = FSRoomIsometricMapAStar_MakeNodeKey(neighbor)

                -- 已经评估过的节点直接跳过
                if closedSet[neighborKey] then
                    break
                end

                -- 计算从当前节点移动到邻居节点的代价
                local moveToNeighborCost = isometricMap:MoveCost(current.x, current.y, neighbor.x, neighbor.y)
                -- 如果走current节点到邻居 起点到邻居将会多远
                local tentativeGScore = gScore[currentKey] + moveToNeighborCost

                -- 如果找到更优路径，或该邻居尚未被访问过
                if not gScore[neighborKey] or tentativeGScore < gScore[neighborKey] then
                    -- 更新邻居节点信息
                    cameFrom[neighborKey] = current       -- 记录前驱节点
                    gScore[neighborKey] = tentativeGScore -- 更新g值
                    -- 计算f值 = g值 + h值（启发式估价）
                    fScore[neighborKey] = tentativeGScore + isometricMap:Distance(neighbor.x, neighbor.y, goalX, goalY)

                    -- Push会自动处理 不在堆中就添加 已在堆中就更新优先级
                    openSet:Push(neighbor, fScore[neighborKey])
                end
            until true -- 循环只跑一次当 continue 用
        end
    end

    -- openSet为空但未找到目标，说明无路径可达
    return nil
end

---@param cameFrom table<string, FSRoomIsometricMapTilePos>
---@param current  FSRoomIsometricMapTilePos
---@return table<integer, FSRoomIsometricMapTilePos>
function FSRoomIsometricMapAStar:ReconstructPath(cameFrom, current)
    ---@type table<integer, FSRoomIsometricMapTilePos>
    local resultPath = { { x = current.x, y = current.y } }
    local currentKey = FSRoomIsometricMapAStar_MakeNodeKey(current)

    -- 从终点回溯到起点
    while cameFrom[currentKey] ~= nil do
        current = cameFrom[currentKey]
        currentKey = FSRoomIsometricMapAStar_MakeNodeKey(current)
        table.insert(resultPath, { x = current.x, y = current.y })
    end

    -- 返回反转的resultPath
    for i = 1, math.floor(#resultPath / 2) do
        resultPath[i], resultPath[#resultPath - i + 1] = resultPath[#resultPath - i + 1], resultPath[i]
    end

    return resultPath
end

return FSRoomIsometricMapAStar
