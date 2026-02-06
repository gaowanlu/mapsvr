--- 每帧内单个指令的数据结构
---@class FSRoomSyncFrameCommandType
---@field userId string
---@field commandType string
---@field data table
---@field frameId integer

--- 每帧的数据结构
---@class FSRoomSyncFrameType
---@field frameId integer
---@field timestamp number
---@field commands table<integer,FSRoomSyncFrameCommandType>

---@class FSRoomSync
---@field room FSRoom 所属房间
---@field currentFrame integer 当前帧号
---@field frameRate integer 帧率30FPS
---@field frameInterval number 每帧时间33ms
---@field frameHistory table<integer,FSRoomSyncFrameType> 历史帧
---@field frameCommands table<integer,FSRoomSyncFrameCommandType> 当前帧命令
---@field isRunning boolean 是否在运行
---@field lastFrameTime number 最后帧时间
local FSRoomSync = require("FSRoomSyncData");

local TimeMgr = require("TimeMgrLogic");


--- 创建新的FSRoom对象
---@param room FSRoom
---@return FSRoomSync
function FSRoomSync.new(room)
    ---@type FSRoomSync
    local self = setmetatable({}, FSRoomSync);
    self.room = room;
    self.currentFrame = 0;
    self.frameRate = 30;
    self.frameInterval = 33;
    self.frameHistory = {};
    self.frameCommands = {};

    self.isRunning = false;
    self.lastFrameTime = 0;

    return self;
end

function FSRoomSync:Start()
    self.isRunning = true;
    self.currentFrame = 0;
    self.lastFrameTime = TimeMgr.GetMS();
    self.frameHistory = {};
end

function FSRoomSync:Stop()
    self.isRunning = false;
end

---@param userId string 玩家ID
---@param commandType string 指令类型
---@param data any 指令数据
---@return boolean
function FSRoomSync:AddCommand(userId, commandType, data)
    if not self.isRunning then
        return false;
    end

    ---@type FSRoomSyncFrameCommandType
    local command = {
        userId = userId,
        commandType = commandType,
        data = data,
        frameId = self.currentFrame
    };

    table.insert(self.frameCommands, command);

    return true;
end

--- 检查是否需要跳入到下一帧
---@return boolean
function FSRoomSync:ShouldUpdate()
    if not self.isRunning then
        return false;
    end

    local currentTimeMS = TimeMgr.GetMS();

    local elapsed = currentTimeMS - self.lastFrameTime;

    return elapsed > self.frameInterval;
end

--- Tick调用
---@return table|nil 返回刚刚收集的新的一帧
function FSRoomSync:Update()
    if not self.isRunning then
        return nil
    end

    local currentTimeMS = TimeMgr.GetMS();
    local elapsed = currentTimeMS - self.lastFrameTime;

    -- 还不够一帧的间隔
    if elapsed < self.frameInterval then
        return nil
    end

    self.lastFrameTime = currentTimeMS;
    -- 更新当前帧号
    self.currentFrame = self.currentFrame + 1;

    -- 创建一个frame data
    ---@type FSRoomSyncFrameType
    local frame = {
        frameId = self.currentFrame,
        timestamp = TimeMgr.GetS(),
        commands = self.frameCommands
    };

    -- 将帧存到history
    table.insert(self.frameHistory, frame);

    -- 清空commands为下一帧
    self.frameCommands = {}

    return frame;
end

---@return integer 返回当前帧号
function FSRoomSync:GetCurrentFrame()
    return self.currentFrame;
end

---@return table 返回历史所有帧
function FSRoomSync:GetFrameHistory()
    return self.frameHistory;
end

--- 返回自从frameId之后的所有帧,不包含指定的frameId那帧
---@param frameId integer 帧号
---@return table<integer,FSRoomSyncFrameType>
function FSRoomSync:GetFramesSince(frameId)
    ---@type table<integer,FSRoomSyncFrameType>
    local missedFrames = {};

    for _, frame in ipairs(self.frameHistory) do
        if frame.frameId > frameId then
            table.insert(missedFrames, frame);
        end
    end

    return missedFrames;
end

--- 只保留keeepCount帧超过了则删除最老的
---@param keepCount integer
function FSRoomSync:ClearOldFrames(keepCount)
    keepCount = keepCount or 1000
    if #self.frameHistory > keepCount then
        local removeCount = #self.frameHistory - keepCount;
        for i = 1, removeCount do
            table.remove(self.frameHistory, 1);
        end
    end
end

---@class FSRoomSyncStatisticsType
---@field currentFrame integer 当前帧号
---@field totalFrames integer history中存了多少帧
---@field isRunning boolean 是否在运行
---@field pendingCommands integer 当前帧收到多少指令了

---@return FSRoomSyncStatisticsType
function FSRoomSync:GetStats()
    return {
        currentFrame = self.currentFrame,
        totalFrames = #self.frameHistory,
        isRunning = self.isRunning,
        pendingCommands = #self.frameCommands
    };
end

return FSRoomSync;
