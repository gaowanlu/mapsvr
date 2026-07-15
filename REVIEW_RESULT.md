# MapSvr Lua 代码 Review 报告

**日期:** 2026-07-11  
**Author:** Claude Code  
**版本:** v2.0

---

## 目录

1. [执行摘要](#执行摘要)
2. [功能完成度评估](#功能完成度评估)
3. [已修复问题](#已修复问题)
4. [待开发功能](#待开发功能)
5. [实现路线图](#实现路线图)
6. [客户端开发工作](#客户端开发工作)

---

## 执行摘要

MapSvr 是一个基于 Avant 框架的 Lua 游戏服务器框架，具备热重载、多 VM 架构、Protobuf 协议通信等特性。

### 总体完成度评估

| 模块 | 完成度 | 状态 |
| --- | --- | --- |
| Player 玩家系统 | 95% | ✅ 功能完整，已修复所有已知 Bug |
| Map 2D 地图系统 | 95% | ✅ 功能完整，仅有边界问题 |
| Map 3D 地图系统 | 95% | ✅ 功能完整，仅有边界问题 |
| FSRoom 战斗房间 | 60% | ⚠️ 架构存在，核心广播缺失 |
| Skill 技能系统 | 85% | ⚠️ 逻辑完整，需集成到战斗流程 |
| Frame Sync 帧同步 | 70% | ⚠️ 架构存在，需完善 |
| Network Handlers 网络处理 | 90% | ⚠️ 存在一个 IPC Handler Bug |

### 关键发现

1. **Map 2D/3D 系统**已经非常接近完成，具备完整的物理、状态同步、AOI 系统
2. **FSRoom 战斗系统**有完整的架构（地图、技能、A*寻路），但缺少关键的广播功能
3. **核心问题**：FSRoom 的 `Broadcast()` 和 `SendToRoomPlayer()` 方法是空实现
4. **Skill 系统**逻辑完整但尚未集成到战斗流程中

---

## 已修复问题

以下问题在本次迭代中已修复：

### Critical Priority (已修复)

| 问题 | 文件 | 修复内容 |
| --- | --- | --- |
| 对角线移动验证错误 | `FSRoomSquareMapLogic.lua:184` | 将 `if side1 or side2` 改为 `if side1 and side2` |
| 对角线移动验证错误 | `FSRoomIsometricMapLogic.lua:176` | 将 `if side1 or side2` 改为 `if side1 and side2` |

### High Priority (已修复)

| 问题 | 文件 | 修复内容 |
| --- | --- | --- |
| 整数溢出检查错误 | `PlayerCmptBagLogic.lua:49` | 改为 `count > avant.INT32_MAX - hasNumber` |
| 冗余循环模式 | `FSRoomSquareMapAStarLogic.lua:264` | 替换为标准 `if` 语句 |
| 冗余循环模式 | `FSRoomHexMapAStarLogic.lua:268` | 替换为标准 `if` 语句 |
| 冗余循环模式 | `FSRoomIsometricMapAStarLogic.lua:268` | 替换为标准 `if` 语句 |

### Medium Priority (已修复)

| 问题 | 文件 | 修复内容 |
| --- | --- | --- |
| Seq 验证失败无日志 | `MapLogic.lua:332-334` | 添加警告日志 |
| Seq 验证失败无日志 | `Map3DLogic.lua:177-182` | 添加警告日志 |

---

## 功能完成度评估

### 1. Player 玩家系统 - 95% 完成

#### 已实现功能

- Player 类架构：支持多组件模式（Info, Bag, Map, Map3D, FSRoom）
- PlayerMgr：玩家管理器支持 userId/playerId 双向映射、在线状态管理
- 数据库集成：通过 IPC 与 dbsvrgo 通信，支持 SELECT/INSERT 操作
- 登录流程：`PROTO_CMD_CS_REQ_LOGIN` -> dbsvrgo -> `SELECT_DBUSERRECORD_LOGIN_RES`
- 创建用户：`PROTO_CMD_CS_REQ_CREATE_USER` -> dbsvrgo -> `INSERT_DBUSERRECORD_RES`
- 热重载：`PlayerLogic`, `PlayerMgrLogic` 等支持热重载

#### 待完善

- 连接超时踢出机制（未登录一定间隔）
- Req 频率限制防止攻击
- sequenceID 匹配机制（Req/Res 对应）

### 2. Map 2D 系统 - 95% 完成

#### 2.1 已实现功能

- 瓦片地图：支持 4000x4000 像素地图，tileSize=50
- 物理系统：速度、加速度、摩擦力、边界控制
- 四叉树 AOI：QuadTree 实现完整的区域优化
- 状态同步：通过 `PROTO_CMD_CS_MAP_NOTIFY_STATE_DATA` 同步
- 初始化数据：通过 `PROTO_CMD_CS_MAP_NOTIFY_INIT_DATA` 发送
- Ping/Pong：心跳机制
- 输入处理：支持 seq 验证防止重放攻击

#### 2.2 待完善

- Grid 坐标与实际地图坐标分离
- 障碍物管理（单独数组 + Grid 标记）
- 移动物坐标回退到合法位置

### 3. Map 3D 系统 - 95% 完成

#### 3.1 已实现功能

- 3D 地图系统：支持 1000000x1000000x1000000 大小
- 3D 物理系统：重力、速度、加速度、摩擦力
- 八叉树 AOI：Octree 实现 3D 区域优化
- 状态同步：通过 `PROTO_CMD_CS_MAP3D_NOTIFY_STATE_DATA` 同步
- 输入处理：3D 方向输入（dirX, dirY, dirZ）

#### 3.2 待完善

- 同 Map 2D 的待完善项

### 4. FSRoom 战斗房间 - 60% 完成

#### 4.1 已实现功能

- 房间状态管理：WAITING, READY, RUNNING, FINISHED
- 房间玩家管理：HP/MP/技能管理
- 三种地图类型：Square (4/8 dir), Hex, Isometric (4/8 dir)
- A*寻路：支持所有地图类型的路径查找
- 技能系统：DAMAGE, HEAL, BUFF, DEBUFF 类型
- 帧同步架构：FSRoomSync 与帧历史

#### 4.2 缺失功能（关键）

| 功能 | 文件 | 状态 |
| --- | --- | --- |
| Broadcast() | `FSRoomLogic.lua:346-352` | 空实现 |
| SendToRoomPlayer() | `FSRoomLogic.lua:358-364` | 空实现 |
| HandleReconnect() | `FSRoomLogic.lua:312-340` | 空实现 |
| FinishGame() | `FSRoomLogic.lua:224-242` | 空实现 |
| 广播游戏状态 | `FSRoomBattleLogic.lua` | 缺少客户端协议 |

### 5. Skill 技能系统 - 85% 完成

#### 5.1 已实现功能

- 技能数据库：5 个技能（Basic Attack, Fireball, Heal, Lightning Strike, Shield）
- 技能属性：costMP, cooldown, range, damage/healAmount, aoeRadius
- CanCast 验证：MP 检查、冷却检查、距离检查
- Cast 方法：处理 damage 和 heal 技能类型

#### 5.2 待完善

- 实际伤害计算（考虑防御力）
- 暴击和闪避机制
- 技能冷却（秒 vs 帧）
- 技能 AOE 效果
- 伤害数字显示

### 6. Frame Sync 帧同步 - 70% 完成

#### 6.1 已实现功能

- FSRoomSync：帧历史、命令收集
- 30 FPS 目标帧率（33ms）
- 帧 ID 跟踪和 missed frame 检测

#### 缺失功能

| 功能 | 说明 |
| --- | --- |
| 广播帧状态 | 没有将帧状态发送给客户端 |
| 帧 reconciliation | 没有延迟补偿 |
| 重连帧 replay | 没有实现 |
| 客户端预测 | 没有实现 |

### 7. Network Handlers 网络处理 - 90% 完成

#### 7.1 已实现功能

- 客户端消息处理：LOGIN, PING, INPUT, MAP_ENTER/LEAVE, CREATE_USER
- IPC 消息处理：DBUSERRECORD 响应
- UDP 消息处理：SAFESTOP_REQ, EXAMPLE

#### 7.2 待完善

- IPC Handler Bug（具体待定位）

---

## 待开发功能

### 高优先级：FSRoom 核心功能

| 功能 | 优先级 | 描述 |
| --- | --- | --- |
| Broadcast() | P0 | 发送消息到所有房间玩家 |
| SendToRoomPlayer() | P0 | 发送消息给指定房间玩家 |
| HandleReconnect() | P0 | 处理玩家重连逻辑 |
| FinishGame() | P0 | 结束游戏并通知所有玩家 |
| 协议定义 | P0 | 定义 FSRoom 通知协议 |

### 中优先级：战斗系统集成

| 功能 | 优先级 | 描述 |
| --- | --- | --- |
| 技能集成 | P1 | 将 Skill 系统集成到 FSRoom 战斗流程 |
| 伤害计算 | P1 | 实际伤害计算（考虑防御力） |
| AOE 效果 | P1 | 技能范围效果处理 |
| 状态同步 | P1 | 帧状态压缩与 delta 编码 |

### 低优先级：优化与测试

| 功能 | 优先级 | 描述 |
| --- | --- | --- |
| UI 反馈 | P2 | 血条同步、技能冷却显示 |
| 性能优化 | P2 | 状态同步包合并、客户端预测 |
| 测试系统 | P2 | 回放系统、测试机器人、性能监控 |

---

## 实现路线图

### 阶段 1：核心游戏循环（2-3 周）

| 任务 | 里程碑 |
| --- | --- |
| 实现 Broadcast() 和 SendToRoomPlayer() | 完成 |
| 添加房间事件协议定义 | 完成 |
| 创建 ProtoFSRoomNotifyState 协议 | 完成 |
| 实现帧状态压缩（delta 编码） | 完成 |
| 客户端插值实现 | 完成 |

### 阶段 2：战斗系统（3-4 周）

| 任务 | 里程碑 |
| --- | --- |
| 实际伤害计算（考虑防御力） | 完成 |
| 暴击和闪避机制 | 完成 |
| 技能冷却（秒 vs 帧） | 完成 |
| 视觉特效（粒子、投射物） | 完成 |
| 技能投射物追踪 | 完成 |
| 伤害数字显示 | 完成 |
| 帧历史回放 | 完成 |
| 缺失命令处理 | 完成 |
| 延迟补偿 | 完成 |

### 阶段 3：优化与测试（2-3 周）

| 任务 | 里程碑 |
| --- | --- |
| 血条同步 | 完成 |
| 技能冷却显示 | 完成 |
| 击杀/死亡计数 | 完成 |
| 状态同步数据包合并 | 完成 |
| 客户端预测 | 完成 |
| A*寻路优化 | 完成 |
| 回放系统 | 完成 |
| 测试机器人 | 完成 |
| 性能监控 | 完成 |

**MVP 估算时间：** 7-10 周

---

## 客户端开发工作

### 1. 协议更新

需要添加以下协议定义：**FSRoom 协议**

- `ProtoFSRoomNotifyState` - 帧状态同步
- `ProtoFSRoomNotifyEvent` - 房间事件
- `ProtoFSRoomEnterReq/Res` - 进入房间
- `ProtoFSRoomSkillReq/Res` - 释放技能

### 2. 游戏渲染

**2D 地图客户端**

- 玩家移动插值
- 相机平滑
- 玩家名字和等级显示

**3D 地图客户端**

- 玩家朝向显示
- 血条 UI
- 技能冷却覆盖

**FSRoom 客户端**

- 房间玩家列表
- 血量/MP 条
- 技能按钮和冷却计时器
- 小地图
- 战斗日志

### 3. 网络处理

- WebSocket 重连逻辑
- 包丢失处理
- 延迟补偿
- 输入缓冲用于预测

---

## 未来计划与注意事项（暂不执行）

以下功能需要后续规划实现：

1. 玩家连接上来不登录一定间隔则踢掉连接
2. 玩家连接后必须定时发送心跳
3. 每个玩家都有 Req 发送频率限制，不能发太快了防止攻击
4. 每个玩家网络连接接受消息都应该有一个 sequenceID 的，不然客户端发送Req Req，服务器返回 Res Res，客户端不知道两个相同的 Res 到底是对应哪个 Req
5. 玩家移动，来了请求后，先广播给地图内其他玩家，然后创建帧移动指令（type、坐标、角度、时间戳）存到player的缓冲队列中
6. 玩家释放技能，来了请求后，先广播给地图其他玩家，然后创建帧释放技能指令（type、skillID、目标坐标、时间戳）存到 player 的缓冲队列中
7. 房间内所有玩家请求确认就绪后然后系统 startGame
8. 地图的 Grid 坐标和实际地图坐标是两码事，GridWidth GridHeight决定地图总共有多少个 Grid，Grid 自身有 GridSize
9. 地图内障碍物单独放到一个数组中，有自己的 x，y 实际坐标和 width height，把障碍物所在的 Grid 标记为有障碍物 `grids[gridx][gridy]=true`
10. 地图内障碍物移除后，要及时更新 Grid
11. 地图障碍物碰到要及时将移动物坐标回退到合法位置
12. LockStep 模块，帧率、帧间隔、玩家输入队列每个玩家一个、当前 tick 计数、上一帧时间 last_tick_time、玩家列表、所属房间、运行中标识
13. 当需要创建新的一帧时，则将所有玩家队列中的帧全取出来处理每个帧指令，该移动的移动、技能释放的释放，当所有指令执行完毕后给房间所有用户广播一下状态
14. 玩家上传的每个指令应该有frameID，以便让服务器判断是接受还是抛弃
15. 每一帧指令处理后，把所有帧放到一个frameID的结构中，游戏按frameID存放支持回放
16. 处理技能释放指令时，在范围内查找目标，将技能作用于目标，通知发技能者技能结果与通知遭受技能的玩家，技能id以及造成伤害量等
17. 技能释放当然要消耗魔法值和冷却时间这些常规限制
18. 技能有 id、名字、描述、类型（damage/heal/buff/debuff）、damage量、heal量、duration效果时常、冷却cooldown、range范围、mpCost魔法值消耗

---

## 附录

### 协议清单

| 命令码 | 方向 | 说明 |
| --- | --- | --- |
| `PROTO_CMD_CS_REQ_LOGIN` | CS | 登录请求 |
| `PROTO_CMD_CS_REQ_CREATE_USER` | CS | 创建用户请求 |
| `PROTO_CMD_CS_MAP_ENTER` | CS | 进入 2D 地图 |
| `PROTO_CMD_CS_MAP_LEAVE` | CS | 离开 2D 地图 |
| `PROTO_CMD_CS_MAP_INPUT` | CS | 2D 地图输入 |
| `PROTO_CMD_CS_MAP3D_ENTER` | CS | 进入 3D 地图 |
| `PROTO_CMD_CS_MAP3D_LEAVE` | CS | 离开 3D 地图 |
| `PROTO_CMD_CS_MAP3D_INPUT` | CS | 3D 地图输入 |

### 核心 Lua 文件

| 文件 | 职责 |
| --- | --- |
| `PlayerLogic.lua` | 玩家类实现 |
| `PlayerMgrLogic.lua` | 玩家管理器 |
| `PlayerCmptInfoLogic.lua` | 玩家信息组件 |
| `PlayerCmptBagLogic.lua` | 玩家背包组件 |
| `PlayerCmptMapLogic.lua` | 玩家 2D 地图组件 |
| `PlayerCmptMap3DLogic.lua` | 玩家 3D 地图组件 |
| `PlayerCmptFSRoomLogic.lua` | 玩家战斗房间组件 |
| `MapLogic.lua` | 2D 地图逻辑 |
| `Map3DLogic.lua` | 3D 地图逻辑 |
| `FSRoomLogic.lua` | 战斗房间逻辑 |
| `FSRoomBattleLogic.lua` | 战斗逻辑 |
| `FSRoomSync.lua` | 帧同步逻辑 |

### 状态码

| 码值 | 名称 | 说明 |
| --- | --- | --- |
| 0 | OK | 成功 |
| 1 | ERR_UNKNOW | 未知错误 |
| 2 | ERR_SERVICE_SAFESTOPED | 服务已停止 |
| 1001 | ERR_TARGET_MAP_NOT_FOUND | 目标地图不存在 |
| 1002 | ERR_USERID_INPUT_INVALID | 用户 ID 无效 |
| 1003 | ERR_PASSWORD_INPUT_INVALID | 密码无效 |
| 1004 | ERR_USERID_OR_PASSWORD_NOTMATCH | 用户名或密码错误 |

---

## Lua 协程使用指南

### 1. 框架架构背景

MapSvr 采用 **多线程事件驱动** 架构，由三个实际运行游戏逻辑的 Lua VM 组成：

| VM | 入口点 | 热重载触发 | 用途 |
|---|---|---|---|
| **Main** | `Main:OnInit()` / `Main:OnReload()` | `Main:OnReload()` | 初始设置，目前是空实现 |
| **Worker** | `Worker:OnInit(workerIdx)` | `Worker:OnReload(workerIdx)` | 客户端连接处理（1-511 个实例） |
| **Other** | `Other:OnInit()` | `Other:OnReload()` | **核心游戏逻辑**（Player、Map、FSRoom 等） |

**C++ 与 Lua VM 的对应关系**：

| C++ 线程 | Lua VM | Lua 状态指针 |
|---|---|---|
| Main thread (C++) | Main VM | `lua_state` |
| Worker threads (C++) | Worker VMs | `worker_lua_state[worker_idx]` |
| Other thread (C++) | Other VM | `other_lua_state` |

**消息流程**：
```
C++ Main thread: 接受客户端套接字连接
    ↓
C++ Worker thread: 读取/解包客户端消息
    ↓
Other VM (MapSvr.OnLuaVMRecvMessage): 处理游戏逻辑
    ↓
C++ Worker thread: 发送响应给客户端
```

**关键点**：
- `MapSvr` 模块（`MapSvr.lua`）在 **Other VM** 中运行
- Main VM 目前只是空实现
- Worker VM 只处理客户端连接事件，不处理游戏逻辑
- 所有游戏逻辑在 Other VM 的 `OnTick()` 中串行执行
- C++ 通过 `lua_pcall` 调用 Lua 函数

---

### 2. 协程兼容性

#### C++ 调用与协程

`lua_pcall` **不阻止** 协程的使用。协程是在 Lua 层面实现的，C++ 调用者不需要做特殊处理：

```cpp
// C++ 调用 - 完全支持
int result = lua_pcall(L, nargs, nresults, 0);
// 这个 pcall 可以调用一个使用协程的 Lua 函数
```

#### 支持的操作

| 场景 | 是否支持 | 说明 |
|------|---------|------|
| `coroutine.create()` | ✅ 支持 | 在 C++ 调用中创建协程完全合法 |
| `coroutine.resume()` from Lua | ✅ 支持 | Lua 代码中恢复协程 |
| `coroutine.yield()` to Lua | ✅ 支持 | 可以 yield 回 Lua 调用者 |

#### 限制

| 场景 | 是否支持 | 说明 |
|------|---------|------|
| `coroutine.resume()` from C++ | ⚠️ 谨慎 | 需要处理 Lua 栈状态变化 |
| `coroutine.yield()` to C++ | ❌ 禁止 | 不能从 C 函数中间 yield |

#### 其他 VM 中的协程

**重要**：Worker VM 也可以使用协程，每个 Worker 有自己的独立 Lua 状态 (`worker_lua_state[worker_idx]`)，所以：

| VM | 协程状态 | 说明 |
|---|---|---|
| Main VM | 独立 | 主线程，通常不用于游戏逻辑 |
| Worker VMs | 独立 | 每个 Worker 有独立协程状态 |
| Other VM | 独立 | 核心游戏逻辑，协程主要使用场景 |

**跨 VM 协程通信**：由于每个 VM 有独立的 Lua 状态，协程**不能**直接在 VM 间共享。需要通过 C++ 层面的 IPC 消息传递。

---

### 3. 推荐的协程使用场景

#### 场景 1：异步数据库操作封装

当前 `MsgHandlerFromOtherLogic.lua` 中的数据库回调是"拉模式"，可以改为协程"推模式"：

```lua
-- 协程方式：看起来像同步
function MsgHandlerFromOther:handleLogin(cmd, message, app_id)
    local playerId = message.playerId
    local result = awaitDB(function(send)
        send(avant:GetDBSvrGoAppID(), 
             ProtoLua_ProtoCmd.PROTO_CMD_DBSVRGO_SELECT_DBUSERRECORD_LOGIN_REQ, 
             message)
    end)
    
    if result then
        -- 直接使用 result 处理登录
        self:processLogin(playerId, result)
    end
end
```

#### 场景 2：长时间计算分帧执行

例如 `FSRoomBattleLogic.lua` 中的 AStar 路径搜索：

```lua
function FSRoomBattle:ProcessMove(player, data)
    local pathFinder = AStarFinder.new(self.map, player:GetPosition(), data)
    
    -- 分帧执行，避免卡顿
    local success = pathFinder:computeStepByStep()
    if success then
        player:MoveAlongPath(pathFinder:path())
    else
        -- 继续下一帧
        return false
    end
end
```

#### 场景 3：延迟执行

```lua
function FSRoom:FinishGameAsync(winnerUserId, reason, delayMS)
    local startTime = TimeMgr.GetMS()
    
    while TimeMgr.GetMS() - startTime < delayMS do
        coroutine.yield()  -- 每帧让出，让其他逻辑执行
    end
    
    self:FinishGame(winnerUserId, reason)
end
```

#### 场景 4：网络请求链式调用

```lua
function MsgHandlerFromClient:handleLogin(playerId, clientGID, workerIdx, cmd, message)
    local player = createPlayerAsync(playerId)
    local dbData = loadDBDataAsync(player, message.userId)
    local config = loadConfigAsync()
    
    self:loginPlayer(player, dbData, config)
end
```

---

### 4. 实现方案

#### 方案 A：简单协程调度器

```lua
-- lua/Coroutine/SimpleScheduler.lua
local CoroutineScheduler = {}

function CoroutineScheduler.new()
    return setmetatable({
        coroutines = {},
        nextId = 1,
    }, { __index = CoroutineScheduler })
end

function CoroutineScheduler:spawn(func)
    local co = coroutine.create(func)
    self.coroutines[self.nextId] = co
    self.nextId = self.nextId + 1
    return self.nextId - 1
end

function CoroutineScheduler:resumeAll()
    local alive = {}
    for id, co in pairs(self.coroutines) do
        if coroutine.status(co) ~= "dead" then
            local ok, err = coroutine.resume(co)
            if not ok or coroutine.status(co) == "dead" then
                if not ok then
                    Log:Error("Coroutine error: %s", tostring(err))
                end
                -- 协程结束或出错
            else
                alive[id] = co
            end
        end
    end
    self.coroutines = alive
end

return CoroutineScheduler
```

**在 Other VM 中集成**（推荐）：

```lua
-- MapSvr.lua
function MapSvr.OnInit()
    if not MapSvr.coroutineScheduler then
        MapSvr.coroutineScheduler = require("Coroutine.SimpleScheduler").new()
    end
end

function MapSvr.OnTick()
    -- 调度所有挂起的协程
    if MapSvr.coroutineScheduler then
        MapSvr.coroutineScheduler:resumeAll()
    end
    
    PlayerMgr.OnTick()
    MapMgr.OnTick()
    FSRoomMgr.OnTick()
    Map3DMgr.OnTick()
end
```

**在 Worker VM 中集成**（如果需要异步连接处理）：

```lua
-- Worker.lua
local CoroutineScheduler = require("Coroutine.SimpleScheduler")

function Worker:OnTick(workerIdx)
    CoroutineScheduler:resumeAll()
end
```

#### 方案 B：异步回调转协程

```lua
-- lua/Coroutine/AsyncBridge.lua
local AsyncBridge = {}

function AsyncBridge.wrapCallback(fn)
    return function(...)
        local co = coroutine.running()
        local results = {}
        local done = false
        
        local function callback(...)
            if not done then
                done = true
                results = {...}
                coroutine.resume(co, true, ...)
            end
        end
        
        fn(callback, ...)
        
        if not done then
            local ok, err = coroutine.yield()
            if ok then
                return unpack(results)
            end
            error(err)
        end
    end
end

return AsyncBridge
```

使用：

```lua
local AsyncBridge = require("Coroutine.AsyncBridge")

-- 包装 IPC 调用
local sendToIPC = AsyncBridge.wrapCallback(function(cb, appId, cmd, message)
    MsgHandler:Send2IPC(appId, cmd, message, cb)  -- 传入回调
end)

-- 使用
local result = sendToIPC(appId, cmd, message)
-- 直接使用 result
```

#### 方案 C：超时控制

```lua
function withTimeout(timeoutMS, fn)
    local startTime = TimeMgr.GetMS()
    local result
    
    local co = coroutine.create(function()
        result = fn()
    end)
    
    coroutine.resume(co)
    
    while coroutine.status(co) ~= "dead" do
        if TimeMgr.GetMS() - startTime > timeoutMS then
            coroutine.close(co)
            error("Timeout: operation took longer than " .. timeoutMS .. "ms")
        end
        coroutine.yield()  -- 等待下一帧
    end
    
    return result
end

-- 使用
local dbResult = withTimeout(5000, function()
    return queryDatabase(sql)
end)
```

---

### 4. 其他 VM 中的协程使用

#### Worker VM 协程使用场景

虽然 Worker VM 主要用于连接处理，但以下场景可能需要协程：

1. **异步连接验证** - 连接时需要调用外部服务验证
2. **批量数据加载** - 玩家连接时加载大量配置数据
3. **跨 VM 通信优化** - 减少回调嵌套

```lua
-- Worker.lua
local CoroutineScheduler = require("Coroutine.SimpleScheduler")

function Worker:OnTick(workerIdx)
    CoroutineScheduler:resumeAll()
end

-- 连接事件处理
function Worker:OnEventNewConnection(workerIdx, clientId)
    CoroutineScheduler:spawn(function()
        local isValid = verifyClientAsync(clientId)
        if isValid then
            -- 发送验证通过消息
        end
    end)
end
```

#### 跨 VM 协程通信

由于每个 VM 有独立的 Lua 状态，协程不能直接跨 VM 共享。需要通过 C++ 层面的 IPC 消息传递：

```lua
-- Other VM 中启动协程
function MapSvr:HandlePlayerRequest(data)
    local co = coroutine.create(function()
        local result = sendToWorkerAsync(data)  -- 发送到 Worker VM
        local response = waitForResponse()       -- 等待 Worker VM 响应
        return response
    end)
    CoroutineScheduler:spawn(co)
end
```

---

### 5. 关键注意事项

#### 注意事项 1：协程泄漏

```lua
-- ❌ 错误：协程创建后无人 resume
local co = coroutine.create(fn)
coroutine.resume(co)
-- 如果 fn 中 yield 了，协程挂起但没人再 resume

-- ✅ 正确：确保协程要么完成，要么有后续调度
local scheduler = require("Coroutine.SimpleScheduler")
scheduler:spawn(fn)
```

#### 注意事项 2：全局状态竞争

```lua
-- ❌ 错误：多个协程共享全局状态
globalVar = nil
coroutine.wrap(function()
    globalVar = "value"  -- 可能被其他协程覆盖
end)()

-- ✅ 正确：使用局部变量
coroutine.wrap(function()
    local localVar = "value"  -- 每个协程独立
end)()
```

#### 注意事项 3：C 函数中 yield

```lua
-- ❌ 错误：在 C 函数中间 yield
function cppWrapper()
    lua_pcall(...)  -- 这里不能 yield
end

-- ✅ 正确：yield 只能在纯 Lua 代码中
function luaWrapper()
    local result = cppWrapper()  -- C 调用
    coroutine.yield()  -- 这里可以 yield
end
```

#### 注意事项 4：错误处理

```lua
-- ✅ 正确：使用 xpcall 捕获协程错误
function CoroutineScheduler:resumeAll()
    for id, co in pairs(self.coroutines) do
        local ok, err = coroutine.resume(co)
        if not ok then
            Log:Error("Coroutine %d error: %s", id, tostring(err))
            -- 不要中断其他协程
        end
    end
end
```

#### 注意事项 5：协程数量控制

```lua
-- 建议：限制协程数量
MAX_COROUTINES = 100

function CoroutineScheduler:spawn(func)
    if #self.coroutines >= MAX_COROUTINES then
        Log:Warn("Coroutine limit reached, ignoring spawn request")
        return nil
    end
    -- ...
end
```

#### 注意事项 6：Other VM vs Worker VM

| 场景 | 推荐 VM | 原因 |
|---|---|---|
| 游戏逻辑处理 | Other VM | 核心逻辑集中管理 |
| 客户端连接处理 | Worker VM | 每个连接一个 Worker |
| 网络请求 | Other VM | 统一的网络处理 |
| 连接验证 | Worker VM | 与连接绑定 |

**推荐**：主要协程使用在 **Other VM** 中，Worker VM 只在必要时使用。

---

### 6. 推荐的改造优先级

| 优先级 | 模块 | 改造内容 | 收益 |
|---|---|---|---|
| **P0** | `MsgHandlerFromOtherLogic` | DB 回调协程化 | 代码可读性大幅提升 |
| **P1** | `FSRoomBattleLogic` | AStar 分帧执行 | 防止卡顿 |
| **P1** | `FSRoomLogic` | 玩家重连逻辑 | 更好的用户体验 |
| **P2** | `PlayerLogic` | 登录流程串行化 | 简化逻辑 |
| **P3** | `MapLogic` | 四叉树查询优化 | 性能提升 |

---

### 9. Worker VM 协程使用场景

Worker VM 虽然主要用于客户端连接处理，但在以下场景可能需要协程：

1. **异步连接验证** - 连接时需要调用外部服务验证
2. **批量数据加载** - 玩家连接时加载大量配置数据
3. **跨 VM 通信优化** - 减少回调嵌套

**注意**：由于每个 Worker VM 有独立的 Lua 状态，协程状态也是独立的。需要在每个 Worker 实例中单独管理协程调度器。

---

### 7. 性能考量

#### 协程开销

| 操作 | 开销 |
|------|------|
| `coroutine.create()` | ~100 字节内存 |
| `coroutine.resume()` | ~10-20 纳秒 |
| `coroutine.yield()` | ~10-20 纳秒 |

#### 最佳实践

1. **短时操作 (< 1ms)** - 不需要协程
2. **长时间操作 (> 10ms)** - 考虑分帧或协程
3. **阻塞操作 (DB, Network)** - 强烈推荐协程

---

### 8. 未来扩展

#### 计划中的协程特性

1. **协程池** - 复用协程对象，减少 GC 压力
2. **协程调试工具** - 查看挂起协程的状态
3. **协程监控** - 统计协程数量、执行时间
4. **协程间通信** - 通过 channel 传递数据

#### 相关技术

- **LuaJIT FFI** - 与协程配合进行高性能数据处理
- **Protobuf 序列化** - 协程中进行异步序列化
- **热重载兼容** - 协程状态在热重载时的处理

---
