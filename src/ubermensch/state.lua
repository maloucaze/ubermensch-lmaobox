--- Resolves display sides, selection mode, comparison, and warning state.
-- @module ubermensch.state

local Constants = require("ubermensch.constants")
local Comparison = require("ubermensch.comparison")
local Selection = require("ubermensch.selection")
local Weapons = require("ubermensch.weapons")

local State = {}

--- Creates a confirmed empty side for a complete authoritative roster.
-- @param team Team identifier represented by the side.
-- @return table Display side representing `NO MEDIC` at zero percent.
local function missing_side(team)
    return {
        team = team,
        missing = true,
        family = "NO MEDIC",
        charge = 0,
        charge_source = "missing",
        family_source = "missing",
        deployment_source = "missing",
        deployed = false,
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
-- @param team Team identifier.
-- @param roster_available Whether authoritative roster absence is provable.
-- @return table Display side.
local function resolve_side(candidate, team, roster_available)
    if candidate ~= nil then
        return candidate
    end
    if roster_available then
        return missing_side(team)
    end
    return unknown_side(team)
end

--- Determines whether a side contains retained, approximate, or unknown data.
-- Confirmed `NO MEDIC` is exact and therefore does not request a warning.
-- @param side Resolved display side.
-- @return boolean Whether the warning border is required for this side.
local function side_warns(side)
    if side.missing then
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
    if local_side.missing and enemy_side.missing then
        return {
            status = "EQUAL",
            charge_difference = 0,
            time_difference = nil,
        }
    end

    if local_side.missing or enemy_side.missing then
        local known = local_side.missing and enemy_side or local_side
        if not Weapons.is_supported(known.family) or known.charge == nil then
            return nil
        end
        local difference = local_side.charge - enemy_side.charge
        return {
            status = local_side.missing and "DIS" or "ADV",
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

    if local_candidate ~= nil then
        prior_selection[local_team] = local_candidate.userid
    elseif tracking.roster_available then
        prior_selection[local_team] = nil
    end
    if enemy_candidate ~= nil then
        prior_selection[enemy_team] = enemy_candidate.userid
    elseif tracking.roster_available then
        prior_selection[enemy_team] = nil
    end

    local local_side = resolve_side(
        local_candidate,
        local_team,
        tracking.roster_available
    )
    local enemy_side = resolve_side(
        enemy_candidate,
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
