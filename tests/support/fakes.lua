local Fakes = {}

local function maybe_error(options, name)
    if options[name .. "_error"] then
        error(name .. " failure")
    end
end

function Fakes.weapon(options)
    options = options or {}
    local weapon = {}
    function weapon:GetIndex()
        return options.index or 101
    end
    function weapon:IsValid()
        return options.valid ~= false
    end
    function weapon:IsDormant()
        maybe_error(options, "dormant")
        return options.dormant == true
    end
    function weapon:IsMedigun()
        options.medigun_reads = (options.medigun_reads or 0) + 1
        return options.is_medigun ~= false
    end
    function weapon:GetPropEntity(property)
        if property == "m_hOwner" then
            maybe_error(options, "owner")
            return options.owner
        end
    end
    function weapon:GetPropInt(...)
        maybe_error(options, "family")
        local arguments = { ... }
        if arguments[#arguments] == "m_iItemDefinitionIndex" then
            return options.item
        end
    end
    function weapon:GetPropFloat(data_table, property)
        options.float_reads = options.float_reads or {}
        options.float_reads[#options.float_reads + 1] = data_table .. "." .. property
        maybe_error(options, "charge")
        if data_table == "LocalTFWeaponMedigunData" then
            return options.local_charge
        end
        if data_table == "NonLocalTFWeaponMedigunData" then
            return options.nonlocal_charge
        end
        return options.bare_charge
    end
    function weapon:GetPropBool(property)
        if property == "m_bChargeRelease" then
            maybe_error(options, "deployment")
            return options.deployed
        end
        if property == "m_bHolstered" then
            maybe_error(options, "holstered")
            return options.holstered
        end
    end
    weapon.options = options
    return weapon
end

function Fakes.player(options)
    options = options or {}
    local player = {}
    function player:GetIndex()
        return options.index
    end
    function player:IsValid()
        return options.valid ~= false
    end
    function player:IsDormant()
        maybe_error(options, "dormant")
        return options.dormant == true
    end
    function player:GetTeamNumber()
        maybe_error(options, "team")
        return options.team
    end
    function player:GetPropInt(...)
        maybe_error(options, "class")
        return options.class
    end
    function player:IsAlive()
        maybe_error(options, "alive")
        return options.alive
    end
    function player:GetPropEntity(property)
        if property == "m_hActiveWeapon" then
            options.active_reads = (options.active_reads or 0) + 1
            maybe_error(options, "active")
            return options.active_weapon
        end
    end
    function player:GetEntityForLoadoutSlot(slot)
        options.loadout_slots = options.loadout_slots or {}
        options.loadout_slots[#options.loadout_slots + 1] = slot
        maybe_error(options, "loadout")
        return options.loadout_weapon
    end
    player.options = options
    return player
end

function Fakes.resource(rows, failures)
    rows = rows or {}
    failures = failures or {}
    local resource = {}
    local mapping = {
        m_bConnected = "connected",
        m_bValid = "valid",
        m_bAlive = "alive",
        m_iTeam = "team",
        m_iUserID = "userid",
        m_iPlayerClass = "class",
        m_iChargeLevel = "charge",
    }
    local function values(property)
        if failures[property] then
            error(property .. " failure")
        end
        local result = {}
        for index = 1, 32 do
            local row = rows[index]
            local field = mapping[property]
            if row ~= nil then
                result[index + 1] = row[field]
            elseif field == "connected" or field == "valid" or field == "alive" then
                result[index + 1] = false
            else
                result[index + 1] = 0
            end
        end
        return result
    end
    function resource:GetPropDataTableBool(property)
        return values(property)
    end
    function resource:GetPropDataTableInt(property)
        return values(property)
    end
    return resource
end

function Fakes.event(name, values)
    values = values or {}
    local event = {}
    function event:GetName()
        return name
    end
    function event:GetInt(key)
        return values[key]
    end
    function event:GetBool(key)
        return values[key]
    end
    function event:GetString(key)
        return values[key]
    end
    return event
end

function Fakes.memory_io()
    local state = {
        files = {},
        opens = {},
        closes = 0,
        flushes = 0,
        writes = 0,
    }
    local api = {}
    function api.open(path, mode)
        state.opens[#state.opens + 1] = { path = path, mode = mode }
        if mode == "r" or mode == "rb" then
            local content = state.files[path]
            if content == nil then
                return nil
            end
            return {
                read = function() return content end,
                close = function() state.closes = state.closes + 1 end,
            }
        end
        if mode ~= "w" and mode ~= "wb" then
            return nil
        end
        state.files[path] = ""
        local handle = {}
        function handle:write(content)
            state.writes = state.writes + 1
            state.files[path] = state.files[path] .. content
            return true
        end
        function handle:flush()
            state.flushes = state.flushes + 1
            return true
        end
        function handle:close()
            state.closes = state.closes + 1
            return true
        end
        return handle
    end
    return api, state
end

function Fakes.host(options)
    options = options or {}
    local state = {
        now = options.now or 10,
        map = options.map == nil and "cp_badlands" or options.map,
        round_state = options.round_state or 4,
        mvm = options.mvm == true,
        console = false,
        game_ui = false,
        players = options.players or {},
        direct_weapons = options.direct_weapons or {},
        resource = options.resource or Fakes.resource({}),
        local_player = options.local_player,
        userids = options.userids or {},
        callbacks = {},
        registered = {},
        unregistered = {},
        prints = {},
        draw_calls = {},
        acquisition_calls = 0,
        mouse = { x = 0, y = 0 },
        menu_open = false,
        pressed = false,
        down = false,
        released = false,
        key_pressed = {},
        font_creations = 0,
        host_unloading = false,
        delta_tick = options.delta_tick,
        find_by_class_calls = {},
        input_calls = {},
    }
    local host = {}

    local function require_integer_draw_arguments(...)
        local arguments = { ... }
        for i = 1, #arguments do
            local value = arguments[i]
            if type(value) == "number" and value ~= math.floor(value) then
                error("number has no integer representation")
            end
        end
    end
    host.entities = {
        GetLocalPlayer = function()
            state.acquisition_calls = state.acquisition_calls + 1
            return state.local_player
        end,
        GetPlayerResources = function()
            state.acquisition_calls = state.acquisition_calls + 1
            return state.resource
        end,
        FindByClass = function(class)
            state.acquisition_calls = state.acquisition_calls + 1
            state.find_by_class_calls[#state.find_by_class_calls + 1] = class
            if class == "CTFPlayer" then
                return state.players
            end
            return state.direct_weapons
        end,
    }
    host.client = {
        GetPlayerInfo = function(index)
            local userid = state.userids[index]
            return userid ~= nil and { UserID = userid } or nil
        end,
    }
    if options.delta_tick ~= nil then
        host.clientstate = {
            GetDeltaTick = function()
                state.network_revision_calls =
                    (state.network_revision_calls or 0) + 1
                return state.delta_tick
            end,
        }
    end
    host.engine = {
        GetMapName = function() return state.map end,
        Con_IsVisible = function() return state.console end,
        IsGameUIVisible = function() return state.game_ui end,
        GetGameDir = function() return options.game_dir or "C:\\tf2" end,
    }
    host.gamerules = {
        IsMvM = function() return state.mvm end,
        GetRoundState = function() return state.round_state end,
    }
    host.globals = {
        RealTime = function() return state.now end,
    }
    host.draw = {
        CreateFont = function(...)
            state.font_creations = state.font_creations + 1
            state.font_arguments = { ... }
            return 7
        end,
        SetFont = function(...) state.draw_calls[#state.draw_calls + 1] = { "font", ... } end,
        GetTextSize = function(text) return #text * 7, 13 end,
        GetScreenSize = function() return 1920, 1080 end,
        Color = function(...)
            require_integer_draw_arguments(...)
            state.draw_calls[#state.draw_calls + 1] = { "color", ... }
        end,
        FilledRect = function(...)
            require_integer_draw_arguments(...)
            state.draw_calls[#state.draw_calls + 1] = { "rect", ... }
        end,
        Text = function(...)
            require_integer_draw_arguments(...)
            state.draw_calls[#state.draw_calls + 1] = { "text", ... }
        end,
    }
    host.gui = { IsMenuOpen = function() return state.menu_open end }
    host.input = {
        GetMousePos = function()
            state.input_calls.mouse = (state.input_calls.mouse or 0) + 1
            return state.mouse
        end,
        IsButtonPressed = function(button)
            state.input_calls.pressed = (state.input_calls.pressed or 0) + 1
            state.button = button
            if button == 107 then
                return state.pressed
            end
            return state.key_pressed[button] == true
        end,
        IsButtonDown = function(button)
            state.input_calls.down = (state.input_calls.down or 0) + 1
            state.button = button
            return state.down
        end,
        IsButtonReleased = function(button)
            state.input_calls.released = (state.input_calls.released or 0) + 1
            state.button = button
            return state.released
        end,
    }
    host.callbacks = {
        Register = function(name, identifier, callback)
            state.callbacks[name] = callback
            state.registered[#state.registered + 1] = name .. ":" .. identifier
            return true
        end,
        Unregister = function(name, identifier)
            if state.host_unloading then
                error("callback unregistration during host Unload")
            end
            state.callbacks[name] = nil
            state.unregistered[#state.unregistered + 1] = name .. ":" .. identifier
            return true
        end,
    }
    host.filesystem = { CreateDirectory = function() return true, "C:\\tf2\\ubermensch-lmaobox" end }
    host.io = options.io or { open = function() return nil end }
    host.os = options.os or { getenv = function() return "C:\\Users\\Test\\AppData\\Local" end }
    host.print_function = function(message) state.prints[#state.prints + 1] = message end
    host.mouse_left = 107
    host.state = state
    return host
end

--- Simulates LMAOBox's script-owned Unload dispatch and automatic teardown.
-- The fake rejects explicit callback removal during dispatch to preserve the
-- live crash regression, then removes the script's callbacks as the host does.
-- @param host Fake host returned by `Fakes.host`.
function Fakes.unload(host)
    local state = host.state
    local callback = state.callbacks.Unload
    if callback == nil then
        return
    end
    state.host_unloading = true
    local ok, failure = pcall(callback)
    state.host_unloading = false
    state.callbacks = {}
    if not ok then
        error(failure, 0)
    end
end

function Fakes.validation_host()
    local ally_options = {
        index = 102,
        item = 29,
        nonlocal_charge = 0.75,
        deployed = false,
        holstered = false,
    }
    local enemy_options = {
        index = 103,
        item = 35,
        nonlocal_charge = 0.50,
        deployed = false,
        holstered = true,
    }
    local local_player = Fakes.player({
        index = 1,
        team = 2,
        class = 1,
        alive = true,
    })
    local ally = Fakes.player({
        index = 2,
        team = 2,
        class = 5,
        alive = true,
        loadout_weapon = Fakes.weapon(ally_options),
    })
    local enemy = Fakes.player({
        index = 3,
        team = 3,
        class = 5,
        alive = true,
        loadout_weapon = Fakes.weapon(enemy_options),
    })
    ally_options.owner = ally
    enemy_options.owner = enemy
    local file_api, memory = Fakes.memory_io()
    local host = Fakes.host({
        io = file_api,
        players = { local_player, ally, enemy },
        local_player = local_player,
        userids = { [1] = 10, [2] = 20, [3] = 30 },
        resource = Fakes.resource({
            [1] = {
                connected = true,
                valid = true,
                alive = true,
                team = 2,
                userid = 10,
                class = 1,
                charge = 0,
            },
            [2] = {
                connected = true,
                valid = true,
                alive = true,
                team = 2,
                userid = 20,
                class = 5,
                charge = 75,
            },
            [3] = {
                connected = true,
                valid = true,
                alive = true,
                team = 3,
                userid = 30,
                class = 5,
                charge = 50,
            },
        }),
    })
    host.lua_version = "Lua test"
    host.key_f8 = 99
    return host, memory, ally_options, enemy_options
end

return Fakes
