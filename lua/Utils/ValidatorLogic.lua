---@class Validator
local Validator = require("ValidatorData")

--- 判断字符串是否为空
---@param str string
---@return boolean
function Validator.IsEmptyString(str)
    return str == nil or str == ""
end

--- 验证是否为正整数
---@param value integer
---@return boolean
function Validator.IsPositiveInteger(value)
    return value >= 0 and math.floor(value) == value
end

--- 验证是否为正数
---@param value number
---@return boolean
function Validator.IsPositiveNumber(value)
    return value > 0
end

--- 验证是否在范围内
---@param value number
---@param min   number
---@param max   number
---@return boolean
function Validator.InRangeForNumber(value, min, max)
    return value >= min and value <= max
end

--- 验证用户名是否合法
---@param userId string
---@return integer
function Validator.UserIdValidator(userId)
    if userId == nil then
        return ProtoLua_ProtoErrCode.ERR_USERID_INPUT_INVALID
    end

    if #userId <= 0 or #userId > 64 then
        return ProtoLua_ProtoErrCode.ERR_USERID_INPUT_INVALID
    end

    return ProtoLua_ProtoErrCode.OK
end

--- 验证用户密码是否合法
---@param password string
---@return integer
function Validator.UserPasswordValidator(password)
    if password == nil then
        return ProtoLua_ProtoErrCode.ERR_PASSWORD_INPUT_INVALID
    end

    if #password <= 0 or #password > 64 then
        return ProtoLua_ProtoErrCode.ERR_PASSWORD_INPUT_INVALID
    end

    return ProtoLua_ProtoErrCode.OK
end

return Validator
