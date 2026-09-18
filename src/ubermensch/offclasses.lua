--- Definite enemy Sniper/Spy detection for supported competitive formats.
-- @module ubermensch.offclasses

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")

local Offclasses = {}

--- Validates a nonnegative integral roster or slot count.
-- @param value Candidate numeric count.
-- @return number|nil Valid count, otherwise nil.
local function count(value)
    if not Numbers.is_finite(value) or value < 0
        or value ~= math.floor(value)
    then
        return nil
    end
    return value
end

--- Infers a supported format only when configured slots are unusable.
-- Counts include connected valid RED/BLU players regardless of life state.
-- A roster exceeding six players on either team is deliberately excluded so
-- an observable Highlander roster cannot be mistaken for sixes.
-- @param team_counts Complete roster counts keyed by team number.
-- @return string|nil `4v4` or `6v6`, otherwise nil.
local function infer_format(team_counts)
    if type(team_counts) ~= "table" then
        return nil
    end
    local red = count(team_counts[Constants.TEAM.RED])
    local blu = count(team_counts[Constants.TEAM.BLU])
    if red == nil or blu == nil then
        return nil
    end
    local largest = math.max(red, blu)
    if largest > 6 then
        return nil
    end
    if largest >= 5 then
        return "6v6"
    end
    if largest == 4 then
        return "4v4"
    end
    return nil
end

--- Resolves the supported competitive format from validated match facts.
-- Casual and explicit Highlander states always win over slot or roster
-- evidence. Exact configured slots are preferred; inference is a fallback only
-- when the slot value is absent or unusable for a supported format.
-- @param tracking Reconciled match and roster facts.
-- @return string|nil Supported format label.
function Offclasses.format(tracking)
    if tracking.roster_available ~= true or tracking.is_casual == true
        or tracking.is_highlander == true
    then
        return nil
    end
    if tracking.is_competitive ~= true and tracking.is_tournament ~= true then
        return nil
    end

    local slots = count(tracking.configured_player_slots)
    if slots == Constants.HIGHLANDER_SLOTS then
        return nil
    end
    local configured = slots ~= nil
        and Constants.COMPETITIVE_FORMAT_SLOTS[slots]
        or nil
    if configured ~= nil then
        return configured
    end
    if slots ~= nil then
        return nil
    end
    return infer_format(tracking.team_player_counts)
end

--- Builds an ordered definite enemy off-class display model.
-- The count includes alive and dead players. A class is alive-colored whenever
-- at least one of its players is alive, and dead-colored only when all are dead.
-- @param tracking Reconciled roster and match facts.
-- @return table|nil Ordered detected classes, or nil when hidden.
function Offclasses.resolve(tracking)
    local format = Offclasses.format(tracking)
    local local_team = tracking.local_team or tracking.last_local_team
    local enemy_team = Constants.ENEMY_TEAM[local_team]
    local by_team = tracking.offclass_counts
    if format == nil or enemy_team == nil or type(by_team) ~= "table"
        or type(by_team[enemy_team]) ~= "table"
    then
        return nil
    end

    local classes = {}
    local enemy = by_team[enemy_team]
    for _, definition in ipairs({
        { class = Constants.SNIPER_CLASS, label = "SNIPER" },
        { class = Constants.SPY_CLASS, label = "SPY" },
    }) do
        local facts = enemy[definition.class]
        local total = facts ~= nil and count(facts.total) or nil
        local alive = facts ~= nil and count(facts.alive) or nil
        if total ~= nil and alive ~= nil and total > 0 and alive <= total then
            classes[#classes + 1] = {
                label = definition.label,
                count = total,
                alive = alive > 0,
            }
        end
    end
    if #classes == 0 then
        return nil
    end
    return {
        format = format,
        classes = classes,
    }
end

return Offclasses
