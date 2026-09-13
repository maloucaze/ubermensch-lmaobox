--- Classification of supported and explicitly unsupported Medi Gun items.
-- @module ubermensch.weapons

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")

local Weapons = {}

--- Classifies a validated item definition without guessing unknown items.
-- @param item_definition Raw item-definition index read from a weapon.
-- @return string|nil `STOCK`, `KRITZ`, or `UNSUPPORTED`; nil when malformed or unknown.
function Weapons.classify(item_definition)
    if not Numbers.is_finite(item_definition)
        or item_definition ~= math.floor(item_definition)
    then
        return nil
    end
    if Constants.ITEM_FAMILY[item_definition] ~= nil then
        return Constants.ITEM_FAMILY[item_definition]
    end
    if Constants.KNOWN_UNSUPPORTED[item_definition] ~= nil then
        return "UNSUPPORTED"
    end
    return nil
end

--- Reports whether a family participates in charge comparisons.
-- @param family Family label or nil.
-- @return boolean True for Stock and Kritzkrieg only.
function Weapons.is_supported(family)
    return family == "STOCK" or family == "KRITZ"
end

return Weapons
