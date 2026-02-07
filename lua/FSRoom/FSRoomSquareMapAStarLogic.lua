---@class FSRoomSquareMapAStar
FSRoomSquareMapAStar = require("FSRoomSquareMapAStarData");

---@class FSRoomSquareMapAStarPriorityQueueNode
---@field pos FSRoomSquareMapTilePos
---@field priority number

---@class FSRoomSquareMapAStarPriorityQueue
---@field heap table<integer,FSRoomSquareMapAStarPriorityQueueNode>
---@field positionMap table<string, integer>
local FSRoomSquareMapAStarPriorityQueue = {};
FSRoomSquareMapAStarPriorityQueue.__index = FSRoomSquareMapAStarPriorityQueue;

--- 为Pos生成唯一键
---@param pos FSRoomSquareMapTilePos
---@return string
local function FSRoomSquareMapAStar_MakeNodeKey(pos)
    return pos.x .. "," .. pos.y;
end

---@return FSRoomSquareMapAStarPriorityQueue
function FSRoomSquareMapAStarPriorityQueue.new()
    ---@type FSRoomSquareMapAStarPriorityQueue
    local self = setmetatable({}, FSRoomSquareMapAStarPriorityQueue);
    self.heap = {};
    self.positionMap = {};

    return self;
end

--- 向队列中添加元素
---@param pos FSRoomSquareMapTilePos 要存储的数据项
---@param priority number 优先级值 越小优先级越高
function FSRoomSquareMapAStarPriorityQueue:Push(pos, priority)
    local key = FSRoomSquareMapAStar_MakeNodeKey(pos);

    -- 如果已存在与堆中，则更新优先级
    if self.positionMap[key] ~= nil then
        self:UpdatePriority(pos, priority);
        return;
    end

    ---@type FSRoomSquareMapAStarPriorityQueueNode
    local node = { pos = pos, priority = priority };
    table.insert(self.heap, node); -- 添加到堆尾
    local index = #self.heap;
    self.positionMap[key] = index; -- 记录位置
    self:BubbleUp(#self.heap);     -- 向上调整堆结构
end

--- 更新已存在节点的优先级
---@param pos FSRoomSquareMapTilePos
---@param priority number
function FSRoomSquareMapAStarPriorityQueue:UpdatePriority(pos, priority)
    local key = FSRoomSquareMapAStar_MakeNodeKey(pos);
    local index = self.positionMap[key];

    if not index then
        return; -- 节点不在堆中
    end

    local oldPriority = self.heap[index].priority;
    self.heap[index].priority = priority;

    -- 根据优先级变化决定向上还是向下调整
    if priority < oldPriority then
        self:BubbleUp(index);   -- 优先级提高，向上调整
    else
        self:BubbleDown(index); -- 优先级降低，向下调整
    end
end

--- 检查某个位置是否在队列中
---@param pos FSRoomSquareMapTilePos
---@return boolean
function FSRoomSquareMapAStarPriorityQueue:Contains(pos)
    local key = FSRoomSquareMapAStar_MakeNodeKey(pos);
    return self.positionMap[key] ~= nil;
end

--- 弹出优先级最高（值最小）的元素
---@return FSRoomSquareMapTilePos|nil
function FSRoomSquareMapAStarPriorityQueue:Pop()
    -- 堆空
    if #self.heap == 0 then
        return nil
    end

    local root = self.heap[1];
    local rootKey = FSRoomSquareMapAStar_MakeNodeKey(root.pos);
    self.positionMap[rootKey] = nil; -- 从位置映射中移除

    -- 移除并返回最后一个
    local last = table.remove(self.heap);

    if #self.heap > 0 then
        self.heap[1] = last;           -- 将最后节点移到根部
        local lastKey = FSRoomSquareMapAStar_MakeNodeKey(last.pos);
        self.positionMap[lastKey] = 1; -- 更新位置映射
        self:BubbleDown(1);            -- 向下调整堆结构
    end

    return root.pos;
end

--- 检查队列是否为空
---@return boolean
function FSRoomSquareMapAStarPriorityQueue:IsEmpty()
    return #self.heap == 0;
end

--- 向上调整堆
---@param index integer 需要调整的节点索引
function FSRoomSquareMapAStarPriorityQueue:BubbleUp(index)
    if index <= 1 then
        return -- 已到达根节点
    end

    local parentIndex = math.floor(index / 2); -- 计算父节点索引

    -- 如果当前节点比父节点优先级高则交换
    if self.heap[index].priority < self.heap[parentIndex].priority then
        -- 交换节点
        self:SwapNode(index, parentIndex);
        self:BubbleUp(parentIndex);
    end
end

--- 向下调整堆
---@param index integer
function FSRoomSquareMapAStarPriorityQueue:BubbleDown(index)
    local leftIndex = index * 2;      -- 左孩子节点索引
    local rightIndex = leftIndex + 1; -- 右孩子节点索引
    local smallest = index;           -- 记录最小值的索引

    -- 比较左子节点
    if leftIndex <= #self.heap and self.heap[leftIndex].priority < self.heap[smallest].priority then
        smallest = leftIndex;
    end

    -- 比较右子节点
    if rightIndex <= #self.heap and self.heap[rightIndex].priority < self.heap[smallest].priority then
        smallest = rightIndex;
    end


    -- 如果最小值不是当前节点，则交换并继续向下调整
    if smallest ~= index then
        self:SwapNode(index, smallest);
        -- 递归向下调整
        self:BubbleDown(smallest);
    end
end

--- 交换两个节点并更新位置映射
---@param i integer
---@param j integer
function FSRoomSquareMapAStarPriorityQueue:SwapNode(i, j)
    local iNode = self.heap[i];
    local jNode = self.heap[j];

    -- 交换堆中的节点
    self.heap[i], self.heap[j] = jNode, iNode;

    -- 更新位置映射
    local iKey = FSRoomSquareMapAStar_MakeNodeKey(iNode.pos);
    local jKey = FSRoomSquareMapAStar_MakeNodeKey(jNode.pos);
    self.positionMap[iKey] = j;
    self.positionMap[jKey] = i;
end

---@return FSRoomSquareMapAStar
function FSRoomSquareMapAStar.new()
    ---@type FSRoomSquareMapAStar
    local self = setmetatable({}, FSRoomSquareMapAStar);

    return self;
end

--- 执行A*路径查找
---@param squareMap FSRoomSquareMap
---@param startX integer
---@param startY integer
---@param goalX integer
---@param goalY integer
---@return table<integer,FSRoomSquareMapTilePos>|nil
function FSRoomSquareMapAStar:FindPath(squareMap, startX, startY, goalX, goalY)
    -- 检查起点和终点是否可行走
    if not squareMap:IsWalkable(startX, startY) or not squareMap:IsWalkable(goalX, goalY) then
        return nil; -- 无路可走
    end

    -- 待评估节点的优先队列
    local openSet = FSRoomSquareMapAStarPriorityQueue.new();
    -- 已经评估的节点标记
    ---@type table<string,boolean>
    local closedSet = {};

    -- 记录每个节点的前驱节点用于重建路径
    ---@type table<string, FSRoomSquareMapTilePos>
    local cameFrom = {};

    -- 记录从起点到各节点的实际代价
    ---@type table<string,number>
    local gScore = {};

    -- 记录各节点的总估计 f = g + h
    ---@type table<string,number>
    local fScore = {};

    local startKey = FSRoomSquareMapAStar_MakeNodeKey({ x = startX, y = startY });
    local goalKey = FSRoomSquareMapAStar_MakeNodeKey({ x = goalX, y = goalY });

    -- 初始化起点
    gScore[startKey] = 0;
    fScore[startKey] = squareMap:Distance(startX, startY, goalX, goalY);
    openSet:Push({ x = startX, y = startY }, fScore[startKey]);

    -- 不断处理 openSet 中 f 值最小的节点
    while not openSet:IsEmpty() do
        -- 从堆中弹出一个未处理过f最小的
        local current = openSet:Pop();

        if current == nil then
            return nil;
        end

        local currentKey = FSRoomSquareMapAStar_MakeNodeKey(current);
        closedSet[currentKey] = true; -- 标记已评估

        -- 检查是否到达目标
        if currentKey == goalKey then
            return self:ReconstructPath(cameFrom, current);
        end

        -- 检查当前节点的所有邻居
        local neighbors = squareMap:GetNeighbors(current.x, current.y);
        for _, neighbor in ipairs(neighbors) do
            repeat
                local neighborKey = FSRoomSquareMapAStar_MakeNodeKey(neighbor);

                -- 已经评估过的节点直接跳过
                if closedSet[neighborKey] then
                    break;
                end

                -- 计算从当前节点移动到邻居节点的代价
                local moveToNeighborCost = squareMap:MoveCost(current.x, current.y, neighbor.x, neighbor.y);
                -- 如果走current节点到邻居 起点到邻居将会多远
                local tentativeGScore = gScore[currentKey] + moveToNeighborCost;

                -- 如果找到更优路径，或该邻居尚未被访问过
                if not gScore[neighborKey] or tentativeGScore < gScore[neighborKey] then
                    -- 更新邻居节点信息
                    cameFrom[neighborKey] = current;       -- 记录前驱节点
                    gScore[neighborKey] = tentativeGScore; -- 更新g值
                    -- 计算f值 = g值 + h 值(启发式估价)
                    fScore[neighborKey] = tentativeGScore + squareMap:Distance(neighbor.x, neighbor.y, goalX, goalY);

                    -- Push会自动处理 不在堆中就添加 已在堆中就更新优先级
                    openSet:Push(neighbor, fScore[neighborKey]);
                end
            until true;
        end
    end

    -- openSet为空但未找到目标，说明无可达路径
    return nil;
end

---@param cameFrom table<string, FSRoomSquareMapTilePos>
---@param current FSRoomSquareMapTilePos
---@return table<integer,FSRoomSquareMapTilePos>
function FSRoomSquareMapAStar:ReconstructPath(cameFrom, current)
    ---@type table<integer,FSRoomSquareMapTilePos>
    local resultPath = { { x = current.x, y = current.y } };
    local currentKey = FSRoomSquareMapAStar_MakeNodeKey(current);

    -- 从重点回溯到起点
    while cameFrom[currentKey] ~= nil do
        current = cameFrom[currentKey];
        currentKey = FSRoomSquareMapAStar_MakeNodeKey(current);
        -- 插入到路径开头
        table.insert(resultPath, 1, { x = current.x, y = current.y });
    end

    return resultPath;
end

return FSRoomSquareMapAStar;
