--- Resolves display sides, selection mode, comparison, and warning state.
-- @module ubermensch.state

local Constants = require("ubermensch.constants")
local Comparison = require("ubermensch.comparison")
local Selection = require("ubermensch.selection")
local Weapons = require("ubermensch.weapons")

local State = {}

--- Creates a confirmed empty side for a complete authoritative roster.
-- @param team Team identifier represented by the side.
-- @return table Display side representing `NO MED` at zero percent.
local function missing_side(team)
    return {
        team = team,
        missing = true,
        family = "NO MED",
        charge = 0,
        charge_source = "missing",
        family_source = "missing",
        deployment_source = "missing",
        deployed = false,
    }
end

--- Creates the compact fallback for a retained supported Medic who is dead.
-- @param candidate Selected dead-Medic identity and retained family.
-- @param team Team identifier represented by the side.
-- @return table Display side representing authoritative death.
local function dead_side(candidate, team)
    return {
        userid = candidate.userid,
        entity_index = candidate.entity_index,
        team = team,
        dead = true,
        family = "DEAD MED",
        charge = 0,
        charge_source = "dead",
        family_source = "dead",
        deployment_source = "dead",
        deployed = false,
        died_at = candidate.died_at,
    }
end

--- Creates an unknown side when roster absence cannot be proven.
-- @param team Team identifier represented by the side.
-- @return table Unknown display side.
local function unknown_side(team)
    return {
        team = team,
        family = nil,
        charge = nil,
        charge_source = "unknown",
        family_source = "unknown",
        deployment_source = "unknown",
        deployed = nil,
    }
end

--- Resolves a candidate or absence into a display side.
-- @param candidate Selected candidate, if any.
-- @param dead_candidate Selected dead-Medic fallback, if any.
-- @param team Team identifier.
-- @param roster_available Whether authoritative roster absence is provable.
-- @return table Display side.
local function resolve_side(candidate, dead_candidate, team, roster_available)
    if candidate ~= nil then
        return candidate
    end
    if dead_candidate ~= nil then
        return dead_side(dead_candidate, team)
    end
    if roster_available then
        return missing_side(team)
    end
    return unknown_side(team)
end

--- Determines whether a side contains retained, approximate, or unknown data.
-- Confirmed absence and death are exact and do not request a warning.
-- @param side Resolved display side.
-- @return boolean Whether the warning border is required for this side.
local function side_warns(side)
    if side.missing or side.dead then
        return false
    end
    return side.family_source ~= "current"
        or side.charge_source ~= "current"
        or side.deployment_source ~= "current"
end

--- Resolves a comparison when both sides or a confirmed absence are known.
-- @param local_side Local-team display side.
-- @param enemy_side Enemy-team display side.
-- @return table|nil Comparison, or nil when required data is unknown.
local function resolve_comparison(local_side, enemy_side)
    local local_unavailable = local_side.missing or local_side.dead
    local enemy_unavailable = enemy_side.missing or enemy_side.dead
    if local_unavailable and enemy_unavailable then
        return {
            status = "EQL",
            charge_difference = 0,
            time_difference = nil,
        }
    end

    if local_unavailable or enemy_unavailable then
        local known = local_unavailable and enemy_side or local_side
        if not Weapons.is_supported(known.family) or known.charge == nil then
            return nil
        end
        local difference = local_side.charge - enemy_side.charge
        return {
            status = local_unavailable and "DIS" or "ADV",
            charge_difference = difference,
            time_difference = nil,
        }
    end
    return Comparison.both(local_side, enemy_side)
end

--- Resolves the latest tracking snapshot into the three-line HUD model.
-- Self-Medic mode compares the alive local Medic directly. Other modes select
-- the nearest-time-to-ready eligible Medic on each team.
-- @param tracking Tracker view containing candidates, roster state, and local identity.
-- @param prior_selection Mutable per-team prior-selection table for stable ties.
-- @return table|nil Display model, or nil until a local team is known.
function State.resolve(tracking, prior_selection)
    local local_team = tracking.local_team or tracking.last_local_team
    local enemy_team = Constants.ENEMY_TEAM[local_team]
    if enemy_team == nil then
        return nil
    end

    local local_candidate
    local self_mode = tracking.local_alive == true
        and tracking.local_class == Constants.MEDIC_CLASS
    if self_mode then
        for i = 1, #tracking.candidates do
            local candidate = tracking.candidates[i]
            if candidate.is_local then
                if candidate.unsupported ~= true then
                    local_candidate = candidate
                end
                break
            end
        end
    else
        local_candidate = Selection.for_team(
            tracking.candidates,
            local_team,
            prior_selection[local_team]
        )
    end
    local enemy_candidate = Selection.for_team(
        tracking.candidates,
        enemy_team,
        prior_selection[enemy_team]
    )

    local dead_candidates = tracking.dead_candidates or {}
    local local_dead
    if local_candidate == nil then
        local_dead = Selection.dead_for_team(
            dead_candidates,
            local_team,
            prior_selection[local_team]
        )
    end
    local enemy_dead
    if enemy_candidate == nil then
        enemy_dead = Selection.dead_for_team(
            dead_candidates,
            enemy_team,
            prior_selection[enemy_team]
        )
    end

    if local_candidate ~= nil then
        prior_selection[local_team] = local_candidate.userid
    elseif local_dead ~= nil then
        prior_selection[local_team] = local_dead.userid
    elseif tracking.roster_available then
        prior_selection[local_team] = nil
    end
    if enemy_candidate ~= nil then
        prior_selection[enemy_team] = enemy_candidate.userid
    elseif enemy_dead ~= nil then
        prior_selection[enemy_team] = enemy_dead.userid
    elseif tracking.roster_available then
        prior_selection[enemy_team] = nil
    end

    local local_side = resolve_side(
        local_candidate,
        local_dead,
        local_team,
        tracking.roster_available
    )
    local enemy_side = resolve_side(
        enemy_candidate,
        enemy_dead,
        enemy_team,
        tracking.roster_available
    )
    local comparison = resolve_comparison(local_side, enemy_side)

    return {
        local_side = local_side,
        enemy_side = enemy_side,
        comparison = comparison,
        self_mode = self_mode,
        warning = not tracking.roster_available
            or side_warns(local_side)
            or side_warns(enemy_side),
    }
end

return State
