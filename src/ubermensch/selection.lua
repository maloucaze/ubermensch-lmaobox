--- Linear Medic selection with deployment, readiness, and stable tie-breaks.
-- @module ubermensch.selection

local Constants = require("ubermensch.constants")
local Comparison = require("ubermensch.comparison")
local Numbers = require("ubermensch.numbers")
local Weapons = require("ubermensch.weapons")

local Selection = {}

local SOURCE_RANK = {
    current = 3,
    resource = 2,
    estimate = 1,
    retained = 0,
    unknown = 0,
}

--- Calculates the freshness rank used only inside numeric tie tolerances.
-- @param candidate Resolved Medic candidate.
-- @return number Integer rank where a larger value is fresher.
local function freshness(candidate)
    return SOURCE_RANK[candidate.charge_source] or 0
end

--- Resolves deterministic tie-breaks without depending on roster order.
-- @param left First candidate.
-- @param right Second candidate.
-- @param prior_userid Previously selected server user ID, if any.
-- @return table Preferred candidate.
local function tie_break(left, right, prior_userid)
    local left_freshness = freshness(left)
    local right_freshness = freshness(right)
    if left_freshness ~= right_freshness then
        return left_freshness > right_freshness and left or right
    end

    if prior_userid ~= nil then
        if left.userid == prior_userid and right.userid ~= prior_userid then
            return left
        end
        if right.userid == prior_userid and left.userid ~= prior_userid then
            return right
        end
    end

    local left_index = left.entity_index or math.huge
    local right_index = right.entity_index or math.huge
    if left_index <= right_index then
        return left
    end
    return right
end

--- Chooses between two supported numeric candidates.
-- Active deployment always wins over inactive readiness. Active ties maximize
-- remaining charge; inactive ties minimize exact time-to-ready.
-- @param left First supported numeric candidate.
-- @param right Second supported numeric candidate.
-- @param prior_userid Previously selected user ID.
-- @return table Preferred candidate.
local function prefer_numeric(left, right, prior_userid)
    local left_active = left.deployed == true
    local right_active = right.deployed == true
    if left_active ~= right_active then
        return left_active and left or right
    end

    if left_active then
        local difference = left.charge - right.charge
        if math.abs(difference) > Constants.ACTIVE_TIE_PERCENT + 1e-9 then
            return difference > 0 and left or right
        end
        return tie_break(left, right, prior_userid)
    end

    local left_time = Comparison.time_to_ready(left.family, left.charge)
    local right_time = Comparison.time_to_ready(right.family, right.charge)
    local difference = left_time - right_time
    if math.abs(difference) > Constants.READY_TIE_SECONDS + 1e-9 then
        return difference < 0 and left or right
    end
    return tie_break(left, right, prior_userid)
end

--- Selects one eligible Medic in O(P) time without sorting.
-- Supported candidates with numeric charge outrank unidentified or charge-less
-- fallbacks. The fallback exists so incomplete field reads do not falsely imply
-- `NO MEDIC` when the roster still contains an eligible Medic.
-- @param candidates Plain resolved candidates for one team.
-- @param team Numeric team identifier.
-- @param prior_userid Previously selected user ID for stable ties.
-- @return table|nil Selected candidate, or nil when none is eligible.
function Selection.for_team(candidates, team, prior_userid)
    local best_numeric
    local best_fallback
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.team == team and candidate.alive == true
            and candidate.unsupported ~= true
        then
            local numeric = Weapons.is_supported(candidate.family)
                and Numbers.percent(candidate.charge) ~= nil
            if numeric then
                if best_numeric == nil then
                    best_numeric = candidate
                else
                    best_numeric = prefer_numeric(
                        best_numeric,
                        candidate,
                        prior_userid
                    )
                end
            elseif best_fallback == nil then
                best_fallback = candidate
            else
                best_fallback = tie_break(
                    best_fallback,
                    candidate,
                    prior_userid
                )
            end
        end
    end
    return best_numeric or best_fallback
end

return Selection
