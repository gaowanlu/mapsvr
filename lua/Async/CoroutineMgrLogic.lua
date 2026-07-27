---@class CoroutineMgr
---@field sessionSeed         integer
---@field coToSessionID       table<thread, integer>             协程对象映射到协程ID
---@field sessions            table<integer, CoroutineSession>   协程ID映射到CoroutineSession
---@field readyQueue          table<integer, integer>            就绪队列只存sessionID
---@field sleepList           table<integer, CoroutineSleepPair> 定时器最小堆
---@field MAX_RESUME_PER_TICK integer                            每帧update最多resume多少
---@field lastTickMS          integer                            最后一次Tick毫秒时间戳
local CoroutineMgr = require("CoroutineMgrData")

local TimeMgr = require("TimeMgrLogic")
local Log = require("Log")

---@diagnostic disable-next-line: access-invisible
local unpack = table.unpack or unpack

CoroutineMgr.sessionSeed = CoroutineMgr.sessionSeed or 0
CoroutineMgr.coToSessionID = CoroutineMgr.coToSessionID or {}
CoroutineMgr.sessions = CoroutineMgr.sessions or {}
CoroutineMgr.readyQueue = CoroutineMgr.readyQueue or {}
CoroutineMgr.sleepList = CoroutineMgr.sleepList or {}
CoroutineMgr.MAX_RESUME_PER_TICK = CoroutineMgr.MAX_RESUME_PER_TICK or 10000
CoroutineMgr.lastTickMS = CoroutineMgr.lastTickMS or TimeMgr.GetMS()

-- Min-Heap utility functions for sleepList
local function heapPush(list, item)
    table.insert(list, item)
    local idx = #list
    while idx > 1 do
        local parent = math.floor(idx / 2)
        if list[idx].wakeupTime < list[parent].wakeupTime then
            list[idx], list[parent] = list[parent], list[idx]
            idx = parent
        else
            break
        end
    end
end

local function heapPop(list)
    if #list == 0 then return nil end
    local root = list[1]
    local last = table.remove(list)
    if #list > 0 then
        list[1] = last
        local idx = 1
        while true do
            local left = idx * 2
            local right = idx * 2 + 1
            local smallest = idx
            if left <= #list and list[left].wakeupTime < list[smallest].wakeupTime then
                smallest = left
            end
            if right <= #list and list[right].wakeupTime < list[smallest].wakeupTime then
                smallest = right
            end
            if smallest ~= idx then
                list[idx], list[smallest] = list[smallest], list[idx]
                idx = smallest
            else
                break
            end
        end
    end
    return root
end

local function heapPeek(list)
    return list[1]
end
function CoroutineMgr.OnTick()
    CoroutineMgr.lastTickMS = TimeMgr.GetMS()

    -- 检查超时的协程
    while #CoroutineMgr.sleepList > 0 and heapPeek(CoroutineMgr.sleepList).wakeupTime <= CoroutineMgr.lastTickMS do
        local item = heapPop(CoroutineMgr.sleepList)
        local sessionID = item.sessionID
        local info = CoroutineMgr.sessions[sessionID]

        -- 惰性忽略 如果已经被 wakeup result不为空 或已死 则跳过
        if info and info.wakeupTime == item.wakeupTime and not info.result and not info.finished then
            info.isTimeout = true
            info.result = {}
            table.insert(CoroutineMgr.readyQueue, sessionID)
        end
    end

    -- 执行就绪队列中的协程
    local resumeCount = 0
    local head = 1
    local queueSize = #CoroutineMgr.readyQueue

    while head <= queueSize do
        if resumeCount >= CoroutineMgr.MAX_RESUME_PER_TICK then
            Log:Error("[CoroManager WARN] Exceeded max resume count per tick, delaying to next frame.")
            break
        end
        resumeCount = resumeCount + 1

        local sessionID = CoroutineMgr.readyQueue[head]
        head = head + 1

        local info = CoroutineMgr.sessions[sessionID]

        if info and not info.finished then
            local co = info.co
            -- 传入唤醒参数
            local ok, err = coroutine.resume(co, unpack(info.result or {}))

            if not ok then
                -- 错误隔离 打印错误 防止整个服务器崩溃
                Log:Error("sessionID %s resume failed: %s", tostring(sessionID), tostring(err))
            elseif coroutine.status(co) == "dead" then
                -- 协程正常结束
                CoroutineMgr.DestroySession(sessionID)
            end
        end
    end

    -- 清理 readyQueue
    if head > 1 then
        for i = 1, head - 1 do
            CoroutineMgr.readyQueue[i] = nil
        end
    end
end

-- 为新协程生成序号
---@return integer, integer
function CoroutineMgr.GenSessionID()
    if CoroutineMgr.sessionSeed >= avant.INT32_MAX then
        CoroutineMgr.sessionSeed = 0
    end

    repeat
        CoroutineMgr.sessionSeed = CoroutineMgr.sessionSeed + 1
    until CoroutineMgr.sessions[CoroutineMgr.sessionSeed] == nil

    return CoroutineMgr.sessionSeed, CoroutineMgr.lastTickMS
end

-- 二分查找插入定时器列表 保持升序
function CoroutineMgr.InsertSleepList(sessionID, wakeupTime)
    heapPush(CoroutineMgr.sleepList, { sessionID = sessionID, wakeupTime = wakeupTime })
end

-- 根据sessionID销毁协程
---@param sessionID integer
function CoroutineMgr.DestroySession(sessionID)
    ---@type CoroutineSession | nil
    local info = CoroutineMgr.sessions[sessionID]
    if info == nil then
        return
    end

    CoroutineMgr.coToSessionID[info.co] = nil
    CoroutineMgr.sessions[sessionID] = nil
end

-- 获取当前协程ID
---@return integer | nil
function CoroutineMgr.CurrentSessionID()
    local co = coroutine.running()
    if co == nil then
        return nil
    end
    return CoroutineMgr.coToSessionID[co]
end

-- 给当前协程打标签，方便调试
---@param tag any
---@return boolean
function CoroutineMgr.SetTag(tag)
    local sessionID = CoroutineMgr.CurrentSessionID()
    if sessionID == nil then
        return false
    end

    if CoroutineMgr.sessions[sessionID] == nil then
        return false
    end

    CoroutineMgr.sessions[sessionID].tag = tag
    return true
end

-- 创建并启动一个新的协程
---@param func function 协程人物函数
---@return integer 新创建的协程SessionID
function CoroutineMgr.Spawn(func, ...)
    local sessionID, timeMS = CoroutineMgr.GenSessionID()
    local co = coroutine.create(func)

    CoroutineMgr.sessions[sessionID] = {
        createTime = timeMS,
        co = co,
        finished = false,
        isTimeout = false,
        result = { ... },
        tag = "untagged",
        wakeupTime = nil
    }

    CoroutineMgr.coToSessionID[co] = sessionID

    table.insert(CoroutineMgr.readyQueue, sessionID)

    return sessionID
end

-- 挂起当前协程，并设置超时时间
---@async
---@param timeout integer
---@return boolean, ... 外部wakeup传入的参数
function CoroutineMgr.Wait(timeout)
    local co = coroutine.running()
    local sessionID = CoroutineMgr.coToSessionID[co]

    if not sessionID then
        error("CoroutineMgr.Wait must be called inside a spawned coroutine")
    end

    local info = CoroutineMgr.sessions[sessionID]
    info.result = nil

    if timeout and timeout > 0 then
        info.wakeupTime = TimeMgr.GetMS() + timeout
        CoroutineMgr.InsertSleepList(sessionID, info.wakeupTime)
    end

    coroutine.yield()

    -- 恢复执行
    local isTimeout = info.isTimeout
    local result = info.result or {}

    -- 清理状态
    info.isTimeout = false
    info.result = nil
    info.wakeupTime = nil

    return isTimeout, unpack(result)
end

-- 唤醒某个被挂起的协程，并传入参数
---@param sessionID integer
function CoroutineMgr.Wakeup(sessionID, ...)
    local info = CoroutineMgr.sessions[sessionID]

    -- 没找到管理的协程或协程已经结束了
    if not info or info.finished then
        return false
    end

    if info.result then
        -- 已经在就绪队列中，防止多次wakeup导致参数覆盖
        -- result设置一次就需要让协程处理一次然后才能在设置
        return false
    end

    info.result = { ... }
    info.isTimeout = false

    -- 惰性删除 不直接从 sleepList 删除 在update时自动跳过
    table.insert(CoroutineMgr.readyQueue, sessionID)
    return true
end

-- 强制杀死某个协程
---@param sessionID integer
---@return boolean
function CoroutineMgr.Kill(sessionID)
    local info = CoroutineMgr.sessions[sessionID]

    if info and not info.finished then
        info.finished = true
        CoroutineMgr.DestroySession(sessionID)
        return true
    end

    return false
end

-- 调试打印当前所有存活的协程信息 用于排查
function CoroutineMgr.DebugDump()
    local count = 0
    Log:Error("===== Coroutine Manager Debug Dump =====")
    for sid, info in pairs(CoroutineMgr.sessions) do
        count = count + 1
        local status = coroutine.status(info.co)
        local res = info.result and "Pending Resume" or "Waiting"
        Log:Error(string.format("SID:%d | Tag:%s | Status:%s | State:%s", sid, info.tag, status, res))
    end
    Log:Error("========================================")
end

return CoroutineMgr
