--- Time-to-ready and advantage classification rules.
-- @module ubermensch.comparison

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")
local Weapons = require("ubermensch.weapons")

local Comparison = {}

--- Computes ideal seconds remaining until charge reaches 100 percent.
-- @param family Supported Medi Gun family.
-- @param charge Current or estimated percentage.
-- @return number|nil Nonnegative time-to-ready, or nil for unknown inputs.
function Comparison.time_to_ready(family, charge)
    local valid_charge = Numbers.percent(charge)
    if not Weapons.is_supported(family) or valid_charge == nil then
        return nil
    end
    return (100 - valid_charge) / Constants.CHARGE_RATE[family]
end

--- Classifies a signed time advantage using the inclusive equality window.
-- Positive values mean the local side becomes ready sooner.
-- @param time_difference Enemy TTR minus local TTR.
-- @return string|nil `ADV`, `DIS`, or `EQL`; nil for invalid input.
function Comparison.classify(time_difference)
    if not Numbers.is_finite(time_difference) then
        return nil
    end
    if time_difference > Constants.ADVANTAGE_SECONDS then
        return "ADV"
    end
    if time_difference < -Constants.ADVANTAGE_SECONDS then
        return "DIS"
    end
    return "EQL"
end

--- Compares two supported numeric sides without rounding intermediate values.
-- @param local_side Side containing family and charge.
-- @param enemy_side Side containing family and charge.
-- @return table|nil Comparison with status, charge_difference, and time_difference.
function Comparison.both(local_side, enemy_side)
    local local_time = Comparison.time_to_ready(
        local_side.family,
        local_side.charge
    )
    local enemy_time = Comparison.time_to_ready(
        enemy_side.family,
        enemy_side.charge
    )
    if local_time == nil or enemy_time == nil then
        return nil
    end
    local time_difference = enemy_time - local_time
    return {
        status = Comparison.classify(time_difference),
        charge_difference = local_side.charge - enemy_side.charge,
        time_difference = time_difference,
    }
end

return Comparison
