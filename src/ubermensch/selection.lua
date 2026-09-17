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

--- Prefers the requested fixed family order inside a readiness tie.
-- Family never overrides active state or a readiness difference outside the
-- normal-selection tolerance.
-- @param left First fully supported candidate.
-- @param right Second fully supported candidate.
-- @return table|nil Preferred candidate, or nil when families tie.
local function family_tie(left, right)
    local left_rank = Weapons.tie_rank(left.family)
    local right_rank = Weapons.tie_rank(right.family)
    if left_rank == right_rank then
        return nil
    end
    return left_rank > right_rank and left or right
end

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
    local preferred_family = family_tie(left, right)
    if preferred_family ~= nil then
        return preferred_family
    end
    return tie_break(left, right, prior_userid)
end

--- Chooses between display-only Vaccinator candidates.
-- A larger known current/resource percentage is the most useful fallback;
-- absent or tied charge uses the ordinary stable freshness tie-break.
-- @param left First Vaccinator candidate.
-- @param right Second Vaccinator candidate.
-- @param prior_userid Previously selected user ID.
-- @return table Preferred candidate.
local function prefer_vacc(left, right, prior_userid)
    local left_charge = Numbers.percent(left.charge)
    local right_charge = Numbers.percent(right.charge)
    if left_charge ~= nil and right_charge ~= nil and left_charge ~= right_charge then
        return left_charge > right_charge and left or right
    end
    if left_charge ~= nil and right_charge == nil then
        return left
    end
    if right_charge ~= nil and left_charge == nil then
        return right
    end
    return tie_break(left, right, prior_userid)
end

--- Selects one living Medic in O(P) time without sorting.
-- Numeric comparison-supported candidates outrank charge-less supported
-- candidates, Vaccinator, and unidentified/custom fallbacks in that order.
-- Every living Medic remains representable so unknown equipment cannot falsely
-- imply `NO MED`.
-- @param candidates Plain resolved candidates for one team.
-- @param team Numeric team identifier.
-- @param prior_userid Previously selected user ID for stable ties.
-- @return table|nil Selected candidate, or nil when none is eligible.
function Selection.for_team(candidates, team, prior_userid)
    local best_numeric
    local best_supported_fallback
    local best_vacc
    local best_fallback
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.team == team and candidate.alive == true then
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
            elseif Weapons.is_supported(candidate.family) then
                if best_supported_fallback == nil then
                    best_supported_fallback = candidate
                else
                    best_supported_fallback = tie_break(
                        best_supported_fallback,
                        candidate,
                        prior_userid
                    )
                end
            elseif candidate.family == "VACC" then
                if best_vacc == nil then
                    best_vacc = candidate
                else
                    best_vacc = prefer_vacc(
                        best_vacc,
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
    return best_numeric or best_supported_fallback or best_vacc or best_fallback
end

--- Selects the dead-Medic fallback for a team in one linear pass.
-- A previously selected identity remains stable; otherwise the most recent
-- authoritative death wins, with entity index providing deterministic ties.
-- @param candidates Retained dead-Medic candidates.
-- @param team Numeric team identifier.
-- @param prior_userid Previously selected server user ID, if any.
-- @return table|nil Preferred dead candidate, or nil when none qualifies.
function Selection.dead_for_team(candidates, team, prior_userid)
    local best
    for i = 1, #candidates do
        local candidate = candidates[i]
        if candidate.team == team and candidate.dead == true then
            if candidate.userid == prior_userid then
                return candidate
            end
            if best == nil or (candidate.died_at or -math.huge)
                > (best.died_at or -math.huge)
            then
                best = candidate
            elseif (candidate.died_at or -math.huge)
                == (best.died_at or -math.huge)
                and (candidate.entity_index or math.huge)
                    < (best.entity_index or math.huge)
            then
                best = candidate
            end
        end
    end
    return best
end

return Selection
