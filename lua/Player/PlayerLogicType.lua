---@class PlayerComponentsType
---@field info   PlayerCmptInfo
---@field bag    PlayerCmptBag
---@field map    PlayerCmptMap
---@field map3d  PlayerCmptMap3D
---@field FSRoom PlayerCmptFSRoom

---@class PlayerCacheDataType
---@field id        string  playerId
---@field clientGID string  clientGID
---@field workerIdx integer workerIdx
---@field userId    string  userID

---@class PlayerType
---@field PlayerCacheData PlayerCacheDataType
---@field components      PlayerComponentsType
---@field DbUserRecord    ProtoLua_DbUserRecord | nil 数据库玩家数据
