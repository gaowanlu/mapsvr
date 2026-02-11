---@class FSRoomMapType
---@field SQUARE integer 正方形瓦片正交视角
---@field SQUARE_4DIR integer 正方型瓦片4方向
---@field SQUARE_8DIR integer 正方形瓦片8方向
---@field HEX integer 六边形瓦片
---@field ISO integer 等距菱形瓦片
---@field ISO_4DIR integer 等距菱形瓦片4方向
---@field ISO_8DIR integer 等距菱形瓦片8方向

---@class FSRoomMapFactory
---@field MapTypes FSRoomMapType
local FSRoomMapFactory = require("FSRoomMapFactoryData");

local FSRoomSquareMap = require("FSRoomSquareMapLogic");
local FSRoomHexMap = require("FSRoomHexMapLogic");
local FSRoomIsometricMap = require("FSRoomIsometricMapLogic");

FSRoomMapFactory.MapTypes = {
    SQUARE      = 1,
    SQUARE_4DIR = 2,
    SQUARE_8DIR = 3,
    HEX         = 4,
    ISO         = 5,
    ISO_4DIR    = 6,
    ISO_8DIR    = 7
};

---@param mapType integer
---@param width integer
---@param height integer
---@return FSRoomSquareMap|FSRoomHexMap|FSRoomIsometricMap|nil,string
function FSRoomMapFactory.CreateMap(mapType, width, height)
    if mapType == FSRoomMapFactory.MapTypes.SQUARE or mapType == FSRoomMapFactory.MapTypes.SQUARE_4DIR then
        return FSRoomSquareMap.new(width, height, false), "";
    elseif mapType == FSRoomMapFactory.MapTypes.SQUARE_8DIR then
        return FSRoomSquareMap.new(width, height, true), "";
    elseif mapType == FSRoomMapFactory.MapTypes.HEX then
        return FSRoomHexMap.new(width, height), "";
    elseif mapType == FSRoomMapFactory.MapTypes.ISO or mapType == FSRoomMapFactory.MapTypes.ISO_8DIR then
        return FSRoomIsometricMap.new(width, height, true), "";
    elseif mapType == FSRoomMapFactory.MapTypes.ISO_4DIR then
        return FSRoomIsometricMap.new(width, height, false), "";
    end

    return nil, "未知地图类型";
end

---@class FSRoomMapTypeInfo
---@field name string
---@field description string
---@field neighbors integer
---@field movement string

---@param mapType integer
---@return FSRoomMapTypeInfo
function FSRoomMapFactory.GetMapTypeInfo(mapType)
    ---@type table<integer,FSRoomMapTypeInfo>
    local info = {
        [FSRoomMapFactory.MapTypes.SQUARE] = {
            name = "正方形瓦片",
            description = "正交视角",
            neighbors = 4,
            movement = "4方向 上下左右"
        },
        [FSRoomMapFactory.MapTypes.SQUARE_4DIR] = {
            name = "正方形瓦片",
            description = "正交视角",
            neighbors = 4,
            movement = "4方向 上下左右"
        },
        [FSRoomMapFactory.MapTypes.SQUARE_8DIR] = {
            name = "正方形瓦片",
            description = "正交视角 支持对角线移动",
            neighbors = 8,
            movement = "8方向 上下左右以及对角线"
        },
        [FSRoomMapFactory.MapTypes.HEX] = {
            name = "六边形瓦片",
            description = "使用立方体坐标系统",
            neighbors = 6,
            movement = "6方向"
        },
        [FSRoomMapFactory.MapTypes.ISO] = {
            name = "等距菱形瓦片",
            description = "2.5D视角",
            neighbors = 8,
            movement = "8方向 含对角线"
        },
        [FSRoomMapFactory.MapTypes.ISO_8DIR] = {
            name = "等距菱形瓦片",
            description = "2.5D视角",
            neighbors = 8,
            movement = "8方向 含对角线"
        },
        [FSRoomMapFactory.MapTypes.ISO_4DIR] = {
            name = "等距菱形瓦片",
            description = "2.5D视角",
            neighbors = 4,
            movement = "4方向 上下左右"
        }
    };

    return info[mapType] or { name = "未知", description = "未知地图类型", neighbors = 0, movement = "未知" };
end

if not ... then
    print("\n========== 可用的地图类型 ==========")
    for key, mapType in pairs(FSRoomMapFactory.MapTypes) do
        local info = FSRoomMapFactory.GetMapTypeInfo(mapType);
        print("\n[" .. key .. "] " .. mapType)
        print("  名称: " .. info.name)
        print("  描述: " .. info.description)
        print("  移动: " .. info.movement)
    end
    print("\n====================================\n")

    local squareMap4Dir, _ = FSRoomMapFactory.CreateMap(FSRoomMapFactory.MapTypes.SQUARE_4DIR, 20, 20);
    local squareMap8Dir, _ = FSRoomMapFactory.CreateMap(FSRoomMapFactory.MapTypes.SQUARE_8DIR, 20, 20);
    local hexMap, _ = FSRoomMapFactory.CreateMap(FSRoomMapFactory.MapTypes.HEX, 20, 20);
    local isometric4Dir, _ = FSRoomMapFactory.CreateMap(FSRoomMapFactory.MapTypes.ISO_4DIR, 20, 20);
    local isometric8Dir, _ = FSRoomMapFactory.CreateMap(FSRoomMapFactory.MapTypes.ISO_8DIR, 20, 20);

    if squareMap4Dir ~= nil then
        squareMap4Dir:Print();
    end
    if squareMap8Dir ~= nil then
        squareMap8Dir:Print();
    end
    if hexMap ~= nil then
        hexMap:Print();
    end
    if isometric4Dir ~= nil then
        isometric4Dir:Print();
    end
    if isometric8Dir ~= nil then
        isometric8Dir:Print();
    end
end

return FSRoomMapFactory;
