PlayerCmptFSRoom = PlayerCmptFSRoom or {}
local PlayerCmptBase = require("PlayerCmptBaseLogic")

setmetatable(PlayerCmptFSRoom, {
    __index = PlayerCmptBase
})

PlayerCmptFSRoom.__index = PlayerCmptFSRoom

return PlayerCmptFSRoom
