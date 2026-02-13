---@class FSRoomDbDataType
---@field id number 房间号
---@field name string 房间名

---@class FSRoom
---@field STATE_WAITING string
---@field STATE_READY string
---@field STATE_RUNNING string
---@field STATE_FINISHED string
---@field state string
---@field lastUpdateStateTime integer
---@field maxPlayers integer
---@field map FSRoomSquareMap
---@field battle FSRoomBattle
---@field sync FSRoomSync
---@field FSRoomDbData FSRoomDbDataType
---@field roomPlayers table<string,FSRoomPlayer>
---@field roomPlayersCnt integer
local FSRoom = require("FSRoomData")
local Log = require("Log")
local FSRoomMapFactory = require("FSRoomMapFactoryLogic");
local FSRoomBattle = require("FSRoomBattleLogic");
local FSRoomSync = require("FSRoomSyncLogic");
local FSRoomPlayer = require("FSRoomPlayerLogic");

local AlgorithmRandom = require("AlgorithmRandomLogic");

-- Room states
FSRoom.STATE_WAITING = "waiting"
FSRoom.STATE_READY = "ready"
FSRoom.STATE_RUNNING = "running"
FSRoom.STATE_FINISHED = "finished"

-- 构造新的FSRoom对象
---@param roomId integer
---@param maxPlayers integer
---@return FSRoom
function FSRoom.new(roomId, maxPlayers)
    ---@type FSRoom
    local self = setmetatable({}, FSRoom); -- 本质是 setmetatable({},{_index=FSRoom})

    -- 模拟FSRoom的DB字段
    self.FSRoomDbData = {
        id = roomId,
        name = "FSRoom_" .. tostring(roomId)
    };

    self.roomPlayers = {};
    self.roomPlayersCnt = 0;

    self.state = FSRoom.STATE_WAITING;
    self.lastUpdateStateTime = 0;
    self.maxPlayers = maxPlayers;

    -- 初始化房间地图
    self.map = FSRoomMapFactory.CreateMap(FSRoomMapFactory.MapTypes.ISO_4DIR, 20, 20);

    -- 初始化Battle
    self.battle = FSRoomBattle.new(self, self.map);

    self.sync = FSRoomSync.new(self);

    return self
end

---@param playerId string
---@param userId string
---@return bool,string
function FSRoom:AddPlayerToRoom(playerId, userId)
    -- 房间人满了
    if self.roomPlayersCnt >= self.maxPlayers then
        return false, "Room is full"
    end

    -- 房间状态必须为WAITING或READY
    if self.state ~= FSRoom.STATE_WAITING and self.state ~= FSRoom.STATE_READY then
        return false, "Room game aready started"
    end

    -- 检查玩家是否已经在房间内了
    if self.roomPlayers[userId] ~= nil then
        return false, "player already in room"
    end

    -- 创建一个RoomPlayer
    self.roomPlayers[userId] = FSRoomPlayer.new(playerId, userId, self);
    self.roomPlayersCnt = self.roomPlayersCnt + 1;

    local newRoomPlayer = self.roomPlayers[userId];
    -- 设置出生位置
    local spawnX = AlgorithmRandom.Random(10, self.map.width - 10);
    local spawnY = AlgorithmRandom.Random(10, self.map.height - 10);

    -- 防止出生在不能行走的瓦片
    while not self.map:IsWalkable(spawnX, spawnY) do
        spawnX = AlgorithmRandom.Random(10, self.map.width - 10);
        spawnY = AlgorithmRandom.Random(10, self.map.height - 10);
    end
    newRoomPlayer:SetPosition(spawnX, spawnY);

    -- 为玩家添加默认技能
    newRoomPlayer:AddSkill(1); -- Basic attack
    newRoomPlayer:AddSkill(2); -- Fireball
    newRoomPlayer:AddSkill(3); -- Heal

    Log:Error("player playerId %s userId %s joined room %s", playerId, userId, tostring(self.FSRoomDbData.id));

    -- 广播消息给其他玩家
    -- self:Broadcast(0, { 有新玩家加入房间 }, userId);

    return true, ""
end

--- 返回房间当前状态
---@return string
function FSRoom:GetState()
    return self.state;
end

--- 房间Tick调用由 FSRoomMgr调用
function FSRoom:OnTick()
end

--- 从房间内移除指定玩家
---@param playerId string
---@param userId string
---@return boolean
function FSRoom:RemovePlayerFromRoom(playerId, userId)
    local player = self.roomPlayers[userId];
    if not player then
        return false;
    end

    -- 直接移除
    self.roomPlayers[userId] = nil;
    self.roomPlayersCnt = self.roomPlayersCnt - 1;

    Log:Error("roomPlayer userId %s left room %s", userId, tostring(self.FSRoomDbData.id));

    -- 给其他玩家广播这个玩家离开了房间
    -- self:Broadcast(0, { 有玩家离开了房间 }, userId);

    -- 没有足够玩家则终止比赛
    -- 如果房间是空的 或 房间在运行中且没有足够玩家 结束游戏
    if self.roomPlayersCnt == 0 then
        self:FinishGame(nil, "all players left");
    elseif self.state == FSRoom.STATE_RUNNING then
        local gameEnd, winnerUserId = self.battle:CheckGameEnd();
        if gameEnd then
            self:FinishGame(winnerUserId, "Not enough players");
        end
    end

    return true;
end

---@param userId string
---@return FSRoomPlayer|nil
function FSRoom:GetRoomPlayer(userId)
    return self.roomPlayers[userId];
end

---@param userId string
---@return boolean 是否设置成功
function FSRoom:SetPlayerReady(userId)
    local roomPlayer = self.roomPlayers[userId];
    if not roomPlayer then
        return false;
    end

    roomPlayer.isReady = true;
    Log:Error("roomPlayer userId %s is ready in room %s", roomPlayer.userId, tostring(self.FSRoomDbData.id));

    -- 检查所有玩家都是否就绪了
    if self:AllPlayersReady() then
        self:StartGame(); -- 就绪了就开始游戏
    end

    return true;
end

---@return boolean 房间内所有玩家是否都已经ready
function FSRoom:AllPlayersReady()
    -- 小于两人不能玩
    if self.roomPlayersCnt < 2 then
        return false;
    end

    -- 全部roomPlayer都要ready
    for _, player in pairs(self.roomPlayers) do
        if not player.isReady then
            return false;
        end
    end

    return true;
end

---@return boolean
function FSRoom:StartGame()
    -- 只能是WAITING或READY状态才能 StartGame
    if self.state ~= FSRoom.STATE_WAITING and self.state ~= FSRoom.STATE_READY then
        return false;
    end

    self.state = FSRoom.STATE_RUNNING;
    self.sync:Start();

    Log:Error("Game started in room %s with %d players", tostring(self.FSRoomDbData.id), self.roomPlayersCnt);

    -- local initialState = {
    --     -- players = { 游戏的初始玩家信息 },
    --     -- map = { 游戏的地图初始消息 }
    -- };
    -- -- 游戏初始数据广播给所有roomPlayer
    -- self:Broadcast(0, initialState);

    return true;
end

---@param winnerUserId string|nil
---@param reason string
function FSRoom:FinishGame(winnerUserId, reason)
    -- 只有RUNNING状态才能FinishGame
    if self.state ~= FSRoom.STATE_RUNNING then
        return;
    end

    self.state = FSRoom.STATE_FINISHED;
    self.sync:Stop();

    Log:Error("Game finished in room %s winnerUserId %s Reason %s",
        tostring(self.FSRoomDbData.id),
        winnerUserId or "none",
        reason or "completed"
    );

    -- 在此，结束时可能把协议必要信息持久化，例如游戏内帧信息，保存下来用于游戏回放

    -- self:Broadcast(0, { 广播游戏结束 });
end

--- 房间内接收到新客户端指令
---@param userId string
---@param commandType string
---@param data table
---@return boolean
function FSRoom:ProcessCommand(userId, commandType, data)
    if self.state ~= FSRoom.STATE_RUNNING then
        return false;
    end

    -- 先提交给sync组件存着
    self.sync:AddCommand(userId, commandType, data);

    return true;
end

--- 房间Tick
function FSRoom:Update()
    if self.state ~= FSRoom.STATE_RUNNING then
        return;
    end

    -- 距离上次形成一帧到现在是否已经满足了一帧的条件
    if not self.sync:ShouldUpdate() then
        return;
    end

    -- 够一帧了，收集刚才收集的指令，返回新的一帧
    local frame = self.sync:Update();
    if not frame then
        return;
    end

    -- 处理刚刚收集的最新一帧
    local frameResults = {};
    -- 把帧内所有command交给battle组件跑
    for _, command in ipairs(frame.commands) do
        local result = self.battle:ProcessCommand(command);
        table.insert(frameResults, result);
    end

    -- battle组件的tick
    self.battle:UpdateFrame();

    -- 检查游戏结束条件
    local gameEnd, winnerUserId = self.battle:CheckGameEnd();
    if gameEnd then
        self:FinishGame(winnerUserId, "Battle ended");
    end

    -- 广播新的这帧给房间内所有玩家
    -- local frameMessage = {
    --     frameId,
    --     timesStamp,
    --     commands,
    --     results = frameResults
    -- };
    -- self:Broadcast(0, frameMesage)

    -- 也许为了防止服务器压力直接清空一些老帧
    -- self.sync:ClearOldFrames(1000);
end

--- 房间玩家断线重连
---@param playerId string
---@param userId string
---@param lastFrameId integer 玩家本地最新一帧帧号
---@return boolean
function FSRoom:HandleReconnect(playerId, userId, lastFrameId)
    local roomPlayer = self.roomPlayers[userId];
    if not roomPlayer then
        return false;
    end

    -- 当前帧号
    local currentFrame = self.sync:GetCurrentFrame();
    local missedFrames = self.sync:GetFramesSince(lastFrameId);

    -- 更新roomPlayer的playerId 确保session正确
    roomPlayer.playerId = playerId;

    Log:Error("Player userId %s reconnected to room %s, missed frames %d",
        userId,
        tostring(self.FSRoomDbData.id),
        #missedFrames
    );

    -- 重连追帧 一个协议不一定发得完，可能是需要多次tick发出去
    -- 需要一定设计
    -- local reconnectMsg = {
    --     userId,
    --     currentFrame,
    --     missedFrames
    -- };

    return true;
end

--- 广播消息给房间内的玩家
---@param cmd integer
---@param message table
---@param exceptUserId string
function FSRoom:Broadcast(cmd, message, exceptUserId)
    for userId, roomPlayer in pairs(self.roomPlayers) do
        if roomPlayer.isConnected and userId ~= exceptUserId then
            -- 将消息发给roomPlayer客户端
        end
    end
end

--- 发送消息给房间内的执行玩家
---@param cmd integer
---@param message table
---@param userId string
function FSRoom:SendToRoomPlayer(cmd, message, userId)
    local roomPlayer = self.roomPlayers[userId];

    if roomPlayer and roomPlayer.isConnected then
        -- 将消息发给roomPlayer客户端
    end
end

---被FSRoomMgr删除前调用 房间对象被销毁之前 房间状态早已经变为STATE_FINISHED
function FSRoom:DeleteBefore()
    Log:Error("FSRoom %s DeleteBefore()", tostring(self.FSRoomDbData.id));
end

--- 获取目前房间内玩家个数
---@return integer
function FSRoom:GetRoomPlayersCnt()
    return self.roomPlayersCnt;
end

return FSRoom;
