--- Pure HUD text and color-role formatting.
-- @module ubermensch.formatting

local Constants = require("ubermensch.constants")
local Comparison = require("ubermensch.comparison")
local Numbers = require("ubermensch.numbers")

local Formatting = {}

--- Reports whether a field source must be visibly marked as approximate.
-- @param source Field source label.
-- @return boolean True for resource and estimated values.
local function approximate(source)
    return source == "resource" or source == "estimate"
end

--- Reports whether displayed readiness depends on a noncurrent input.
-- A retained family affects the rate even when the percentage itself is exact.
-- @param side Resolved display side.
-- @return boolean Whether the readiness value carries an approximation marker.
local function approximate_readiness(side)
    return approximate(side.charge_source)
        or side.family_source == "retained"
end

--- Reports whether comparison math consumed a noncurrent numeric or family fact.
-- @param model Resolved HUD model.
-- @return boolean Whether displayed differences need an approximation mark.
local function approximate_comparison(model)
    return approximate(model.local_side.charge_source)
        or approximate(model.enemy_side.charge_source)
        or model.local_side.family_source == "retained"
        or model.enemy_side.family_source == "retained"
end

--- Converts a rounded whole number to signed unit text.
-- @param value Finite value to round half away from zero.
-- @param suffix Unit suffix.
-- @param is_approximate Whether to prefix the token with `~`.
-- @return string Signed whole-number token.
local function signed_token(value, suffix, is_approximate)
    local rounded = Numbers.round_half_away(value, 0)
    local prefix = rounded > 0 and "+" or ""
    local marker = is_approximate and "~" or ""
    return marker .. prefix .. string.format("%.0f", rounded) .. suffix
end

--- Right-aligns a token within a display column.
-- @param value Already formatted text.
-- @param width Maximum token width for the column.
-- @return string Space-padded token.
local function align_right(value, width)
    return string.rep(" ", width - #value) .. value
end

--- Resolves cached scalar tokens for a team line.
-- @param cache Reusable side-token cache.
-- @param side Resolved display side.
-- @return boolean Whether a displayed token changed.
local function update_side_cache(cache, side)
    local kind = side.dead and "dead"
        or (side.missing and "missing" or "normal")
    local team = Constants.TEAM_NAME[side.team] or "?"
    local family = side.family or "UNKNOWN"
    local charge = side.charge ~= nil
        and Numbers.round_half_away(side.charge, 0)
        or nil
    local readiness = Comparison.time_to_ready(side.family, side.charge)
    readiness = readiness ~= nil
        and Numbers.round_half_away(readiness, 0)
        or nil
    local charge_approximate = charge ~= nil and approximate(side.charge_source)
    local readiness_approximate = readiness ~= nil
        and approximate_readiness(side)
    local changed = cache.kind ~= kind or cache.team ~= team
        or cache.family ~= family or cache.charge ~= charge
        or cache.charge_approximate ~= charge_approximate
        or cache.readiness ~= readiness
        or cache.readiness_approximate ~= readiness_approximate
    if changed then
        cache.kind = kind
        cache.team = team
        cache.family = family
        cache.charge = charge
        cache.charge_approximate = charge_approximate
        cache.readiness = readiness
        cache.readiness_approximate = readiness_approximate
    end
    return changed
end

--- Resolves cached scalar tokens for the comparison line.
-- @param cache Reusable comparison-token cache.
-- @param model Resolved HUD model.
-- @return boolean Whether a displayed token changed.
local function update_comparison_cache(cache, model)
    local comparison = model.comparison
    local status = comparison ~= nil and comparison.status or nil
    local charge = comparison ~= nil
        and Numbers.round_half_away(comparison.charge_difference, 0)
        or nil
    local time = comparison ~= nil and comparison.time_difference ~= nil
        and Numbers.round_half_away(comparison.time_difference, 0)
        or nil
    local is_approximate = comparison ~= nil
        and approximate_comparison(model)
        or false
    local changed = cache.status ~= status or cache.charge ~= charge
        or cache.time ~= time or cache.is_approximate ~= is_approximate
    if changed then
        cache.status = status
        cache.charge = charge
        cache.time = time
        cache.is_approximate = is_approximate
    end
    return changed
end

--- Resolves cached scalar tokens for the authoritative alive-player line.
-- @param cache Reusable team-count token cache.
-- @param counts Resolved team-count model.
-- @return boolean Whether the displayed line changed.
local function update_team_counts_cache(cache, counts)
    local available = counts ~= nil and counts.available == true
    local local_count = available and counts.local_count or nil
    local enemy_count = available and counts.enemy_count or nil
    local changed = cache.available ~= available
        or cache.local_count ~= local_count
        or cache.enemy_count ~= enemy_count
    if changed then
        cache.available = available
        cache.local_count = local_count
        cache.enemy_count = enemy_count
    end
    return changed
end

--- Builds percentage and readiness text from a cached normal side.
-- @param cache Side-token cache.
-- @return string Percentage token.
-- @return string Readiness token.
local function side_numeric_text(cache)
    local charge
    if cache.charge == nil then
        charge = "?%"
    else
        local marker = cache.charge_approximate and "~" or ""
        charge = marker .. string.format("%.0f%%", cache.charge)
    end
    local readiness
    if cache.readiness == nil then
        readiness = "-"
    else
        local marker = cache.readiness_approximate and "~" or ""
        readiness = marker .. string.format("%.0fs", cache.readiness)
    end
    return charge, readiness
end

--- Builds percentage and readiness text from cached comparison values.
-- @param cache Comparison-token cache.
-- @return string|nil Percentage token, or nil when comparison is unavailable.
-- @return string|nil Readiness-difference token.
local function comparison_numeric_text(cache)
    if cache.status == nil then
        return nil, nil
    end
    local charge = signed_token(cache.charge, "%", cache.is_approximate)
    local time = cache.time ~= nil
        and signed_token(cache.time, "s", cache.is_approximate)
        or "-"
    return charge, time
end

--- Formats a normal team line using shared numeric column widths.
-- @param cache Side-token cache.
-- @param charge_text Formatted percentage token.
-- @param readiness_text Formatted readiness token.
-- @param charge_width Shared percentage-column width.
-- @param readiness_width Shared time-column width.
-- @return string Aligned team line.
local function normal_side_line(
    cache,
    charge_text,
    readiness_text,
    charge_width,
    readiness_width
)
    return cache.team
        .. " | " .. align_right(charge_text, charge_width)
        .. " | " .. align_right(readiness_text, readiness_width)
        .. " | " .. cache.family
end

--- Formats a compact authoritative missing or dead team line.
-- @param cache Side-token cache with `missing` or `dead` kind.
-- @return string Compact line.
local function compact_side_line(cache)
    return cache.team .. " | "
        .. (cache.kind == "dead" and "DEAD MED" or "NO MED")
end

--- Rebuilds all lines together so numeric columns share exact widths.
-- @param prepared Reusable formatting result and caches.
local function rebuild_lines(prepared)
    local first = prepared.cache[1]
    local second = prepared.cache[2]
    local comparison = prepared.cache[3]
    local first_charge, first_time = side_numeric_text(first)
    local second_charge, second_time = side_numeric_text(second)
    local comparison_charge, comparison_time = comparison_numeric_text(comparison)
    local charge_width = 1
    local time_width = 1

    if first.kind == "normal" then
        charge_width = math.max(charge_width, #first_charge)
        time_width = math.max(time_width, #first_time)
    end
    if second.kind == "normal" then
        charge_width = math.max(charge_width, #second_charge)
        time_width = math.max(time_width, #second_time)
    end
    if comparison_charge ~= nil then
        charge_width = math.max(charge_width, #comparison_charge)
        time_width = math.max(time_width, #comparison_time)
    end

    prepared.lines[1] = first.kind == "normal"
        and normal_side_line(
            first,
            first_charge,
            first_time,
            charge_width,
            time_width
        )
        or compact_side_line(first)
    prepared.lines[2] = second.kind == "normal"
        and normal_side_line(
            second,
            second_charge,
            second_time,
            charge_width,
            time_width
        )
        or compact_side_line(second)
    if comparison.status == nil then
        prepared.lines[3] = "-"
    else
        prepared.lines[3] = comparison.status
            .. " | " .. align_right(comparison_charge, charge_width)
            .. " | " .. align_right(comparison_time, time_width)
    end
end

--- Formats the cached local-first alive-player counts.
-- @param cache Team-count token cache.
-- @return string Factual counts or the neutral unavailable form.
local function team_counts_line(cache)
    if not cache.available then
        return "- vs. -"
    end
    return tostring(cache.local_count)
        .. " vs. " .. tostring(cache.enemy_count)
end

--- Formats one team line independently, without cross-line padding.
-- @param side Resolved display side.
-- @return string Compact missing/dead line or normal four-column line.
function Formatting.side_line(side)
    local cache = {}
    update_side_cache(cache, side)
    if cache.kind ~= "normal" then
        return compact_side_line(cache)
    end
    local charge, readiness = side_numeric_text(cache)
    return normal_side_line(cache, charge, readiness, #charge, #readiness)
end

--- Resolves a team-line color from availability, deployment, and readiness.
-- @param side Resolved side.
-- @return table RGBA color constant.
function Formatting.side_color(side)
    if side.missing or side.dead then
        return Constants.COLORS.unavailable
    end
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

--- Formats the comparison independently using whole-number differences.
-- @param model Resolved HUD model.
-- @return string Three-column status line, or `-` when unavailable.
function Formatting.comparison_line(model)
    local cache = {}
    update_comparison_cache(cache, model)
    local charge, time = comparison_numeric_text(cache)
    if charge == nil then
        return "-"
    end
    return cache.status .. " | " .. charge .. " | " .. time
end

--- Resolves the semantic color for the comparison status.
-- @param comparison Comparison table or nil.
-- @return table RGBA color constant.
function Formatting.comparison_color(comparison)
    if comparison == nil or comparison.status == "EQL" then
        return Constants.COLORS.text
    end
    if comparison.status == "ADV" then
        return Constants.COLORS.advantage
    end
    return Constants.COLORS.disadvantage
end

--- Resolves the fixed color for both factual and unavailable team counts.
-- @return table RGBA color constant.
function Formatting.team_counts_color()
    return Constants.TEAM_COUNT_COLORS.text
end

--- Produces aligned text and colors, reusing prior storage safely.
-- The Uber lines rebuild only when a display-rounded token changes; raw values
-- continue to drive selection and classification before presentation.
-- @param model Resolved HUD model.
-- @param prepared Optional result from the preceding capture.
-- @return table Four lines, four colors, and warning-border flag.
function Formatting.prepare(model, prepared)
    prepared = prepared or {
        lines = {},
        colors = {},
        cache = { {}, {}, {}, {} },
    }
    local changed = update_side_cache(prepared.cache[1], model.local_side)
    changed = update_side_cache(prepared.cache[2], model.enemy_side) or changed
    changed = update_comparison_cache(prepared.cache[3], model) or changed
    if changed then
        rebuild_lines(prepared)
    end
    if update_team_counts_cache(prepared.cache[4], model.team_counts) then
        prepared.lines[4] = team_counts_line(prepared.cache[4])
    end
    prepared.colors[1] = Formatting.side_color(model.local_side)
    prepared.colors[2] = Formatting.side_color(model.enemy_side)
    prepared.colors[3] = Formatting.comparison_color(model.comparison)
    prepared.colors[4] = Formatting.team_counts_color()
    prepared.warning = model.warning
    return prepared
end

return Formatting
