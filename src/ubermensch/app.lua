--- Application composition, capability validation, callbacks, and cleanup.
-- @module ubermensch.app

local Adapter = require("ubermensch.adapter")
local Constants = require("ubermensch.constants")
local Controller = require("ubermensch.controller")
local Persistence = require("ubermensch.persistence")
local Position = require("ubermensch.position")
local Renderer = require("ubermensch.renderer")
local Safe = require("ubermensch.safe")

local App = {}

local REQUIRED = {
    { "entities.GetLocalPlayer", "entities", "GetLocalPlayer" },
    { "entities.FindByClass", "entities", "FindByClass" },
    { "entities.GetPlayerResources", "entities", "GetPlayerResources" },
    { "client.GetPlayerInfo", "client", "GetPlayerInfo" },
    { "engine.GetMapName", "engine", "GetMapName" },
    { "engine.Con_IsVisible", "engine", "Con_IsVisible" },
    { "engine.IsGameUIVisible", "engine", "IsGameUIVisible" },
    { "gamerules.IsMvM", "gamerules", "IsMvM" },
    { "gamerules.GetRoundState", "gamerules", "GetRoundState" },
    { "globals.RealTime", "globals", "RealTime" },
    { "draw.CreateFont", "draw", "CreateFont" },
    { "draw.SetFont", "draw", "SetFont" },
    { "draw.GetTextSize", "draw", "GetTextSize" },
    { "draw.GetScreenSize", "draw", "GetScreenSize" },
    { "draw.Color", "draw", "Color" },
    { "draw.FilledRect", "draw", "FilledRect" },
    { "draw.Text", "draw", "Text" },
    { "gui.IsMenuOpen", "gui", "IsMenuOpen" },
    { "input.GetMousePos", "input", "GetMousePos" },
    { "input.IsButtonPressed", "input", "IsButtonPressed" },
    { "input.IsButtonDown", "input", "IsButtonDown" },
    { "input.IsButtonReleased", "input", "IsButtonReleased" },
    { "callbacks.Register", "callbacks", "Register" },
    { "callbacks.Unregister", "callbacks", "Unregister" },
}

--- Returns every missing mandatory capability in stable declaration order.
-- Member presence, rather than Lua's `function` type, accepts callable native
-- proxies exposed by some LMAOBox host builds.
-- @param host Host library table.
-- @return table Missing capability labels.
function App.missing_capabilities(host)
    local missing = {}
    for i = 1, #REQUIRED do
        local requirement = REQUIRED[i]
        if Safe.member(host[requirement[2]], requirement[3]) == nil then
            missing[#missing + 1] = requirement[1]
        end
    end
    return missing
end

--- Emits complete startup capability diagnostics in the normative format.
-- @param print_function Console output function.
-- @param missing Ordered missing capability labels.
local function report_missing(print_function, missing)
    print_function(Constants.PREFIX .. " required LMAOBox API unavailable:")
    for i = 1, #missing do
        print_function(Constants.PREFIX .. " missing: " .. missing[i])
    end
end

--- Notifies an optional validation observer while keeping it subordinate to the
-- application lifecycle. Observer failures never replace the product warning.
-- @param state Application state.
-- @param method Observer method name.
-- @param ... Values consumed immediately by the observer.
local function observe(state, method, ...)
    local observer = state.observer
    local action = observer ~= nil and observer[method] or nil
    if type(action) == "function" then
        pcall(action, observer, ...)
    end
end

--- Removes every stable callback identifier before registration or an explicit stop.
-- These calls must remain direct: the live host executes callback functions
-- registered through `pcall`, but does not associate their script with the Lua
-- panel's loaded lifecycle.
-- @param host Host libraries.
local function unregister_all(host)
    host.callbacks.Unregister("FrameStageNotify", Constants.CALLBACK.frame)
    host.callbacks.Unregister("FireGameEvent", Constants.CALLBACK.event)
    host.callbacks.Unregister("Draw", Constants.CALLBACK.draw)
    host.callbacks.Unregister("Unload", Constants.CALLBACK.unload)
end

--- Registers one callback directly while guarding its later execution.
-- Direct registration preserves LMAOBox script ownership; only the callback
-- body is protected so one unexpected path failure remains isolated.
-- @param state Application state containing path flags and warning output.
-- @param callback_name LMAOBox callback type.
-- @param identifier Stable reload-safe identifier.
-- @param path Fault-isolation path name.
-- @param action Callback action.
local function register_guarded(state, callback_name, identifier, path, action)
    local callback = function(...)
        if state.paths[path] == false then
            return
        end
        local ok, failure = pcall(action, ...)
        if not ok then
            state.paths[path] = false
            observe(state, "on_callback_fault", path, tostring(failure))
            state.print_function(
                Constants.PREFIX
                    .. " "
                    .. path
                    .. " callback disabled: "
                    .. tostring(failure)
            )
        end
    end
    state.host.callbacks.Register(callback_name, identifier, callback)
end

--- Reports changing pre-render blockers within a fixed startup-only budget.
-- Diagnostics stop permanently after the first successful HUD frame and can
-- therefore never become routine steady-state logging.
-- @param state Application state retaining bounded diagnostic status.
-- @param rendered Whether the latest Draw rendered the widget.
-- @param blocker Reason returned by the controller when it did not render.
local function report_hud_startup(state, rendered, blocker)
    if state.hud_active or state.hud_diagnostic_count
        >= Constants.STARTUP_DIAGNOSTIC_LIMIT
    then
        return
    end
    if rendered then
        state.hud_active = true
        state.print_function(Constants.PREFIX .. " HUD active")
        return
    end
    blocker = blocker or "unknown startup blocker"
    if blocker == "network snapshot unavailable" then
        if state.frame_callback_count == 0 then
            blocker = blocker .. "; FrameStageNotify has not fired"
        else
            blocker = blocker
                .. "; last FrameStageNotify stage "
                .. tostring(state.last_frame_stage)
                .. ", expected "
                .. tostring(state.expected_frame_stage)
        end
    end
    if blocker ~= state.last_hud_blocker then
        state.last_hud_blocker = blocker
        state.hud_diagnostic_count = state.hud_diagnostic_count + 1
        state.print_function(Constants.PREFIX .. " HUD waiting: " .. blocker)
    end
end

--- Starts Ubermensch after validation and returns its application handle.
-- Initialization creates invariant resources before callbacks. Failure leaves no
-- partial callback set, while optional persistence failure never disables HUD.
-- @param host LMAOBox globals and standard Lua APIs supplied by the bundle.
-- @param options Optional internal composition options. The validation runtime
-- supplies an observer and enables adapter diagnostics; the product does not.
-- @return table|nil Application handle, or nil when startup cannot complete.
function App.start(host, options)
    options = options or {}
    local print_function = host.print_function or host.print or print
    local missing = App.missing_capabilities(host)
    if #missing > 0 then
        report_missing(print_function, missing)
        return nil
    end

    unregister_all(host)
    local renderer, renderer_error = Renderer.new(host)
    if renderer == nil then
        print_function(Constants.PREFIX .. " startup failed: " .. renderer_error)
        return nil
    end
    local position = Position.new()
    local persistence = Persistence.new(host, position, print_function)
    local controller = Controller.new({
        adapter = Adapter.new(host, options.adapter_diagnostics == true),
        renderer = renderer,
        persistence = persistence,
        position = position,
        frame_net_update_end = host.frame_net_update_end,
        frame_render_start = host.frame_render_start,
        observer = options.observer,
        observer_error = function(method, failure)
            print_function(
                "[Ubermensch Validation] observer disabled in "
                    .. tostring(method)
                    .. ": "
                    .. tostring(failure)
            )
        end,
    })
    local state = {
        host = host,
        controller = controller,
        print_function = print_function,
        paths = {
            frame = true,
            event = true,
            draw = true,
            unload = true,
        },
        stopped = false,
        hud_active = false,
        hud_diagnostic_count = 0,
        last_hud_blocker = nil,
        frame_callback_count = 0,
        last_frame_stage = nil,
        expected_frame_stage = controller.frame_net_update_end,
        fallback_reported = false,
        observer = options.observer,
    }

    local function stop(host_is_unloading)
        if state.stopped then
            return
        end
        state.stopped = true
        controller:on_unload()
        -- LMAOBox removes this script's callbacks after Unload returns. Calling
        -- Unregister during that dispatch crashes the tested host. Explicit
        -- non-host stops still own and remove the complete callback set.
        if not host_is_unloading then
            unregister_all(host)
        end
    end

    register_guarded(
        state,
        "FrameStageNotify",
        Constants.CALLBACK.frame,
        "frame",
        function(stage)
            if not state.hud_active then
                state.frame_callback_count = state.frame_callback_count + 1
                state.last_frame_stage = stage
            end
            local _, source = controller:on_frame_stage(stage)
            if source == "fallback" and not state.fallback_reported then
                state.fallback_reported = true
                state.print_function(
                    Constants.PREFIX
                        .. " compatibility: FRAME_NET_UPDATE_END unavailable; "
                        .. "using FRAME_RENDER_START"
                )
            end
        end
    )
    register_guarded(
        state,
        "FireGameEvent",
        Constants.CALLBACK.event,
        "event",
        function(event)
            controller:on_event(event)
        end
    )
    register_guarded(
        state,
        "Draw",
        Constants.CALLBACK.draw,
        "draw",
        function()
            local rendered, blocker = controller:on_draw()
            report_hud_startup(state, rendered, blocker)
        end
    )
    register_guarded(
        state,
        "Unload",
        Constants.CALLBACK.unload,
        "unload",
        function()
            stop(true)
        end
    )

    state.stop = function()
        stop(false)
    end
    print_function(Constants.PREFIX .. " loaded v" .. Constants.VERSION)
    return state
end

return App
