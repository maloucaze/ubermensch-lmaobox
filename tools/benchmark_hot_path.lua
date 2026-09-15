--- Repeatable development benchmark for Ubermensch's capture and Draw paths.
-- This uses deterministic Lua host doubles rather than claiming live LMAOBox
-- frame-time results. Its stable call counts and allocation measurements make
-- before/after hot-path changes comparable on the same Lua interpreter.
-- @module benchmark_hot_path

package.path = table.concat({
    "src/?.lua",
    "src/?/init.lua",
    package.path,
}, ";")

local Adapter = require("ubermensch.adapter")
local Constants = require("ubermensch.constants")
local Controller = require("ubermensch.controller")
local Position = require("ubermensch.position")
local Renderer = require("ubermensch.renderer")

local capture_iterations = tonumber(arg[1]) or 2000
local draw_iterations = tonumber(arg[2]) or 10000

--- Increments one named boundary-call counter.
-- @param counts Mutable counter table.
-- @param name Counter name.
local function count(counts, name)
    counts[name] = (counts[name] or 0) + 1
    counts.total = counts.total + 1
end

--- Creates one deterministic player-resource entity backed by fixed arrays.
-- @param counts Boundary-call counters.
-- @param rows Player facts keyed by entity index.
-- @return table Player-resource double.
local function make_resource(counts, rows)
    local mapping = {
        m_bConnected = "connected",
        m_bValid = "valid",
        m_bAlive = "alive",
        m_iTeam = "team",
        m_iUserID = "userid",
        m_iPlayerClass = "class",
        m_iChargeLevel = "charge",
    }
    local arrays = {}
    for property, field in pairs(mapping) do
        local values = {}
        for index = 1, Constants.MAX_PLAYERS do
            local row = rows[index]
            if row ~= nil then
                values[index + 1] = row[field]
            elseif field == "connected" or field == "valid"
                or field == "alive"
            then
                values[index + 1] = false
            else
                values[index + 1] = 0
            end
        end
        arrays[property] = values
    end
    return {
        GetPropDataTableBool = function(_, property)
            count(counts, "resource_table")
            return arrays[property]
        end,
        GetPropDataTableInt = function(_, property)
            count(counts, "resource_table")
            return arrays[property]
        end,
    }
end

--- Creates a supported Medi Gun entity double.
-- @param counts Boundary-call counters.
-- @param options Weapon identity, owner, family, and charge.
-- @return table Weapon entity double.
local function make_weapon(counts, options)
    return {
        GetIndex = function()
            count(counts, "entity_index")
            return options.index
        end,
        IsValid = function()
            count(counts, "weapon_valid")
            return true
        end,
        IsDormant = function()
            count(counts, "weapon_dormant")
            return false
        end,
        IsMedigun = function()
            count(counts, "is_medigun")
            return true
        end,
        GetPropEntity = function(_, property)
            count(counts, "weapon_owner")
            if property == "m_hOwner" then
                return options.owner
            end
        end,
        GetPropInt = function()
            count(counts, "weapon_family")
            return options.item
        end,
        GetPropFloat = function()
            count(counts, "weapon_charge")
            return options.charge
        end,
        GetPropBool = function(_, property)
            if property == "m_bChargeRelease" then
                count(counts, "weapon_deployment")
                return false
            end
            count(counts, "weapon_holster")
            return false
        end,
    }
end

--- Creates one current player entity double.
-- @param counts Boundary-call counters.
-- @param row Resource facts for the player.
-- @return table Player entity double.
-- @return table Mutable weapon holder populated after player creation.
local function make_player(counts, row)
    local holder = {}
    local player = {
        GetIndex = function()
            count(counts, "entity_index")
            return row.entity_index
        end,
        IsValid = function()
            count(counts, "player_valid")
            return true
        end,
        IsDormant = function()
            count(counts, "player_dormant")
            return false
        end,
        GetTeamNumber = function()
            count(counts, "player_team")
            return row.team
        end,
        GetPropInt = function()
            count(counts, "player_class")
            return row.class
        end,
        IsAlive = function()
            count(counts, "player_alive")
            return row.alive
        end,
        GetPropEntity = function(_, property)
            count(counts, "active_weapon")
            if property == "m_hActiveWeapon" then
                return holder.weapon
            end
        end,
        GetEntityForLoadoutSlot = function()
            count(counts, "loadout_weapon")
            return holder.weapon
        end,
    }
    return player, holder
end

--- Builds the stable full-roster host used by both benchmark phases.
-- @return table Host libraries.
-- @return table Boundary-call counters.
-- @return table Mutable host state.
local function make_host()
    local counts = { total = 0 }
    local state = {
        now = 10,
        delta_tick = 100,
        menu_open = false,
        draw_calls = 0,
    }
    local rows = {}
    local players = {}
    for index = 1, Constants.MAX_PLAYERS do
        local row = {
            entity_index = index,
            connected = true,
            valid = true,
            alive = true,
            team = index % 2 == 0 and Constants.TEAM.RED
                or Constants.TEAM.BLU,
            userid = 1000 + index,
            class = (index == 2 or index == 3)
                and Constants.MEDIC_CLASS or 1,
            charge = index == 2 and 65 or (index == 3 and 55 or 0),
        }
        rows[index] = row
        local player, holder = make_player(counts, row)
        players[index] = player
        if row.class == Constants.MEDIC_CLASS then
            holder.weapon = make_weapon(counts, {
                index = 100 + index,
                owner = player,
                item = index == 2 and 29 or 35,
                charge = row.charge / 100,
            })
        end
    end
    local resource = make_resource(counts, rows)
    local host = {
        entities = {
            GetLocalPlayer = function()
                count(counts, "get_local_player")
                return players[1]
            end,
            GetPlayerResources = function()
                count(counts, "get_player_resources")
                return resource
            end,
            FindByClass = function(class)
                count(counts, class == "CTFPlayer"
                    and "enumerate_players" or "enumerate_mediguns")
                if class == "CTFPlayer" then
                    return players
                end
                return {}
            end,
        },
        client = {
            GetPlayerInfo = function(index)
                count(counts, "player_info")
                return { UserID = rows[index].userid }
            end,
        },
        clientstate = {
            GetDeltaTick = function()
                count(counts, "network_revision")
                return state.delta_tick
            end,
        },
        engine = {
            GetMapName = function()
                count(counts, "map")
                return "pl_badwater"
            end,
            Con_IsVisible = function()
                count(counts, "console")
                return false
            end,
            IsGameUIVisible = function()
                count(counts, "game_ui")
                return false
            end,
        },
        gamerules = {
            GetRoundState = function()
                count(counts, "round_state")
                return 4
            end,
            IsMvM = function()
                count(counts, "mvm")
                return false
            end,
        },
        globals = {
            RealTime = function()
                count(counts, "time")
                return state.now
            end,
            TickCount = function()
                count(counts, "network_revision")
                return state.delta_tick
            end,
        },
        draw = {
            CreateFont = function()
                count(counts, "create_font")
                return 1
            end,
            SetFont = function()
                count(counts, "set_font")
            end,
            GetTextSize = function(text)
                count(counts, "measure_text")
                return #text * 7, 13
            end,
            GetScreenSize = function()
                count(counts, "screen_size")
                return 1920, 1080
            end,
            Color = function()
                count(counts, "draw_color")
            end,
            FilledRect = function()
                count(counts, "draw_rect")
                state.draw_calls = state.draw_calls + 1
            end,
            Text = function()
                count(counts, "draw_text")
                state.draw_calls = state.draw_calls + 1
            end,
        },
        gui = {
            IsMenuOpen = function()
                count(counts, "menu")
                return state.menu_open
            end,
        },
        input = {
            GetMousePos = function()
                count(counts, "mouse_position")
                return { x = 0, y = 0 }
            end,
            IsButtonPressed = function()
                count(counts, "mouse_pressed")
                return false
            end,
            IsButtonDown = function()
                count(counts, "mouse_down")
                return false
            end,
            IsButtonReleased = function()
                count(counts, "mouse_released")
                return false
            end,
        },
        mouse_left = Constants.MOUSE_LEFT,
    }
    return host, counts, state
end

--- Clears counters without replacing the table captured by host closures.
-- @param counts Mutable counter table.
local function clear_counts(counts)
    for name in pairs(counts) do
        counts[name] = nil
    end
    counts.total = 0
end

--- Measures elapsed CPU time for repeated invocations.
-- @param iterations Positive iteration count.
-- @param action Function invoked for each iteration.
-- @return number Elapsed milliseconds.
local function measure_time(iterations, action)
    collectgarbage("collect")
    local started = os.clock()
    for _ = 1, iterations do
        action()
    end
    return (os.clock() - started) * 1000
end

--- Measures transient allocation with collection paused.
-- @param iterations Positive iteration count.
-- @param action Function invoked for each iteration.
-- @return number Approximate allocated bytes per iteration.
local function measure_allocation(iterations, action)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, iterations do
        action()
    end
    local after = collectgarbage("count")
    collectgarbage("restart")
    collectgarbage("collect")
    return (after - before) * 1024 / iterations
end

--- Prints one stable name/value result line.
-- @param name Metric name.
-- @param value Metric value.
local function result(name, value)
    io.write(string.format("%-34s %s\n", name .. ":", tostring(value)))
end

local host, counts, state = make_host()
local controller = Controller.new({
    adapter = Adapter.new(host),
    renderer = assert(Renderer.new(host)),
    persistence = { save = function() return true end },
    position = Position.new(),
})

controller:on_frame_stage(Constants.FRAME_RENDER_START)
clear_counts(counts)
local capture_ms = measure_time(capture_iterations, function()
    state.now = state.now + 1 / 144
    state.delta_tick = state.delta_tick + 1
    controller:on_frame_stage(Constants.FRAME_RENDER_START)
end)
local capture_calls = counts.total / capture_iterations
local capture_loadout = (counts.loadout_weapon or 0) / capture_iterations
local capture_active = (counts.active_weapon or 0) / capture_iterations
local capture_direct = (counts.enumerate_mediguns or 0) / capture_iterations

clear_counts(counts)
local capture_bytes = measure_allocation(200, function()
    state.now = state.now + 1 / 144
    state.delta_tick = state.delta_tick + 1
    controller:on_frame_stage(Constants.FRAME_RENDER_START)
end)

clear_counts(counts)
local generation = controller.tracker.generation
local duplicate_ms = measure_time(draw_iterations, function()
    controller:on_frame_stage(Constants.FRAME_RENDER_START)
end)
local duplicate_calls = counts.total / draw_iterations
local duplicate_captures = controller.tracker.generation - generation

clear_counts(counts)
local duplicate_bytes = measure_allocation(1000, function()
    controller:on_frame_stage(Constants.FRAME_RENDER_START)
end)

clear_counts(counts)
controller:on_draw()
clear_counts(counts)
local draw_ms = measure_time(draw_iterations, function()
    controller:on_draw()
end)
local draw_calls = counts.total / draw_iterations
local draw_mouse = ((counts.mouse_position or 0)
    + (counts.mouse_pressed or 0)
    + (counts.mouse_down or 0)
    + (counts.mouse_released or 0)) / draw_iterations

clear_counts(counts)
local draw_bytes = measure_allocation(1000, function()
    controller:on_draw()
end)

result("Lua", _VERSION)
result("roster players", Constants.MAX_PLAYERS)
result("capture iterations", capture_iterations)
result("capture total ms", string.format("%.3f", capture_ms))
result("capture us/iteration", string.format(
    "%.3f",
    capture_ms * 1000 / capture_iterations
))
result("capture boundary calls/iteration", string.format("%.1f", capture_calls))
result("capture active reads/iteration", string.format("%.1f", capture_active))
result("capture loadout reads/iteration", string.format("%.1f", capture_loadout))
result("capture direct enums/iteration", string.format("%.1f", capture_direct))
result("capture allocated bytes/iteration", string.format("%.1f", capture_bytes))
result("same-tick fallback iterations", draw_iterations)
result("same-tick fallback total ms", string.format("%.3f", duplicate_ms))
result("same-tick boundary calls/iteration", string.format(
    "%.1f",
    duplicate_calls
))
result("same-tick captures", duplicate_captures)
result("same-tick allocated bytes/iteration", string.format(
    "%.1f",
    duplicate_bytes
))
result("Draw iterations", draw_iterations)
result("Draw total ms", string.format("%.3f", draw_ms))
result("Draw us/iteration", string.format(
    "%.3f",
    draw_ms * 1000 / draw_iterations
))
result("Draw boundary calls/iteration", string.format("%.1f", draw_calls))
result("Draw mouse reads/iteration", string.format("%.1f", draw_mouse))
result("Draw allocated bytes/iteration", string.format("%.1f", draw_bytes))
