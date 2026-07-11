local PlayerCmptBase = require("PlayerCmptBaseLogic")
local Log = require("Log")

---@class PlayerCmptBagType:PlayerCmptBase

---@class PlayerCmptBag:PlayerCmptBagType
local PlayerCmptBag = require("PlayerCmptBagData")

---@param owner Player
---@return PlayerCmptBag
function PlayerCmptBag.new(owner)
    -- 本质是 setmetatable(PlayerCmptBase.new(owner), {__index=PlayerCmptBag})
    local self = setmetatable(PlayerCmptBase.new(owner), PlayerCmptBag)
    return self
end

---@return ProtoLua_DbPlayerBag
function PlayerCmptBag:GetBagData()
    return self:GetPlayer():GetDbUserRecord().base_info.bagData;
end

---@param itemID integer
---@return ProtoLua_DbPlayerBagItem|nil
function PlayerCmptBag:FindDbBagItemByItemID(itemID)
    local dbData = self:GetBagData()

    ---@type ProtoLua_DbPlayerBagItem|nil
    local dbPlayerBagItem = nil;

    for _, bagItem in ipairs(dbData.bagItemList) do
        if bagItem.itemID == itemID then
            dbPlayerBagItem = bagItem;
            break;
        end
    end

    return dbPlayerBagItem;
end

---@param itemID integer
---@param count integer
---@return boolean
function PlayerCmptBag:TestAddItemByItemID(itemID, count)
    if count <= 0 then
        return false;
    end
    local hasNumber = self:GetItemCountByItemID(itemID);

    if count > avant.INT32_MAX - hasNumber then
        return false;
    end

    return true;
end

---@param itemID integer
---@param count integer
---@return boolean
function PlayerCmptBag:AddItemByItemID(itemID, count)
    if not self:TestAddItemByItemID(itemID, count) then
        return false;
    end

    local dbData = self:GetBagData()

    ---@type ProtoLua_DbPlayerBagItem|nil
    local dbPlayerBagItem = self:FindDbBagItemByItemID(itemID);

    if dbPlayerBagItem == nil then
        dbData.bagItemList[#dbData.bagItemList + 1] = {
            itemID = itemID,
            number = 0
        };
        dbPlayerBagItem = dbData.bagItemList[#dbData.bagItemList]
    end

    if dbPlayerBagItem == nil then
        return false;
    end

    dbPlayerBagItem.number = dbPlayerBagItem.number + count;

    return true
end

---@param itemID integer
---@return number
function PlayerCmptBag:GetItemCountByItemID(itemID)
    local dbPlayerBagItem = self:FindDbBagItemByItemID(itemID);

    if dbPlayerBagItem == nil then
        return 0;
    end

    return dbPlayerBagItem.number;
end

---@param itemID integer
---@param count integer
---@return boolean
function PlayerCmptBag:TestSubItemByItemID(itemID, count)
    if count <= 0 then
        return false;
    end
    local hasNumber = self:GetItemCountByItemID(itemID);
    if hasNumber >= count then
        return true;
    end
    return false;
end

---@param itemID integer
---@param count integer
---@return boolean
function PlayerCmptBag:SubItemByItemID(itemID, count)
    local dbBagData = self:GetBagData();
    if count <= 0 then
        return false;
    end

    local dbPlayerBagItem = self:FindDbBagItemByItemID(itemID);
    if dbPlayerBagItem == nil then
        return false;
    end

    if dbPlayerBagItem.number < count then
        return false;
    end

    dbPlayerBagItem.number = dbPlayerBagItem.number - count;

    if dbPlayerBagItem.number == 0 then
        -- 删除这个item
        for i = #dbBagData.bagItemList, 1, -1 do
            if dbBagData.bagItemList[i].itemID == itemID then
                table.remove(dbBagData.bagItemList, i);
                dbPlayerBagItem = nil;
                break
            end
        end
    end

    return true;
end

function PlayerCmptBag:OnTick()
    -- 调试测试代码
    if self:TestAddItemByItemID(1, 100) then
        self:AddItemByItemID(1, 100);
    else
        self:SubItemByItemID(1, 1);
    end

    if self:TestSubItemByItemID(1, 99) then
        self:SubItemByItemID(1, 99);
    end
end

return PlayerCmptBag;
