local Harness = require("support.harness")
local Adapter = require("ubermensch.adapter")
local Constants = require("ubermensch.constants")
local Fakes = require("support.fakes")

local function read_file(path)
    local handle = assert(io.open(path, "rb"))
    local content = handle:read("*a")
    handle:close()
    return content
end

Harness.test("hot-path modules do not sort candidates or acquire in Draw", function()
    local selection = read_file("src/ubermensch/selection.lua")
    local tracking = read_file("src/ubermensch/tracking.lua")
    local controller = read_file("src/ubermensch/controller.lua")
    local adapter = read_file("src/ubermensch/adapter.lua")
    local safe = read_file("src/ubermensch/safe.lua")
    Harness.falsy(string.find(selection, "table.sort", 1, true))
    Harness.falsy(string.find(tracking, "table.sort", 1, true))
    Harness.falsy(string.find(controller, "FindByClass", 1, true))
    Harness.falsy(string.find(controller, "GetPlayerResources", 1, true))
    Harness.falsy(string.find(controller, "io.open", 1, true))
    Harness.falsy(string.find(adapter, '"CWeaponMedigun"', 1, true))
    Harness.falsy(string.find(safe, "pcall(function", 1, true))
end)

Harness.test("full roster probes weapon handles only for possible Medics", function()
    local players = {}
    local rows = {}
    local userids = {}
    local weapons = {}
    for index = 1, Constants.MAX_PLAYERS do
        local is_medic = index == 2 or index == 3
        local weapon_options
        local weapon
        if is_medic then
            weapon_options = {
                index = 100 + index,
                item = index == 2 and 29 or 35,
                nonlocal_charge = index == 2 and 0.65 or 0.55,
                deployed = false,
            }
            weapon = Fakes.weapon(weapon_options)
            weapons[#weapons + 1] = weapon
        end
        local player = Fakes.player({
            index = index,
            team = index % 2 == 0 and Constants.TEAM.RED
                or Constants.TEAM.BLU,
            class = is_medic and Constants.MEDIC_CLASS or 1,
            alive = true,
            loadout_weapon = weapon,
            active_weapon = weapon,
        })
        if weapon_options ~= nil then
            weapon_options.owner = player
        end
        players[index] = player
        userids[index] = 1000 + index
        rows[index] = {
            connected = true,
            valid = true,
            alive = true,
            team = player.options.team,
            userid = userids[index],
            class = player.options.class,
            charge = is_medic and 50 or 0,
        }
    end
    local host = Fakes.host({
        players = players,
        local_player = players[1],
        userids = userids,
        resource = Fakes.resource(rows),
    })
    local snapshot = Adapter.new(host):capture()
    local active_reads = 0
    local loadout_reads = 0
    for index = 1, #players do
        active_reads = active_reads + (players[index].options.active_reads or 0)
        loadout_reads = loadout_reads
            + #(players[index].options.loadout_slots or {})
    end
    Harness.equal(snapshot.observed_weapon_count, 2)
    Harness.equal(active_reads, 2)
    Harness.equal(loadout_reads, 2)
    Harness.equal(weapons[1].options.medigun_reads, 1)
    Harness.equal(weapons[2].options.medigun_reads, 1)
    Harness.same_table(host.state.find_by_class_calls, { "CTFPlayer" })
end)

Harness.test("generated bundle is self-contained under fake globals", function()
    local content = read_file("ubermensch.lua")
    Harness.contains(content, "local module_loaders = {}")
    Harness.falsy(string.find(content, "package.path", 1, true))
    Harness.falsy(string.find(content, "validation.recorder", 1, true))
    Harness.falsy(string.find(content, "session_start", 1, true))
    local host = Fakes.host({})
    local environment = setmetatable({
        entities = host.entities,
        client = host.client,
        engine = host.engine,
        gamerules = host.gamerules,
        globals = host.globals,
        draw = host.draw,
        gui = host.gui,
        input = host.input,
        callbacks = host.callbacks,
        filesystem = host.filesystem,
        io = host.io,
        os = host.os,
        MOUSE_LEFT = 107,
        print = host.print_function,
    }, { __index = _G })
    local chunk, failure
    if _VERSION == "Lua 5.1" then
        chunk, failure = _G.loadstring(content, "@ubermensch.lua")
        if chunk ~= nil then _G.setfenv(chunk, environment) end
    else
        chunk, failure = load(content, "@ubermensch.lua", "t", environment)
    end
    Harness.truthy(chunk ~= nil, failure)
    chunk()
    Harness.truthy(host.state.callbacks.Draw ~= nil)
    host.state.callbacks.Unload()
end)

Harness.test("generated validation bundle is self-contained and records", function()
    local content = read_file("ubermensch_validation.lua")
    Harness.contains(content, "local module_loaders = {}")
    Harness.contains(content, 'module_loaders["validation.recorder"]')
    Harness.falsy(string.find(content, "package.path", 1, true))
    local file_api, memory = Fakes.memory_io()
    local host = Fakes.host({ io = file_api })
    local environment = setmetatable({
        entities = host.entities,
        client = host.client,
        engine = host.engine,
        gamerules = host.gamerules,
        globals = host.globals,
        draw = host.draw,
        gui = host.gui,
        input = host.input,
        callbacks = host.callbacks,
        filesystem = host.filesystem,
        io = host.io,
        os = host.os,
        MOUSE_LEFT = 107,
        KEY_F8 = 99,
        E_ButtonCode = { KEY_F8 = 99 },
        print = host.print_function,
    }, { __index = _G })
    local chunk, failure
    if _VERSION == "Lua 5.1" then
        chunk, failure = _G.loadstring(content, "@ubermensch_validation.lua")
        if chunk ~= nil then _G.setfenv(chunk, environment) end
    else
        chunk, failure = load(
            content,
            "@ubermensch_validation.lua",
            "t",
            environment
        )
    end
    Harness.truthy(chunk ~= nil, failure)
    chunk()
    Harness.truthy(host.state.callbacks.Draw ~= nil)
    host.state.callbacks.Unload()
    local recorded = false
    for _, log in pairs(memory.files) do
        if string.find(log, '"type":"session_start"', 1, true) then
            recorded = true
        end
    end
    Harness.truthy(recorded)
end)
