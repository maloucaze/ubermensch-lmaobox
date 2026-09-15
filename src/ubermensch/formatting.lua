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

--- Resolves the display tokens for one team line without allocating text.
-- @param side Resolved display side.
-- @return string Team label.
-- @return string Family label.
-- @return number|nil Rounded percentage.
-- @return boolean Whether the percentage carries an approximation marker.
local function side_tokens(side)
    local charge = side.charge ~= nil
        and Numbers.round_half_away(side.charge, 0)
        or nil
    return Constants.TEAM_NAME[side.team] or "?",
        side.family or "UNKNOWN",
        charge,
        charge ~= nil and approximate(side.charge_source)
end

--- Formats already normalized team-line tokens.
-- @param team Team label.
-- @param family Family label.
-- @param charge Rounded percentage or nil.
-- @param is_approximate Whether to add `~`.
-- @return string Team, charge, and family line.
local function format_side_tokens(team, family, charge, is_approximate)
    local charge_text = charge == nil and "?" or string.format("%.0f", charge)
    if charge ~= nil and is_approximate then
        charge_text = "~" .. charge_text
    end
    return string.format("%s %s%% (%s)", team, charge_text, family)
end

--- Formats one team line without exposing player identity.
-- @param side Resolved display side.
-- @return string Team, charge, and family line.
function Formatting.side_line(side)
    return format_side_tokens(side_tokens(side))
end

--- Updates one cached team line only when a displayed token changes.
-- @param prepared Reusable formatting result.
-- @param line_index One or two.
-- @param side Resolved display side.
local function prepare_side(prepared, line_index, side)
    local team, family, charge, is_approximate = side_tokens(side)
    local cache = prepared.cache[line_index]
    if cache.team ~= team or cache.family ~= family
        or cache.charge ~= charge
        or cache.is_approximate ~= is_approximate
    then
        prepared.lines[line_index] = format_side_tokens(
            team,
            family,
            charge,
            is_approximate
        )
        cache.team = team
        cache.family = family
        cache.charge = charge
        cache.is_approximate = is_approximate
    end
    prepared.colors[line_index] = Formatting.side_color(side)
end

--- Updates the cached comparison line only when a displayed token changes.
-- @param prepared Reusable formatting result.
-- @param model Resolved HUD model.
local function prepare_comparison(prepared, model)
    local comparison = model.comparison
    local status = comparison ~= nil and comparison.status or nil
    local charge = comparison ~= nil
        and Numbers.round_half_away(comparison.charge_difference, 0)
        or nil
    local time = comparison ~= nil and comparison.time_difference ~= nil
        and Numbers.round_half_away(comparison.time_difference, 1)
        or nil
    local is_approximate = comparison ~= nil
        and approximate_comparison(model)
        or false
    local cache = prepared.cache[3]
    if cache.status ~= status or cache.charge ~= charge
        or cache.time ~= time or cache.is_approximate ~= is_approximate
    then
        prepared.lines[3] = Formatting.comparison_line(model)
        cache.status = status
        cache.charge = charge
        cache.time = time
        cache.is_approximate = is_approximate
    end
    prepared.colors[3] = Formatting.comparison_color(comparison)
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

--- Produces text and color roles, reusing an optional prior result safely.
-- Cached invalidation uses only display-rounded values, field-source markers,
-- family/team labels, deployment/readiness color inputs, and warning state.
-- Raw values still drive comparison and selection before this presentation step.
-- @param model Resolved HUD model.
-- @param prepared Optional result from the preceding capture.
-- @return table Three lines, three colors, and warning-border flag.
function Formatting.prepare(model, prepared)
    prepared = prepared or {
        lines = {},
        colors = {},
        cache = { {}, {}, {} },
    }
    prepare_side(prepared, 1, model.local_side)
    prepare_side(prepared, 2, model.enemy_side)
    prepare_comparison(prepared, model)
    prepared.warning = model.warning
    return prepared
end

return Formatting
