local CoroutineMgrTest = {}

local CoroutineMgr = require("CoroutineMgrLogic")
local Log = require("Log")

function CoroutineMgrTest.Run()
    local sessionIDB = CoroutineMgr.Spawn(
        ---@async
        function ()
            Log:Error("Co B Start")
            -- 加入在此请求DB消息
            -- 然后Wait等待回调, 10秒没有回调结果回来则超时了
            local timeout, result, dbData = CoroutineMgr.Wait(10000)
            Log:Error(string.format("Co B Wait return %s %s userID %s", timeout, result, dbData.userID))
        end
    )

    local sessionIDA = CoroutineMgr.Spawn(
        ---@async
        function ()
            Log:Error("Co A Start")
            -- 加入在此请求DB消息
            -- 然后Wait等待回调, 2秒没有回调结果回来则超时了
            local timeout, result = CoroutineMgr.Wait(2000)
            Log:Error(string.format("Co A Wait return %s %s", timeout, result))
            CoroutineMgr.DebugDump()
            CoroutineMgr.Wakeup(sessionIDB, 123, { userID = 123, bag = {} })
            CoroutineMgr.DebugDump()
        end
    )

    local sessionIDC = CoroutineMgr.Spawn(
        ---@async
        function ()
            Log:Error("Co C Start")
            -- 加入在此请求DB消息
            -- 然后Wait等待回调, 5秒没有回调结果回来则超时了
            local timeout, result = CoroutineMgr.Wait(5000)
            Log:Error(string.format("Co C Wait return %s %s", timeout, result))
            CoroutineMgr.DebugDump()
        end
    )
end

return CoroutineMgrTest
