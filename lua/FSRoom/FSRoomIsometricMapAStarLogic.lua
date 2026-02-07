---@class FSRoomIsometricMapAStar
FSRoomIsometricMapAStar = require("FSRoomIsometricMapAStarData");

---@return FSRoomIsometricMapAStar
function FSRoomIsometricMapAStar.new()
    ---@type FSRoomIsometricMapAStar
    local self = setmetatable({}, FSRoomIsometricMapAStar);

    return self;
end

return FSRoomIsometricMapAStar;
