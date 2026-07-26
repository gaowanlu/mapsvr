---@class CoroutineSession
---@field createTime integer 创建时间加上sessionID系统足够确定唯一协程
---@field co         thread
---@field finished   boolean
---@field isTimeout  boolean
---@field result     any
---@field wakeupTime integer
---@field tag        any

---@class CoroutineSleepPair
---@field sessionID  integer
---@field wakeupTime integer

CoroutineMgr = CoroutineMgr or {}

return CoroutineMgr
