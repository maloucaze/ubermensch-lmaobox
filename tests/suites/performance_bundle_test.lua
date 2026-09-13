local Harness = require("support.harness")
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
    Harness.falsy(string.find(selection, "table.sort", 1, true))
    Harness.falsy(string.find(tracking, "table.sort", 1, true))
    Harness.falsy(string.find(controller, "FindByClass", 1, true))
    Harness.falsy(string.find(controller, "GetPlayerResources", 1, true))
    Harness.falsy(string.find(controller, "io.open", 1, true))
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
