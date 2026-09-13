--- Pure HUD text and color-role formatting.
-- @module ubermensch.formatting

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")

local Formatting = {}

--- Formats a rounded signed value, omitting a sign for normalized zero.
-- @param value Finite value.
-- @param places Decimal places.
-- @param suffix Unit suffix.
-- @return string Signed, half-away-rounded representation.
local function signed(value, places, suffix)
    local rounded = Numbers.round_half_away(value, places)
    local format = places == 0 and "%d" or ("%." .. places .. "f")
    local body = string.format(format, rounded)
    if rounded > 0 then
        body = "+" .. body
    end
    return body .. suffix
end

--- Reports whether a field source must be visibly marked as approximate.
-- @param source Field source label.
-- @return boolean True for resource and estimated values.
local function approximate(source)
    return source == "resource" or source == "estimate"
end

--- Reports whether comparison math consumed a noncurrent numeric or family fact.
-- @param model Resolved HUD model.
-- @return boolean Whether every displayed difference needs an approximation mark.
local function approximate_comparison(model)
    return approximate(model.local_side.charge_source)
        or approximate(model.enemy_side.charge_source)
        or model.local_side.family_source == "retained"
        or model.enemy_side.family_source == "retained"
end

--- Formats one team line without exposing player identity.
-- @param side Resolved display side.
-- @return string Team, charge, and family line.
function Formatting.side_line(side)
    local team = Constants.TEAM_NAME[side.team] or "?"
    local family = side.family or "UNKNOWN"
    local charge
    if side.charge == nil then
        charge = "?"
    else
        charge = string.format("%.0f", Numbers.round_half_away(side.charge, 0))
        if approximate(side.charge_source) then
            charge = "~" .. charge
        end
    end
    return string.format("%s %s%% (%s)", team, charge, family)
end

--- Resolves a team-line color from deployment and readiness precedence.
-- @param side Resolved side.
-- @return table RGBA color constant.
function Formatting.side_color(side)
    if side.deployed == true then
        if side.team == Constants.TEAM.RED then
            return Constants.COLORS.red_deployed
        end
        return Constants.COLORS.blu_deployed
    end
    if side.charge ~= nil and side.charge >= 100 then
        return Constants.COLORS.ready
    end
    return Constants.COLORS.text
end

--- Formats the comparison line, including source-honesty markers.
-- @param model Resolved HUD model.
-- @return string Exact status line, or `-` when comparison inputs are unavailable.
function Formatting.comparison_line(model)
    local comparison = model.comparison
    if comparison == nil then
        return "-"
    end

    local approximate_input = approximate_comparison(model)
    local marker = approximate_input and "~" or ""
    local result = comparison.status
        .. " | "
        .. marker
        .. signed(comparison.charge_difference, 0, "%")
    if comparison.time_difference ~= nil then
        result = result
            .. " | "
            .. marker
            .. signed(comparison.time_difference, 1, "s")
    end
    return result
end

--- Resolves the semantic color for the comparison status.
-- @param comparison Comparison table or nil.
-- @return table RGBA color constant.
function Formatting.comparison_color(comparison)
    if comparison == nil or comparison.status == "EQUAL" then
        return Constants.COLORS.text
    end
    if comparison.status == "ADV" then
        return Constants.COLORS.advantage
    end
    return Constants.COLORS.disadvantage
end

--- Produces all immutable per-frame text and color roles from a HUD model.
-- @param model Resolved HUD model.
-- @return table Three lines, three colors, and warning-border flag.
function Formatting.prepare(model)
    return {
        lines = {
            Formatting.side_line(model.local_side),
            Formatting.side_line(model.enemy_side),
            Formatting.comparison_line(model),
        },
        colors = {
            Formatting.side_color(model.local_side),
            Formatting.side_color(model.enemy_side),
            Formatting.comparison_color(model.comparison),
        },
        warning = model.warning,
    }
end

return Formatting
