PlayerCmptMap3D = PlayerCmptMap3D or {}
local PlayerCmptBase = require("PlayerCmptBaseLogic")

setmetatable(PlayerCmptMap3D, {
    __index = PlayerCmptBase
})

PlayerCmptMap3D.__index = PlayerCmptMap3D

return PlayerCmptMap3D
