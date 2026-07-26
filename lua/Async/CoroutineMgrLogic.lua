---@class CoroutineMgr
---@field sessionSeed         integer
---@field coToSessionID       table<thread, integer>             协程对象映射到协程ID
---@field sessions            table<integer, CoroutineSession>   协程ID映射到CoroutineSession
---@field readyQueue          table<integer, integer>            就绪队列只存sessionID
---@field sleepList           table<integer, CoroutineSleepPair> 定时器列表，按唤醒时间升序
---@field MAX_RESUME_PER_TICK integer                            每帧update最多resume多少
---@field lastTickMS          integer                            最后一次Tick毫秒时间戳
local CoroutineMgr = require("CoroutineMgrData")

local TimeMgr = require("TimeMgrLogic")
local Log = require("Log")

CoroutineMgr.sessionSeed = CoroutineMgr.sessionSeed or 0
CoroutineMgr.coToSessionID = CoroutineMgr.coToSessionID or {}
CoroutineMgr.sessions = CoroutineMgr.sessions or {}
CoroutineMgr.readyQueue = CoroutineMgr.readyQueue or {}
CoroutineMgr.sleepList = CoroutineMgr.sleepList or {}
CoroutineMgr.MAX_RESUME_PER_TICK = CoroutineMgr.MAX_RESUME_PER_TICK or 10000
CoroutineMgr.lastTickMS = CoroutineMgr.lastTickMS or 0

function CoroutineMgr.OnTick()
    CoroutineMgr.lastTickMS = TimeMgr.GetMS()

    local newSessionID, timeMS = CoroutineMgr.GenSessionID()
    Log:Error(
        "newSessionID %s timeMS %s %s", tostring(newSessionID), tostring(timeMS),
        tostring(CoroutineMgr.lastTickMS == timeMS)
    )
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
    local left, right = 1, #CoroutineMgr.sleepList + 1
    while left < right do
        local mid = math.floor((left + right) / 2)
        if CoroutineMgr.sleepList[mid].wakeupTime <= wakeupTime then
            left = mid + 1
        else
            right = mid
        end
    end
    table.insert(CoroutineMgr.sleepList, left, { sessionID = sessionID, wakeupTime = wakeupTime })
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

function CoroutineMgr.CurrentSessionID()
    local co = coroutine.running()
    return CoroutineMgr.coToSessionID[co]
end

-- TODO: set_tag\spawn\wait\wakeup\sleep\kill\debug_dump\update

return CoroutineMgr
