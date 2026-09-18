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
    host.state.casual = false
    host.state.competitive = true
    host.state.convars.sv_visiblemaxplayers = 12
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
    Harness.contains(output, '"recorder_version":"1.6.0"')
    Harness.contains(output, '"type":"event"')
    Harness.contains(output, '"name":"player_chargedeployed"')
    Harness.contains(output, '"type":"decision"')
    Harness.contains(output, '"self_mode":false')
    Harness.contains(output, '"team_counts"')
    Harness.contains(output, '"configured_player_slots"')
    Harness.contains(output, '"2 vs. 1"')
    Harness.contains(output, '"type":"selection_checkpoint"')
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

Harness.test("validation decisions include off-class format and color evidence", function()
    local host, memory = Fakes.validation_host()
    local sniper = Fakes.player({
        index = 4,
        team = 3,
        class = 2,
        alive = false,
    })
    host.state.players[4] = sniper
    host.state.userids[4] = 40
    host.state.casual = false
    host.state.competitive = true
    host.state.convars.sv_visiblemaxplayers = 12
    host.state.resource = Fakes.resource({
        [1] = { connected = true, valid = true, alive = true, team = 2, userid = 10, class = 1, charge = 0 },
        [2] = { connected = true, valid = true, alive = true, team = 2, userid = 20, class = 5, charge = 75 },
        [3] = { connected = true, valid = true, alive = true, team = 3, userid = 30, class = 5, charge = 50 },
        [4] = { connected = true, valid = true, alive = false, team = 3, userid = 40, class = 2, charge = 0 },
    })
    local recorder = Recorder.new(host)
    local app = App.start(host, {
        observer = recorder,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    host.state.callbacks.FrameStageNotify(4)
    host.state.callbacks.Draw()
    host.state.callbacks.Unload()

    local output = all_output(memory)
    Harness.contains(output, '"format":"6v6"')
    Harness.contains(output, '"Off-class: SNIPER"')
    Harness.contains(output, '"offclass_segments"')
    Harness.contains(output, '"team_player_counts"')
end)

Harness.test("verbose adapter diagnostics follow their fixed cadence", function()
    local host = Fakes.validation_host()
    local recorder = Recorder.new(host, {
        detail_interval = 0.1,
        flush_interval = 100,
    })
    local app = App.start(host, {
        observer = recorder,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    Harness.truthy(recorder:wants_diagnostics())
    host.state.callbacks.FrameStageNotify(4)
    Harness.falsy(recorder:wants_diagnostics())
    host.state.now = host.state.now + 0.099
    Harness.falsy(recorder:wants_diagnostics())
    host.state.now = host.state.now + 0.002
    Harness.truthy(recorder:wants_diagnostics())
    host.state.callbacks.Unload()
end)

Harness.test("selection without diagnostics forces the next raw sample", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, {
        detail_interval = 100,
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
    host.state.players[2].options.alive = false
    host.state.callbacks.FrameStageNotify(4)
    Harness.truthy(recorder.force_diagnostics)
    host.state.now = 10.02
    host.state.callbacks.FrameStageNotify(4)
    Harness.falsy(recorder.force_diagnostics)
    host.state.callbacks.Unload()

    local output = all_output(memory)
    Harness.contains(output, '"adapter_diagnostics_available":false')
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

Harness.test("held F8 input records one marker per physical press", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, { flush_interval = 100 })
    local app = App.start(host, {
        observer = recorder,
        adapter_diagnostics = true,
    })
    Harness.truthy(app ~= nil)
    host.state.callbacks.FrameStageNotify(4)

    host.state.key_pressed[99] = true
    host.state.callbacks.Draw()
    host.state.callbacks.Draw()
    host.state.callbacks.Draw()
    host.state.key_pressed[99] = false
    host.state.callbacks.Draw()
    host.state.key_pressed[99] = true
    host.state.callbacks.Draw()
    host.state.callbacks.Draw()
    host.state.callbacks.Unload()

    local output = all_output(memory)
    Harness.equal(count_occurrences(output, '"type":"marker"'), 2)
    Harness.equal(count_occurrences(output, '"number":1'), 1)
    Harness.equal(count_occurrences(output, '"number":2'), 1)
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
    Harness.equal(count_occurrences(output, '"type":"selection_checkpoint"'), 1)
end)

Harness.test("capture route alternation is aggregated without delta noise", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, {
        detail_interval = 100,
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
    host.state.callbacks.FrameStageNotify(5)
    host.state.callbacks.FrameStageNotify(5)
    host.state.callbacks.Unload()

    local output = all_output(memory)
    Harness.equal(count_occurrences(output, '"type":"decision"'), 1)
    Harness.equal(count_occurrences(output, '"type":"context"'), 1)
    Harness.equal(count_occurrences(output, '"type":"selection_checkpoint"'), 1)
    Harness.contains(
        output,
        '"capture_sources":{"fallback":1,"other":0,"preferred":1}'
    )
end)

Harness.test("Draw links a logged decision to the capture it consumed", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, {
        detail_interval = 100,
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
    host.state.callbacks.FrameStageNotify(5)
    host.state.callbacks.FrameStageNotify(5)
    host.state.callbacks.Draw()
    host.state.callbacks.Unload()

    local output = all_output(memory)
    Harness.contains(
        output,
        '"consumed_capture_sequence":2,"decision_sequence":1'
    )
end)

Harness.test("selection changes receive immediate full evidence", function()
    local host, memory = Fakes.validation_host()
    local recorder = Recorder.new(host, {
        detail_interval = 100,
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
    host.state.players[2].options.alive = false
    host.state.callbacks.FrameStageNotify(4)
    host.state.callbacks.Unload()

    local output = all_output(memory)
    Harness.equal(count_occurrences(output, '"type":"selection_checkpoint"'), 2)
    Harness.contains(output, '"current_alive":false')
    Harness.contains(output, '"previous_selection"')
    Harness.contains(output, '"state":"dead"')
    Harness.contains(output, '"family":"DEAD MED"')
    Harness.contains(output, '"dead_candidates"')
    Harness.contains(output, '"died_at":10')
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
