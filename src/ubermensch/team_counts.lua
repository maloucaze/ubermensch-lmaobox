--- Authoritative local-first alive-player count resolution.
-- @module ubermensch.team_counts

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")

local TeamCounts = {}

--- Validates an authoritative alive-player count.
-- @param value Candidate count derived from the reconciled roster.
-- @return number|nil Nonnegative integer, otherwise nil.
local function alive_count(value)
    if not Numbers.is_finite(value)
        or value < 0
        or value ~= math.floor(value)
    then
        return nil
    end
    return value
end

--- Resolves alive-player counts into local-team-first display order.
-- Counts are withheld when the roster is incomplete; retaining a previous
-- numeric value would misrepresent a rapidly changing lifecycle fact.
-- @param alive_counts Counts keyed by raw RED/BLU team number.
-- @param local_team Validated local team number.
-- @param roster_available Whether the complete roster can support factual counts.
-- @return table Display model containing availability and ordered counts.
function TeamCounts.resolve(alive_counts, local_team, roster_available)
    local enemy_team = Constants.ENEMY_TEAM[local_team]
    if roster_available ~= true or enemy_team == nil
        or type(alive_counts) ~= "table"
    then
        return { available = false }
    end

    local local_count = alive_count(alive_counts[local_team])
    local enemy_count = alive_count(alive_counts[enemy_team])
    if local_count == nil or enemy_count == nil then
        return { available = false }
    end
    return {
        available = true,
        local_count = local_count,
        enemy_count = enemy_count,
    }
end

return TeamCounts
