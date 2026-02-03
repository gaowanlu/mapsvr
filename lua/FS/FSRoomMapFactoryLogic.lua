---@class FSRoomMapType
---@field SQUARE integer 正方形瓦片正交视角
---@field SQUARE_4DIR integer 正方型瓦片4方向
---@field SQUARE_8DIR integer 正方形瓦片8方向
---@field HEX integer 六边形瓦片
---@field ISO integer 等距菱形瓦片
---@field ISO_4DIR integer 等距菱形瓦片4方向
---@field ISO_8DIR integer 等距菱形瓦片8方向

--- 地图基类
---@class FSRoomMapBase
---@field mapType integer FSRoomMapType对应类型

---@class FSRoomMapFactory
---@field MapTypes FSRoomMapType
FSRoomMapFactory = require("FSRoomMapFactoryData");

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
---@return FSRoomMapBase|nil,string
function FSRoomMapFactory.CreateMap(mapType, width, height)
    ---@type FSRoomMapBase
    local roomMapBase = {
        mapType = mapType
    };

    if mapType == FSRoomMapFactory.MapTypes.SQUARE or mapType == FSRoomMapFactory.MapTypes.SQUARE_4DIR then
        return roomMapBase, "";
    elseif mapType == FSRoomMapFactory.MapTypes.SQUARE_8DIR then
        return roomMapBase, "";
    elseif mapType == FSRoomMapFactory.MapTypes.HEX then
        return roomMapBase, "";
    elseif mapType == FSRoomMapFactory.MapTypes.ISO or mapType == FSRoomMapFactory.MapTypes.ISO_8DIR then
        return roomMapBase, "";
    elseif mapType == FSRoomMapFactory.MapTypes.ISO_4DIR then
        return roomMapBase, "";
    end

    return nil, "未知地图类型";
end

return FSRoomMapFactory;
