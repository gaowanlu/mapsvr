---@class FSRoomHexMapAStar
FSRoomHexMapAStar = require("FSRoomHexMapAStarData");

---@return FSRoomHexMapAStar
function FSRoomHexMapAStar.new()
    ---@type FSRoomHexMapAStar
    local self = setmetatable({}, FSRoomHexMapAStar);

    return self;
end

return FSRoomHexMapAStar;
