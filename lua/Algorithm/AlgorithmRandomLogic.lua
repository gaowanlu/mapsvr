---@class AlgorithmRandom
AlgorithmRandom = AlgorithmRandom or {}

---@param m integer
---@param n integer
---@return integer
function AlgorithmRandom.Random(m, n)
    return math.random(m, n)
end

--- 判断命中的函数
---@param prob number 能命中的概率
---@return boolean 是否命中
function AlgorithmRandom.HitProbability(prob)
    local rand = math.random() -- 生成一个 0 到 1 之间的随机数
    return rand <= prob -- 如果随机数小于等于指定概率，则命中
end

--- 不放回抽取多次
---@param weights  table<integer, number>
---@param numDraws number
---@return table<integer, number>
function AlgorithmRandom.WeightedDraw(weights, numDraws)
    ---@type number
    local totalWeight = 0
    local remainingWeights = {}
    local remainingIndices = {}

    -- 计算总权重和初始化剩余权重
    for i, weight in ipairs(weights) do
        totalWeight = totalWeight + weight
        table.insert(remainingWeights, weight)
        table.insert(remainingIndices, i)
    end

    local draws = {}

    -- 限制抽取次数不超过权重数量
    local actualDraws = math.min(numDraws, #weights)

    -- 抽取 actualDraws 次
    for _ = 1, actualDraws do
        if totalWeight <= 0 then break end -- 防止权重为0时死循环

        local rand = math.random() * totalWeight
        ---@type number
        local currentWeight = 0
        ---@type integer | nil
        local selectedIndex = nil

        -- 按照剩余权重抽取
        for i, weight in ipairs(remainingWeights) do
            currentWeight = currentWeight + weight
            if rand <= currentWeight then
                selectedIndex = i
                break
            end
        end

        -- 抽中后，将抽中的元素从剩余元素中移除
        if selectedIndex ~= nil then
            table.insert(draws, remainingIndices[selectedIndex])
            totalWeight = totalWeight - remainingWeights[selectedIndex]
            table.remove(remainingWeights, selectedIndex)
            table.remove(remainingIndices, selectedIndex)
        end
    end

    return draws
end

---@class AlgorithmRandomWeightedDrawSingleScene
---@field totalWeight      number
---@field remainingWeights table<integer, number>
---@field remainingIndices table<integer, number>
---@field selectedIndex    number

--- 创建新的抽奖场景
---@param weights table<integer, number> 权重列表
---@return AlgorithmRandomWeightedDrawSingleScene scene 初始化的场景数据
function AlgorithmRandom.CreateDrawScene(weights)
    ---@type AlgorithmRandomWeightedDrawSingleScene
    local scene = { totalWeight = 0, remainingWeights = {}, remainingIndices = {}, selectedIndex = 0 }

    for i, weight in ipairs(weights) do
        scene.totalWeight = scene.totalWeight + weight
        table.insert(scene.remainingWeights, weight)
        table.insert(scene.remainingIndices, i)
    end

    return scene
end

--- 抽取一个并保存抽奖场景（可放回版本）
---@param weights table<integer, number>                 权重列表
---@param scene   AlgorithmRandomWeightedDrawSingleScene 场景数据，包含剩余的权重和索引
---@return number selectedIndex                                被抽中的索引
---@return AlgorithmRandomWeightedDrawSingleScene updatedScene 更新后的场景数据
function AlgorithmRandom.WeightedDrawSingle(weights, scene)
    -- 如果场景中没有剩余的权重和索引（即第一次抽取），初始化它们
    if not scene or not scene.remainingWeights or #scene.remainingWeights == 0 then
        scene = AlgorithmRandom.CreateDrawScene(weights)
    end

    local remainingWeights = scene.remainingWeights
    local remainingIndices = scene.remainingIndices

    -- 如果没有剩余元素，返回0
    if #remainingWeights == 0 then
        return 0, scene
    end

    -- 计算剩余的总权重
    ---@type number
    local totalWeight = 0
    for _, weight in ipairs(remainingWeights) do
        totalWeight = totalWeight + weight
    end

    -- 如果总权重为0，返回0
    if totalWeight <= 0 then
        return 0, scene
    end

    -- 抽取一个
    local rand = math.random() * totalWeight
    ---@type number
    local currentWeight = 0
    ---@type integer | nil
    local selectedIndex = nil

    for i, weight in ipairs(remainingWeights) do
        currentWeight = currentWeight + weight
        if rand <= currentWeight then
            selectedIndex = i
            break
        end
    end

    -- 设置选中的索引（但不移除，可重复抽取）
    if selectedIndex ~= nil then
        scene.selectedIndex = remainingIndices[selectedIndex]
    else
        scene.selectedIndex = 0
    end

    return scene.selectedIndex, scene
end

--- 抽取一个并保存抽奖场景（不放回版本）
---@param scene AlgorithmRandomWeightedDrawSingleScene 场景数据，包含剩余的权重和索引
---@return number selectedIndex                                被抽中的索引，如果没有剩余元素则返回0
---@return AlgorithmRandomWeightedDrawSingleScene updatedScene 更新后的场景数据
function AlgorithmRandom.WeightedDrawSingleNoRepeat(scene)
    local remainingWeights = scene.remainingWeights
    local remainingIndices = scene.remainingIndices

    -- 如果没有剩余元素，返回0
    if #remainingWeights == 0 then
        return 0, scene
    end

    -- 计算剩余的总权重
    ---@type number
    local totalWeight = 0
    for _, weight in ipairs(remainingWeights) do
        totalWeight = totalWeight + weight
    end

    -- 如果总权重为0，返回0
    if totalWeight <= 0 then
        return 0, scene
    end

    -- 抽取一个
    local rand = math.random() * totalWeight
    ---@type number
    local currentWeight = 0
    ---@type integer | nil
    local selectedIndex = nil

    for i, weight in ipairs(remainingWeights) do
        currentWeight = currentWeight + weight
        if rand <= currentWeight then
            selectedIndex = i
            break
        end
    end

    -- 更新场景数据，移除已抽中的元素（不放回）
    if selectedIndex ~= nil then
        scene.selectedIndex = remainingIndices[selectedIndex]
        -- 移除已抽中的元素
        table.remove(scene.remainingWeights, selectedIndex)
        table.remove(scene.remainingIndices, selectedIndex)
    else
        scene.selectedIndex = 0
    end

    return scene.selectedIndex, scene
end

---@param seed integer
function AlgorithmRandom.RandomSeed(seed)
    math.randomseed(seed)
end

-- 直接运行时的测试代码
if not ... then -- 如果是直接运行而非被 require
    AlgorithmRandom.RandomSeed(os.time()) -- 设置种子

    -- 测试命中概率
    print("=== 测试命中概率 ===")
    if AlgorithmRandom.HitProbability(0.3) then
        print("命中！")
    else
        print("未命中！")
    end

    -- 测试带权重的抽奖
    print("\n=== 测试不放回抽取多次 ===")
    local weights = { 10, 20, 30, 40 }
    local num_draws = 2

    local selected = AlgorithmRandom.WeightedDraw(weights, num_draws)

    print("抽中的下标：")
    for _, idx in ipairs(selected) do
        print(idx)
    end

    -- 测试抽取一个（可放回版本）
    print("\n=== 测试抽取一个（可放回版本）===")
    local scene1 = AlgorithmRandom.CreateDrawScene({ 1, 2, 3, 4 })

    for i = 1, 5 do
        local selectedIndex, updatedScene = AlgorithmRandom.WeightedDrawSingle({ 1, 2, 3, 4 }, scene1)
        print(string.format("抽中的下标（第 %d 次）：", i), selectedIndex)
        scene1 = updatedScene
    end

    -- 测试抽取一个（不放回版本）
    print("\n=== 测试抽取一个（不放回版本）===")
    local scene2 = AlgorithmRandom.CreateDrawScene({ 1, 2, 3, 4, 5, 6, 7, 8 })

    -- 抽取 9 次
    for i = 1, 9 do
        local selectedIndex, updatedScene = AlgorithmRandom.WeightedDrawSingleNoRepeat(scene2)
        print(string.format("抽中的下标（第 %d 次）：%d", i, selectedIndex))
        print("剩余权重：", table.concat(updatedScene.remainingWeights, ", "))
        print("剩余索引：", table.concat(updatedScene.remainingIndices, ", "))
        scene2 = updatedScene -- 更新场景，准备下一次抽取
    end

    print("\n=== 测试抽取一个（不放回版本）===")
    local scene3 = AlgorithmRandom.CreateDrawScene({ 1.32, 2.43, 3.54, 4.65, 5.76, 6.34, 7.54, 8 })

    -- 抽取 9 次
    for i = 1, 9 do
        local selectedIndex, updatedScene = AlgorithmRandom.WeightedDrawSingleNoRepeat(scene3)
        print(string.format("抽中的下标（第 %d 次）：%d", i, selectedIndex))
        print("剩余权重：", table.concat(updatedScene.remainingWeights, ", "))
        print("剩余索引：", table.concat(updatedScene.remainingIndices, ", "))
        scene3 = updatedScene -- 更新场景，准备下一次抽取
    end
end

-- 返回模块
return AlgorithmRandom
