--- Text measurement, layout, and the fixed drawing resource contract.
-- @module ubermensch.renderer

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")
local Safe = require("ubermensch.safe")

local Renderer = {}
Renderer.__index = Renderer

--- Calls a mandatory draw operation and lets the guarded Draw callback report
-- unexpected host failures instead of silently treating them as a rendered HUD.
-- @param self Renderer instance.
-- @param name Mandatory draw-library operation.
-- @param ... Arguments passed to the operation.
-- @return any First host return value when the operation succeeds.
local function draw_call(self, name, ...)
    local ok, result = Safe.library(self.host.draw, name, ...)
    if not ok then
        error("draw." .. name .. " failed: " .. tostring(result), 2)
    end
    return result
end

--- Creates the invariant HUD font once and initializes a text-layout cache.
-- @param host LMAOBox host libraries.
-- @return table|nil Renderer instance.
-- @return string|nil Error when the font could not be created.
function Renderer.new(host)
    local ok, font = Safe.library(
        host.draw,
        "CreateFont",
        Constants.FONT.name,
        Constants.FONT.size,
        Constants.FONT.weight,
        Constants.FONT.flags
    )
    if not ok or font == nil then
        return nil, "draw.CreateFont failed"
    end
    return setmetatable({
        host = host,
        font = font,
        cache_lines = {},
        cache_width = nil,
        cache_height = nil,
        cache_line_height = nil,
    }, Renderer), nil
end

--- Measures the four-line widget and caches unchanged text dimensions.
-- Cache invalidation depends only on line text because the font and padding are
-- immutable for a runtime load.
-- @param lines Exactly four formatted lines.
-- @return number Widget width.
-- @return number Widget height.
-- @return number Common line height.
function Renderer:measure(lines)
    local cached = self.cache_lines
    if lines[1] == cached[1] and lines[2] == cached[2]
        and lines[3] == cached[3] and lines[4] == cached[4]
    then
        return self.cache_width, self.cache_height, self.cache_line_height
    end

    draw_call(self, "SetFont", self.font)
    local maximum_width = 0
    local maximum_height = 0
    for i = 1, 4 do
        local ok, width, height = Safe.library(
            self.host.draw,
            "GetTextSize",
            lines[i]
        )
        if not ok or not Numbers.is_finite(width)
            or not Numbers.is_finite(height)
            or width < 0
            or height < 0
        then
            error("draw.GetTextSize returned invalid dimensions")
        end
        width = Numbers.round_half_away(width, 0)
        height = Numbers.round_half_away(height, 0)
        maximum_width = math.max(maximum_width, width)
        maximum_height = math.max(maximum_height, height)
    end

    local layout = Constants.LAYOUT
    cached[1] = lines[1]
    cached[2] = lines[2]
    cached[3] = lines[3]
    cached[4] = lines[4]
    self.cache_width = maximum_width + layout.horizontal_padding * 2
    self.cache_height = maximum_height * 4
        + layout.vertical_padding * 2
        + layout.line_gap * 2
        + layout.separator_gap * 2
        + layout.separator_thickness
    self.cache_line_height = maximum_height
    return self.cache_width, self.cache_height, self.cache_line_height
end

--- Sets the host draw color from an immutable RGBA role.
-- @param self Renderer instance.
-- @param color Four-element RGBA table.
local function set_color(self, color)
    draw_call(
        self,
        "Color",
        color[1],
        color[2],
        color[3],
        color[4]
    )
end

--- Draws the fixed one-pixel separator between Uber and team-count content.
-- @param self Renderer instance.
-- @param bounds Integral widget bounds.
-- @param y Integral separator top coordinate.
local function draw_separator(self, bounds, y)
    set_color(self, Constants.TEAM_COUNT_COLORS.separator)
    draw_call(
        self,
        "FilledRect",
        bounds.x + Constants.LAYOUT.horizontal_padding,
        y,
        bounds.x + bounds.width - Constants.LAYOUT.horizontal_padding,
        y + Constants.LAYOUT.separator_thickness
    )
end

--- Draws the warning border as exactly four additional rectangles.
-- @param self Renderer instance.
-- @param x Left coordinate.
-- @param y Top coordinate.
-- @param width Widget width.
-- @param height Widget height.
local function draw_warning_border(self, x, y, width, height)
    set_color(self, Constants.COLORS.warning)
    draw_call(self, "FilledRect", x, y, x + width, y + 1)
    draw_call(
        self,
        "FilledRect",
        x,
        y + height - 1,
        x + width,
        y + height
    )
    draw_call(self, "FilledRect", x, y + 1, x + 1, y + height - 1)
    draw_call(
        self,
        "FilledRect",
        x + width - 1,
        y + 1,
        x + width,
        y + height - 1
    )
end

--- Renders one prepared frame with the exact rectangle/text call budget.
-- Each frame uses one background, one separator, and four text calls, plus
-- exactly four rectangles when source honesty requires the warning border.
-- @param prepared Prepared lines, colors, and warning flag.
-- @param bounds Pixel bounds and line height.
function Renderer:draw(prepared, bounds)
    draw_call(self, "SetFont", self.font)
    set_color(self, Constants.COLORS.background)
    draw_call(
        self,
        "FilledRect",
        bounds.x,
        bounds.y,
        bounds.x + bounds.width,
        bounds.y + bounds.height
    )
    if prepared.warning then
        draw_warning_border(
            self,
            bounds.x,
            bounds.y,
            bounds.width,
            bounds.height
        )
    end

    local text_x = bounds.x + Constants.LAYOUT.horizontal_padding
    local text_y = bounds.y + Constants.LAYOUT.vertical_padding
    for i = 1, 3 do
        set_color(self, prepared.colors[i])
        draw_call(self, "Text", text_x, text_y, prepared.lines[i])
        text_y = text_y + bounds.line_height + Constants.LAYOUT.line_gap
    end
    text_y = text_y - Constants.LAYOUT.line_gap
        + Constants.LAYOUT.separator_gap
    draw_separator(self, bounds, text_y)
    text_y = text_y + Constants.LAYOUT.separator_thickness
        + Constants.LAYOUT.separator_gap
    set_color(self, prepared.colors[4])
    draw_call(self, "Text", text_x, text_y, prepared.lines[4])
end

return Renderer
