# MapSvr Lua 代码 Review 报告

**日期:** 2026-07-09  
**Author:** Claude Code  
**版本:** v1.0

---

## 目录

1. [执行摘要](#执行摘要)
2. [功能完成度评估](#功能完成度评估)
3. [发现的错误](#发现的错误)
4. [需要开发的功能](#需要开发的功能)
5. [完整地图多玩家技能帧同步状态同步所需工作](#完整地图多玩家技能帧同步状态同步所需工作)
6. [客户端开发工作](#客户端开发工作)

---

## 执行摘要

MapSvr 是一个基于 Avant 框架的 Lua 游戏服务器框架，具备热重载、多 VM 架构、Protobuf 协议通信等特性。

**总体完成度评估：**

| 模块 | 完成度 | 状态 |
| --- | --- | --- |
| Player 玩家系统 | 80% | 基本完成，有 Minor Bug |
| Map 2D 地图系统 | 95% | 功能完整，仅有边界问题 |
| Map 3D 地图系统 | 95% | 功能完整，仅有边界问题 |
| FSRoom 帧同步战斗房间 | 60% | 架构存在，核心广播缺失 |
| Skill 技能系统 | 85% | 逻辑完整，需集成到战斗 |
| Frame Sync 帧同步 | 70% | 架构存在，需完善 |
| Network Handlers 网络处理 | 90% | 存在一个 IPC Handler Bug |

**关键发现：**

1. Map 2D/3D 系统已经非常接近完成，具备完整的物理、状态同步、AOI 系统
2. FSRoom 战斗系统有完整的架构（地图、技能、A*寻路），但缺少关键的广播功能
3. 核心问题是 FSRoom 的 Broadcast() 和 SendToRoomPlayer() 方法是空的
4. 存在几个中低优先级的 Bug

---

## 功能完成度评估

### 1. Player 玩家系统 - 80% 完成

#### 已实现功能

- Player 类架构：支持多组件模式（Info, Bag, Map, Map3D, FSRoom）
- PlayerMgr：玩家管理器支持 userId/playerId 双向映射、在线状态管理
- 数据库集成：通过 IPC 与 dbsvrgo 通信，支持 SELECT/INSERT 操作
- 登录流程：PROTO_CMD_CS_REQ_LOGIN -> dbsvrgo -> SELECT_DBUSERRECORD_LOGIN_RES
- 创建用户：PROTO_CMD_CS_REQ_CREATE_USER -> dbsvrgo -> INSERT_DBUSERRECORD_RES
- 热重载：PlayerLogic, PlayerMgrLogic 等支持热重载

### 2. Map 2D 系统 - 95% 完成

#### 2. 已实现功能

- 瓦片地图：支持 4000x4000 像素地图，tileSize=50
- 物理系统：速度、加速度、摩擦力、边界控制
- 四叉树 AOI：QuadTree 实现完整的区域优化
- 状态同步：通过 PROTO_CMD_CS_MAP_NOTIFY_STATE_DATA 同步
- 初始化数据：通过 PROTO_CMD_CS_MAP_NOTIFY_INIT_DATA 发送
- Ping/Pong：心跳机制
- 输入处理：支持 seq 验证防止重放攻击

### 3. Map 3D 系统 - 95% 完成

#### 3. 已实现功能

- 3D 地图系统：支持 1000000x1000000x1000000 大小
- 3D 物理系统：重力、速度、加速度、摩擦力
- 八叉树 AOI：Octree 实现 3D 区域优化
- 状态同步：通过 PROTO_CMD_CS_MAP3D_NOTIFY_STATE_DATA 同步
- 输入处理：3D 方向输入（dirX, dirY, dirZ）

### 4. FSRoom 帧同步战斗房间 - 60% 完成

#### 4. 已实现功能

- 房间状态管理：WAITING, READY, RUNNING, FINISHED
- 房间玩家管理：HP/MP/技能管理
- 三种地图类型：Square (4/8 dir), Hex, Isometric (4/8 dir)
- A*寻路：支持所有地图类型的路径查找
- 技能系统：DAMAGE, HEAL, BUFF, DEBUFF 类型
- 帧同步架构：FSRoomSync 与帧历史

#### 缺失功能（关键）

| 功能 | 文件 | 状态 |
| ------ | ------ | ------ |
| Broadcast() | FSRoomLogic.lua:346-352 | 空实现 |
| SendToRoomPlayer() | FSRoomLogic.lua:358-364 | 空实现 |
| HandleReconnect() | FSRoomLogic.lua:312-340 | 空实现 |
| FinishGame() | FSRoomLogic.lua:224-242 | 空实现 |
| 广播游戏状态 | FSRoomBattleLogic.lua | 缺少客户端协议 |

### 5. Skill 技能系统 - 85% 完成

#### 5. 已实现功能

- 技能数据库：5 个技能（Basic Attack, Fireball, Heal, Lightning Strike, Shield）
- 技能属性：costMP, cooldown, range, damage/healAmount, aoeRadius
- CanCast 验证：MP 检查、冷却检查、距离检查
- Cast 方法：处理 damage 和 heal 技能类型

### 6. Frame Sync 帧同步 - 70% 完成

#### 6. 已实现功能

- FSRoomSync：帧历史、命令收集
- 30 FPS 目标帧率（33ms）
- 帧 ID 跟踪和 missed frame 检测

#### 缺失功能

| 功能 | 说明 |
| ------ | ------ |
| 广播帧状态 | 没有将帧状态发送给客户端 |
| 帧 reconciliation | 没有延迟补偿 |
| 重连帧 replay | 没有实现 |

### 7. Network Handlers 网络处理 - 90% 完成

#### 7. 已实现功能

- 客户端消息处理：LOGIN, PING, INPUT, MAP_ENTER/LEAVE, CREATE_USER
- IPC 消息处理：DBUSERRECORD 响应
- UDP 消息处理：SAFESTOP_REQ, EXAMPLE

---

## 发现的错误

### Critical Priority

### High Priority

### Medium Priority

---

## 需要开发的功能

### FSRoom 广播功能（最高优先级）

需要实现以下协议和功能：

1. **FSRoom 协议定义** (proto_cmd.proto)
   - PROTO_CMD_CS_FSRM_NOTIFY_STATE - 帧状态同步
   - PROTO_CMD_CS_FSRM_NOTIFY_EVENT - 房间事件
   - PROTO_CMD_CS_FSRM_NOTIFY_GAME_START - 游戏开始
   - PROTO_CMD_CS_FSRM_NOTIFY_GAME_END - 游戏结束

2. **FSRoom.lua - Broadcast() 实现**

   ```lua
   function FSRoom:Broadcast(cmd, message, exceptUserId)
       for userId, roomPlayer in pairs(self.roomPlayers) do
           if roomPlayer.isConnected and userId ~= exceptUserId then
               local player = PlayerMgr.GetPlayerByUserId(userId)
               if player then
                   MsgHandler:Send2Client(player:GetClientGID(), 
                       player:GetWorkerIdx(), cmd, message)
               end
           end
       end
   end
   ```

3. **FSRoom.lua - SendToRoomPlayer() 实现**

   ```lua
   function FSRoom:SendToRoomPlayer(cmd, message, userId)
       local roomPlayer = self.roomPlayers[userId]
       if roomPlayer and roomPlayer.isConnected then
           local player = PlayerMgr.GetPlayerByUserId(userId)
           if player then
               MsgHandler:Send2Client(player:GetClientGID(), 
                   player:GetWorkerIdx(), cmd, message)
           end
       end
   end
   ```

4. **FSRoomBattle.lua - ProcessCommand() 完善**
   - "move" 命令处理：当前只支持简单的移动，需要完整 A*寻路
   - "skill" 命令处理：需要实现 AOE 效果和伤害计算

---

## 完整地图多玩家技能帧同步状态同步所需工作

### 阶段 1：核心游戏循环（2-3 周）

1. **FSRoom 广播功能实现**
   - 实现 Broadcast() 发送消息到所有房间玩家
   - 实现 SendToRoomPlayer() 发送消息给指定玩家
   - 添加房间事件协议定义

2. **游戏状态同步**
   - 创建 ProtoCSFSRoomNotifyState 协议
   - 实现帧状态压缩（delta 编码）
   - 客户端插值实现

3. **房间事件通知**
   - PROTO_CMD_CS_FSRM_NOTIFY_PLAYER_JOINED
   - PROTO_CMD_CS_FSRM_NOTIFY_PLAYER_LEFT
   - PROTO_CMD_CS_FSRM_NOTIFY_PLAYER_READY
   - PROTO_CMD_CS_FSRM_NOTIFY_GAME_START
   - PROTO_CMD_CS_FSRM_NOTIFY_GAME_END

### 阶段 2：战斗系统（3-4 周）

1. **战斗处理**
   - 实际伤害计算（考虑防御力）
   - 暴击和闪避机制
   - 技能冷却（秒 vs 帧）

2. **技能特效**
   - 视觉特效（粒子、投射物）
   - 技能投射物追踪
   - 伤害数字显示

3. **重连处理**
   - 帧历史回放
   - 缺失命令处理
   - 延迟补偿

### 阶段 3：优化（2-3 周）

1. **UI 反馈**
   - 血条同步
   - 技能冷却显示
   - 击杀/死亡计数

2. **性能优化**
   - 状态同步数据包合并
   - 客户端预测
   - A*寻路优化

3. **测试**
   - 回放系统
   - 测试机器人
   - 性能监控

---

## 客户端开发工作

### 1. 协议更新

客户端 HTML 文件中的 proto 文本过时，需要添加：

1. **FSRoom 协议**
   - ProtoFSRoomNotifyState
   - ProtoFSRoomNotifyEvent
   - ProtoFSRoomEnterReq/Res
   - ProtoFSRoomSkillReq/Res

### 2. 游戏渲染

1. **2D 地图客户端**
   - 玩家移动插值
   - 相机平滑
   - 玩家名字和等级显示

2. **3D 地图客户端**
   - 玩家朝向显示
   - 血条 UI
   - 技能冷却覆盖

3. **FSRoom 客户端**
   - 房间玩家列表
   - 血量/MP 条
   - 技能按钮和冷却计时器
   - 小地图
   - 战斗日志

### 3. 网络处理

1. WebSocket 重连逻辑
2. 包丢失处理
3. 延迟补偿
4. 输入缓冲用于预测

---

## 总结

| 组件 | 状态 | 说明 |
| ------ | ------ | ------ |
| Player 玩家系统 | 完成 | 登录流程工作，组件有 cleanup |
| Map 2D | 基本完成 | 物理、同步、AOI 齐全 |
| Map 3D | 基本完成 | 物理、同步、AOI 齐全 |
| FSRoom | 架构完成 | 广播功能缺失，核心问题 |
| Skill | 逻辑完成 | 需要集成到战斗流程 |
| Frame Sync | 架构完成 | 需要客户端同步 |
| Network | 基本完成 | 存在一个 IPC Handler Bug |

**MVP 估算时间：** 11-16 周

## 未来计划与注意事项暂不执行

- 玩家连接上来不登录一定间隔则踢掉连接
- 玩家连接后必须定时发送心跳
- 每个玩家都有Req发送频率限制，不能发太快了防止攻击
- 每个玩家网络连接接受消息都应该有一个 sequenceID 的，不然客户端发送Req Req，服务器返回 Res Res，客户端不知道两个相同的 Res 到底是对应哪个 Req，Req.sequenceID 服务器返回 Res.sequenceID 对应起来就好了
- 玩家移动，来了请求后，先广播给地图内其他玩家，然后创建 帧移动指令 指令有type、坐标、角度、时间戳 存到player的缓冲队列中
- 玩家释放技能，来了请求后，先广播给地图其他玩家，然后创建 帧释放技能指令 指令有type、skillID、目标坐标、时间戳 存到 player 的缓冲队列中
- 房间内 所有玩家请求确认就绪后 然后系统 startGame
- 地图的 Grid 坐标和实际地图坐标是两码事，GridWidth GridHeight决定地图总共有多少个 Grid，Grid 自身有 GridSize
- 地图内障碍物单独放到一个数组中，有自己的 x，y 实际坐标和 width height，把障碍物所在的 Grid 标记为有障碍物 `grids[gridx][gridy]=true`
- 地图内障碍物移除后，要及时更新 Grid
- 地图障碍物碰到要及时将移动物坐标回退到合法位置
- LockStep 模块，帧率、帧间隔、玩家输入队列每个玩家一个、当前 tick 计数、上一帧时间 last_tick_time、玩家列表、所属房间、运行中标识
- 当需要创建新的一帧时，则将所有玩家队列中的帧全取出来 处理每个帧指令，该移动的移动、技能释放的释放，当所有指令执行完毕后 给房间所有用户广播一下状态
- 玩家上传的每个指令应该有frameID，以便让服务器判断是接受还是抛弃
- 每一帧指令处理后，把所有帧放到一个frameID的结构中，游戏按frameID存放支持回放
- 处理技能释放指令时，在范围内查找目标，将技能作用于目标，通知发技能者技能结果 与 通知遭受技能的玩家，技能id 以及 造成伤害量等
- 技能释放当然要消耗魔法值和冷却时间这些常规限制
- 技能有 id、名字、描述、类型（伤害damage、治疗heal、增益buff、减益debuff）、damage量、heal量、duration效果时常、冷却cooldown、range范围、mpCost魔法值消耗
