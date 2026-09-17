--- Classification and capability groups for known Medi Gun items.
-- @module ubermensch.weapons

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")

local Weapons = {}

--- Classifies a validated item definition without guessing unknown items.
-- @param item_definition Raw item-definition index read from a weapon.
-- @return string|nil Known family label; nil when malformed or unknown.
function Weapons.classify(item_definition)
    if not Numbers.is_finite(item_definition)
        or item_definition ~= math.floor(item_definition)
    then
        return nil
    end
    if Constants.ITEM_FAMILY[item_definition] ~= nil then
        return Constants.ITEM_FAMILY[item_definition]
    end
    return nil
end

--- Reports whether a family has complete comparison and estimation support.
-- @param family Family label or nil.
-- @return boolean True for Stock, Kritzkrieg, and Quick-Fix.
function Weapons.is_supported(family)
    return family == "STOCK" or family == "KRITZ" or family == "QF"
end

--- Reports whether a known family can be represented on a team line.
-- Vaccinator is display-only and intentionally excluded from comparison math.
-- @param family Family label or nil.
-- @return boolean True for every explicitly recognized family.
function Weapons.is_displayable(family)
    return Weapons.is_supported(family) or family == "VACC"
end

--- Returns the deterministic family preference for equal numeric readiness.
-- @param family Fully supported family label.
-- @return number Tie rank, with a larger value preferred.
function Weapons.tie_rank(family)
    return Constants.FAMILY_TIE_RANK[family] or 0
end

return Weapons
