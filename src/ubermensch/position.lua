--- Pure normalized position, screen clamping, and drag state transitions.
-- @module ubermensch.position

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")

local Position = {}

--- Creates the default normalized widget position and idle drag state.
-- @return table Mutable position state.
function Position.new()
    return {
        x = Constants.LAYOUT.default_x,
        y = Constants.LAYOUT.default_y,
        dragging = false,
        drag_offset_x = 0,
        drag_offset_y = 0,
        dirty = false,
    }
end

--- Parses the strict versioned persistence format.
-- @param content Complete file contents.
-- @return number|nil Normalized x coordinate.
-- @return number|nil Normalized y coordinate; both values are nil on rejection.
function Position.parse(content)
    if type(content) ~= "string" then
        return nil, nil
    end
    local header, x_text, y_text = string.match(
        content,
        "^([^\r\n]+)\r?\nx=([^\r\n]+)\r?\ny=([^\r\n]+)\r?\n?$"
    )
    if header ~= Constants.POSITION_HEADER then
        return nil, nil
    end
    local x = tonumber(x_text)
    local y = tonumber(y_text)
    if not Numbers.is_finite(x)
        or not Numbers.is_finite(y)
        or x < 0
        or x > 1
        or y < 0
        or y > 1
    then
        return nil, nil
    end
    return x, y
end

--- Serializes normalized coordinates in the strict versioned format.
-- @param x Normalized horizontal coordinate.
-- @param y Normalized vertical coordinate.
-- @return string|nil File contents, or nil for invalid coordinates.
function Position.serialize(x, y)
    if not Numbers.is_finite(x)
        or not Numbers.is_finite(y)
        or x < 0
        or x > 1
        or y < 0
        or y > 1
    then
        return nil
    end
    return string.format(
        "%s\nx=%.8f\ny=%.8f\n",
        Constants.POSITION_HEADER,
        x,
        y
    )
end

--- Converts normalized coordinates to a fully on-screen integer pixel position.
-- LMAOBox draw calls reject fractional coordinates even when they are finite,
-- so rounding is part of the host-boundary contract rather than presentation.
-- @param state Position state containing normalized coordinates.
-- @param screen_width Current screen width.
-- @param screen_height Current screen height.
-- @param widget_width Measured widget width.
-- @param widget_height Measured widget height.
-- @return number Clamped x pixel.
-- @return number Clamped y pixel.
function Position.pixels(
    state,
    screen_width,
    screen_height,
    widget_width,
    widget_height
)
    local maximum_x = math.max(0, math.floor(screen_width - widget_width))
    local maximum_y = math.max(0, math.floor(screen_height - widget_height))
    local pixel_x = Numbers.round_half_away(state.x * screen_width, 0)
    local pixel_y = Numbers.round_half_away(state.y * screen_height, 0)
    return Numbers.clamp(pixel_x, 0, maximum_x),
        Numbers.clamp(pixel_y, 0, maximum_y)
end

--- Applies one menu-gated mouse sample to the drag state.
-- The initial click offset is preserved, coordinates remain normalized, and a
-- completed drag is reported so persistence can occur outside the Draw logic.
-- @param state Mutable position state.
-- @param input Plain mouse/menu/button sample.
-- @param bounds Current widget bounds with x, y, width, and height.
-- @param screen_width Current screen width.
-- @param screen_height Current screen height.
-- @return boolean True only when a drag ended in this sample.
function Position.update_drag(
    state,
    input,
    bounds,
    screen_width,
    screen_height
)
    local ended = false
    local inside = input.mouse_x >= bounds.x
        and input.mouse_x <= bounds.x + bounds.width
        and input.mouse_y >= bounds.y
        and input.mouse_y <= bounds.y + bounds.height

    if not state.dragging and input.menu_open and input.pressed and inside then
        state.dragging = true
        state.drag_offset_x = input.mouse_x - bounds.x
        state.drag_offset_y = input.mouse_y - bounds.y
    end

    if state.dragging then
        if not input.menu_open or input.released or not input.down then
            state.dragging = false
            state.dirty = true
            ended = true
        else
            local pixel_x = input.mouse_x - state.drag_offset_x
            local pixel_y = input.mouse_y - state.drag_offset_y
            local maximum_x = math.max(0, screen_width - bounds.width)
            local maximum_y = math.max(0, screen_height - bounds.height)
            pixel_x = Numbers.clamp(pixel_x, 0, maximum_x)
            pixel_y = Numbers.clamp(pixel_y, 0, maximum_y)
            state.x = screen_width > 0 and pixel_x / screen_width or 0
            state.y = screen_height > 0 and pixel_y / screen_height or 0
        end
    end
    return ended
end

return Position
