--- Numeric validation and deterministic display rounding.
-- @module ubermensch.numbers

local Numbers = {}

--- Reports whether a raw value is a finite Lua number.
-- @param value Value obtained from a domain caller or host boundary.
-- @return boolean True only for finite numbers.
function Numbers.is_finite(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

--- Restricts a finite number to an inclusive range.
-- @param value Finite numeric value.
-- @param minimum Inclusive lower bound.
-- @param maximum Inclusive upper bound.
-- @return number Clamped value.
function Numbers.clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

--- Validates a numeric percentage while retaining fractional precision.
-- @param value Raw percentage.
-- @return number|nil Finite value in the inclusive range 0 through 100.
function Numbers.percent(value)
    if not Numbers.is_finite(value) or value < 0 or value > 100 then
        return nil
    end
    return value
end

--- Validates an integer percentage supplied by the player resource.
-- @param value Raw resource-table value.
-- @return number|nil Integer from 0 through 100, otherwise nil.
function Numbers.resource_percent(value)
    local result = Numbers.percent(value)
    if result == nil or result ~= math.floor(result) then
        return nil
    end
    return result
end

--- Rounds halves away from zero, independent of Lua version.
-- @param value Finite value to round.
-- @param places Number of decimal places to retain; defaults to zero.
-- @return number Rounded value with negative zero normalized to zero.
function Numbers.round_half_away(value, places)
    local scale = 10 ^ (places or 0)
    local scaled = value * scale
    local rounded
    if scaled >= 0 then
        rounded = math.floor(scaled + 0.5)
    else
        rounded = math.ceil(scaled - 0.5)
    end
    local result = rounded / scale
    if result == 0 then
        return 0
    end
    return result
end

--- Validates a positive integral server user ID.
-- @param value Raw user-ID value.
-- @return number|nil Positive integer user ID, otherwise nil.
function Numbers.userid(value)
    if not Numbers.is_finite(value)
        or value <= 0
        or value ~= math.floor(value)
    then
        return nil
    end
    return value
end

--- Validates a positive integral entity index.
-- @param value Raw entity index.
-- @return number|nil Positive integer index, otherwise nil.
function Numbers.entity_index(value)
    if not Numbers.is_finite(value)
        or value < 1
        or value ~= math.floor(value)
    then
        return nil
    end
    return value
end

return Numbers
