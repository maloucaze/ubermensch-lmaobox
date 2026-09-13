local Harness = require("support.harness")
local Fakes = require("support.fakes")
local Persistence = require("ubermensch.persistence")
local Position = require("ubermensch.position")

Harness.test("strict position format round trips", function()
    local content = Position.serialize(0.25, 0.75)
    local x, y = Position.parse(content)
    Harness.near(x, 0.25, 1e-9)
    Harness.near(y, 0.75, 1e-9)
    Harness.is_nil(Position.parse("x=0.25\ny=0.75\n"))
    Harness.is_nil(Position.parse("UBERMENSCH_POSITION_V2\nx=0.25\ny=0.75\n"))
    Harness.is_nil(Position.parse("UBERMENSCH_POSITION_V1\nx=-1\ny=0.5\n"))
end)

Harness.test("pixel position clamps widget fully on screen", function()
    local state = Position.new()
    state.x = 1
    state.y = 1
    local x, y = Position.pixels(state, 100, 80, 30, 20)
    Harness.equal(x, 70)
    Harness.equal(y, 60)
end)

Harness.test("fractional normalized positions become integer draw coordinates", function()
    local state = Position.new()
    state.x = 0.123
    state.y = 0.456
    local x, y = Position.pixels(state, 333, 271, 101, 43)
    Harness.equal(x, 41)
    Harness.equal(y, 124)
    Harness.equal(x, math.floor(x))
    Harness.equal(y, math.floor(y))
end)

Harness.test("dragging is menu-only and preserves pointer offset", function()
    local state = Position.new()
    state.x = 0.1
    state.y = 0.1
    local bounds = { x = 100, y = 100, width = 100, height = 50 }
    local ended = Position.update_drag(state, {
        menu_open = false, mouse_x = 110, mouse_y = 120,
        pressed = true, down = true, released = false,
    }, bounds, 1000, 800)
    Harness.falsy(state.dragging)
    Harness.falsy(ended)

    Position.update_drag(state, {
        menu_open = true, mouse_x = 110, mouse_y = 120,
        pressed = true, down = true, released = false,
    }, bounds, 1000, 800)
    Harness.truthy(state.dragging)
    Position.update_drag(state, {
        menu_open = true, mouse_x = 310, mouse_y = 220,
        pressed = false, down = true, released = false,
    }, bounds, 1000, 800)
    Harness.near(state.x, 0.3, 1e-9)
    Harness.near(state.y, 0.25, 1e-9)
    ended = Position.update_drag(state, {
        menu_open = true, mouse_x = 310, mouse_y = 220,
        pressed = false, down = false, released = true,
    }, bounds, 1000, 800)
    Harness.truthy(ended)
    Harness.truthy(state.dirty)
end)

local function memory_io(initial, writable)
    local files = initial or {}
    local writes = 0
    return {
        open = function(path, mode)
            if mode == "r" then
                if files[path] == nil then return nil end
                return {
                    read = function() return files[path] end,
                    close = function() end,
                }
            end
            if not writable(path) then return nil end
            local content = ""
            writes = writes + 1
            return {
                write = function(_, value) content = content .. value end,
                close = function() files[path] = content end,
            }
        end,
        files = files,
        write_count = function() return writes end,
    }
end

Harness.test("persistence loads preferred valid position", function()
    local preferred = "C:\\Users\\Test\\AppData\\Local\\lua\\ubermensch_position_v1.txt"
    local io_api = memory_io({ [preferred] = Position.serialize(0.4, 0.6) }, function() return true end)
    local host = Fakes.host({ io = io_api })
    local position = Position.new()
    Persistence.new(host, position, function() end)
    Harness.near(position.x, 0.4, 1e-9)
    Harness.near(position.y, 0.6, 1e-9)
end)

Harness.test("persistence falls back and warns only when every path fails", function()
    local io_api = memory_io({}, function(path)
        return string.find(path, "ubermensch%-lmaobox") ~= nil
    end)
    local host = Fakes.host({ io = io_api })
    local warnings = {}
    local position = Position.new()
    local persistence = Persistence.new(host, position, function(message)
        warnings[#warnings + 1] = message
    end)
    position.dirty = true
    Harness.truthy(persistence:save(position))
    Harness.equal(#warnings, 0)
    Harness.equal(io_api.write_count(), 1)

    local failing = memory_io({}, function() return false end)
    host = Fakes.host({ io = failing })
    persistence = Persistence.new(host, position, function(message)
        warnings[#warnings + 1] = message
    end)
    position.dirty = true
    Harness.falsy(persistence:save(position))
    Harness.falsy(persistence:save(position))
    Harness.equal(#warnings, 1)
end)

Harness.test("clean positions never write", function()
    local io_api = memory_io({}, function() return true end)
    local host = Fakes.host({ io = io_api })
    local position = Position.new()
    local persistence = Persistence.new(host, position, function() end)
    Harness.truthy(persistence:save(position))
    Harness.equal(io_api.write_count(), 0)
end)
