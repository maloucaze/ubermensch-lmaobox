local App = require("ubermensch.app")
local Fakes = require("support.fakes")
local Harness = require("support.harness")
local Recorder = require("validation.recorder")

local function count_occurrences(text, fragment)
    local count = 0
    local position = 1
    while true do
        local found = string.find(text, fragment, position, true)
        if found == nil then
            return count
        end
        count = count + 1
        position = found + #fragment
    end
end

local function all_output(memory)
    local parts = {}
    for _, content in pairs(memory.files) do
        parts[#parts + 1] = content
    end
    return table.concat(parts, "\n")
end

Harness.test("validation runtime records real decisions events Draw and marker", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host)
    local app = App.start(host, {
        observer = recorder,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    host.state.callbacks.FireGameEvent(
        Fakes.event("player_chargedeployed", { userid = 30 })
    )
    host.state.callbacks.FireGameEvent(
        Fakes.event("player_say", { userid = 30 })
    )
    host.state.callbacks.FrameStageNotify(4)
    host.state.key_pressed[99] = true
    host.state.callbacks.Draw()
    host.state.key_pressed[99] = false
    host.state.now = 12.1
    host.state.callbacks.FrameStageNotify(4)
    host.state.callbacks.Draw()
    host.state.callbacks.Unload()

    local output = all_output(memory)
    Harness.contains(output, '"type":"session_start"')
    Harness.contains(output, '"type":"event"')
    Harness.contains(output, '"name":"player_chargedeployed"')
    Harness.contains(output, '"type":"decision"')
    Harness.contains(output, '"type":"draw"')
    Harness.contains(output, '"type":"marker"')
    Harness.contains(output, '"type":"weapon"')
    Harness.contains(output, '"type":"tracker"')
    Harness.contains(output, '"uid":"U')
    Harness.falsy(string.find(output, '"userid":30', 1, true))
    Harness.falsy(string.find(output, "SteamID", 1, true))
    Harness.contains(output, '"type":"session_end"')
    Harness.falsy(string.find(output, "player_say", 1, true))
end)

Harness.test("Draw appends evidence without flushing files", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, { flush_interval = 100 })
    local app = App.start(host, {
        observer = recorder,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    host.state.callbacks.FrameStageNotify(4)
    local flushes = memory.flushes
    host.state.callbacks.Draw()
    Harness.equal(memory.flushes, flushes)
    host.state.callbacks.Unload()
end)

Harness.test("observer failure is isolated from product capture and Draw", function()
    local host = Fakes.validation_host()
    local observer = {
        on_capture = function() error("observer boom") end,
    }
    local app = App.start(host, {
        observer = observer,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    host.state.callbacks.FrameStageNotify(4)
    Harness.truthy(app.paths.frame)
    Harness.truthy(app.controller.latest_prepared ~= nil)
    host.state.callbacks.Draw()
    Harness.truthy(app.paths.draw)
    Harness.contains(
        host.state.prints[2],
        "[Ubermensch Validation] observer disabled in on_capture:"
    )
    host.state.callbacks.Unload()
end)

Harness.test("unchanged captures are delta suppressed", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, {
        detail_interval = 10,
        flush_interval = 100,
        checkpoint_interval = 100,
        heartbeat_interval = 100,
    })
    local app = App.start(host, {
        observer = recorder,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    host.state.callbacks.FrameStageNotify(4)
    host.state.now = 10.01
    host.state.callbacks.FrameStageNotify(4)
    host.state.callbacks.Unload()
    local output = all_output(memory)
    Harness.equal(count_occurrences(output, '"type":"decision"'), 1)
    Harness.equal(count_occurrences(output, '"type":"context"'), 1)
end)

Harness.test("heartbeats checkpoints and callback faults are durable", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, {
        flush_interval = 1,
        heartbeat_interval = 2,
        checkpoint_interval = 3,
    })
    local app = App.start(host, {
        observer = recorder,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    host.state.callbacks.FrameStageNotify(4)
    host.state.now = 14
    host.state.map = "pl_upward"
    host.state.callbacks.FrameStageNotify(4)
    recorder:on_callback_fault("event", "synthetic failure")
    host.state.callbacks.Unload()
    local output = all_output(memory)
    Harness.contains(output, '"type":"heartbeat"')
    Harness.contains(output, '"type":"checkpoint"')
    Harness.contains(output, '"resource_summary"')
    Harness.contains(output, '"type":"callback_fault"')
    Harness.contains(output, '"type":"map_transition"')
    Harness.contains(output, "synthetic failure")
end)
