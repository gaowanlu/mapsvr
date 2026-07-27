---@class Map3DMgr: Map3DMgrType
local Map3DMgr = require("Map3DMgrData")
local Map3D = require("Map3DLogic")
local Log = require("Log")

-- 热重载lua会被重新执行
Map3DMgr.maps = Map3DMgr.maps or {}

---@return Map3D
function Map3DMgr.CreateMap(mapId)
    if Map3DMgr.maps[mapId] ~= nil then
        Log:Error("Already exists Map3D mapId %d", mapId)
        return Map3DMgr.maps[mapId]
    end

    Log:Error("Create new Map3D mapId[%d]", mapId)
    local newMap3D = Map3D.new(mapId)

    Map3DMgr.maps[mapId] = newMap3D

    return Map3DMgr.maps[mapId]
end

---@param mapId integer
---@return Map3D
function Map3DMgr.GetMap(mapId)
    return Map3DMgr.maps[mapId]
end

---@param mapId integer
function Map3DMgr.RemoveMap(mapId)
    Map3DMgr.maps[mapId] = nil
    Log:Error("RemoveMap from Map3DMgr mapId %d", mapId)
end

function Map3DMgr.OnTick()
    for mapId, mapItem in pairs(Map3DMgr.maps) do
        ---@type Map3D
        local mapObj = mapItem

        mapObj:OnTick()
    end
end

function Map3DMgr.OnStop()
    Log:Error("Map3DMgr OnStop")
    for mapId, mapObj in pairs(Map3DMgr.maps) do
        Map3DMgr.RemoveMap(mapId)
    end
end

function Map3DMgr.OnSafeStop()
    Log:Error("Map3DMgr.OnSafeStop()")
end

function Map3DMgr.OnReload()
    local ConfigTableMgr = require("ConfigTableMgrLogic")
    local map3DCount = ConfigTableMgr.Map3DConfig:GetMap3DIdCount()

    for i = 1, map3DCount, 1 do
        local map3DId = ConfigTableMgr.Map3DConfig:GetMap3DIdAt(i)

        -- 初始化一个3D地图
        Map3DMgr.CreateMap(map3DId)
    end
end

return Map3DMgr
