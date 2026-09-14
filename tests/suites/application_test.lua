local Harness = require("support.harness")
local App = require("ubermensch.app")
local Constants = require("ubermensch.constants")
local Fakes = require("support.fakes")

Harness.test("startup reports every missing capability once", function()
    local messages = {}
    local app = App.start({
        print_function = function(message) messages[#messages + 1] = message end,
    })
    Harness.is_nil(app)
    Harness.equal(messages[1], "[Ubermensch] required LMAOBox API unavailable:")
    Harness.truthy(#messages > 20)
    local seen = {}
    for i = 2, #messages do
        Harness.contains(messages[i], "[Ubermensch] missing: ")
        Harness.falsy(seen[messages[i]])
        seen[messages[i]] = true
    end
end)

Harness.test("capability validation accepts callable proxy members", function()
    local host = Fakes.host({})
    host.entities.GetLocalPlayer = setmetatable({}, {
        __call = function() return nil end,
    })
    Harness.equal(#App.missing_capabilities(host), 0)
end)

Harness.test("stable callback IDs register and unload cleanly", function()
    local host = Fakes.host({})
    local app = App.start(host)
    Harness.truthy(app ~= nil)
    Harness.same_table(host.state.registered, {
        "FrameStageNotify:" .. Constants.CALLBACK.frame,
        "FireGameEvent:" .. Constants.CALLBACK.event,
        "Draw:" .. Constants.CALLBACK.draw,
        "Unload:" .. Constants.CALLBACK.unload,
    })
    Harness.same_table(host.state.prints, {
        "[Ubermensch] loaded v" .. Constants.VERSION,
    })
    Harness.falsy(string.find(Constants.CALLBACK.frame, "v2", 1, true))
    Harness.truthy(host.state.callbacks.Unload ~= nil)
    host.state.unregistered = {}
    Fakes.unload(host)
    Harness.is_nil(host.state.callbacks.Draw)
    Harness.is_nil(host.state.callbacks.FrameStageNotify)
    Harness.equal(#host.state.unregistered, 0)
    Harness.truthy(app.controller.unloaded)
end)

Harness.test("callback registration is not hidden inside a protected call", function()
    local host = Fakes.host({})
    local original_pcall = pcall
    local ok, result = original_pcall(function()
        _G.pcall = function(action, ...)
            if action == host.callbacks.Register then
                return false, "protected registration loses script ownership"
            end
            return original_pcall(action, ...)
        end
        return App.start(host)
    end)
    _G.pcall = original_pcall
    if not ok then
        error(result, 0)
    end
    Harness.truthy(result ~= nil)
    Harness.equal(#host.state.registered, 4)
    result.stop()
end)

Harness.test("host unload never unregisters callbacks during dispatch", function()
    local host = Fakes.host({})
    local app = App.start(host)
    host.state.unregistered = {}
    Fakes.unload(host)
    Harness.truthy(app.controller.unloaded)
    Harness.equal(#host.state.unregistered, 0)
    Harness.same_table(host.state.prints, {
        "[Ubermensch] loaded v" .. Constants.VERSION,
    })
end)

Harness.test("explicit stop unregisters every callback once", function()
    local host = Fakes.host({})
    local app = App.start(host)
    host.state.unregistered = {}
    app.stop()
    Harness.same_table(host.state.unregistered, {
        "FrameStageNotify:" .. Constants.CALLBACK.frame,
        "FireGameEvent:" .. Constants.CALLBACK.event,
        "Draw:" .. Constants.CALLBACK.draw,
        "Unload:" .. Constants.CALLBACK.unload,
    })
    app.stop()
    Harness.equal(#host.state.unregistered, 4)
end)

Harness.test("optional persistence failure does not prevent startup", function()
    local host = Fakes.host({ io = { open = function() error("denied") end } })
    local app = App.start(host)
    Harness.truthy(app ~= nil)
    Harness.same_table(host.state.prints, {
        "[Ubermensch] loaded v" .. Constants.VERSION,
    })
    app.stop()
end)

Harness.test("unexpected callback error disables only that path", function()
    local host = Fakes.host({})
    local app = App.start(host)
    app.controller.adapter.capture = function() error("boom") end
    host.state.callbacks.FrameStageNotify(4)
    Harness.falsy(app.paths.frame)
    Harness.truthy(app.paths.draw)
    Harness.equal(#host.state.prints, 2)
    Harness.contains(host.state.prints[2], "frame callback disabled:")
    host.state.callbacks.FrameStageNotify(4)
    Harness.equal(#host.state.prints, 2)
    app.stop()
end)

Harness.test("HUD startup diagnostics are changing bounded and stop after render", function()
    local host = Fakes.host({})
    local app = App.start(host)
    app.controller.on_draw = function()
        return false, "local team unavailable"
    end
    host.state.callbacks.Draw()
    host.state.callbacks.Draw()
    Harness.equal(#host.state.prints, 2)
    Harness.equal(
        host.state.prints[2],
        "[Ubermensch] HUD waiting: local team unavailable"
    )

    app.controller.on_draw = function()
        return true, nil
    end
    host.state.callbacks.Draw()
    Harness.equal(host.state.prints[3], "[Ubermensch] HUD active")

    app.controller.on_draw = function()
        return false, "later expected visibility change"
    end
    host.state.callbacks.Draw()
    Harness.equal(#host.state.prints, 3)
    app.stop()
end)

Harness.test("missing snapshots distinguish absent and mismatched frame callbacks", function()
    local host = Fakes.host({})
    local app = App.start(host)
    host.state.callbacks.Draw()
    Harness.equal(
        host.state.prints[2],
        "[Ubermensch] HUD waiting: network snapshot unavailable; "
            .. "FrameStageNotify has not fired"
    )

    host.state.callbacks.FrameStageNotify(3)
    host.state.callbacks.Draw()
    Harness.equal(
        host.state.prints[3],
        "[Ubermensch] HUD waiting: network snapshot unavailable; "
            .. "last FrameStageNotify stage 3, expected 4"
    )
    app.stop()
end)

Harness.test("application passes the live frame-stage enum to the controller", function()
    local host = Fakes.host({})
    host.frame_net_update_end = 14
    host.frame_render_start = 15
    local app = App.start(host)
    host.state.callbacks.FrameStageNotify(4)
    Harness.is_nil(app.controller.latest_snapshot)
    host.state.callbacks.FrameStageNotify(14)
    Harness.truthy(app.controller.latest_snapshot ~= nil)
    app.stop()
end)

Harness.test("render-start fallback is reported once and produces a snapshot", function()
    local host = Fakes.host({})
    local app = App.start(host)
    host.state.callbacks.FrameStageNotify(5)
    Harness.truthy(app.controller.latest_snapshot ~= nil)
    Harness.equal(
        host.state.prints[2],
        "[Ubermensch] compatibility: FRAME_NET_UPDATE_END unavailable; "
            .. "using FRAME_RENDER_START"
    )
    host.state.callbacks.FrameStageNotify(5)
    Harness.equal(#host.state.prints, 2)
    app.stop()
end)
