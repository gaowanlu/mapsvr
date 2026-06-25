---@class Validator
local Validator = require("ValidatorData");

--- 判断字符串是否为空
---@param str string
---@return boolean
function Validator.IsEmptyString(str)
    return str == nil or str == "";
end

--- 验证是否为正整数
---@param value integer
---@return boolean
function Validator.IsPositiveInteger(value)
    return value >= 0 and math.floor(value) == value;
end

--- 验证是否为正数
---@param value number
---@return boolean
function Validator.IsPositiveNumber(value)
    return value > 0;
end

--- 验证是否在范围内
---@param value number
---@param min number
---@param max number
---@return boolean
function Validator.InRangeForNumber(value, min, max)
    return value >= min and value <= max;
end

return Validator;
