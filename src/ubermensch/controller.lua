--- Thin callback orchestration over acquisition, domain state, and drawing.
-- @module ubermensch.controller

local Constants = require("ubermensch.constants")
local Formatting = require("ubermensch.formatting")
local Numbers = require("ubermensch.numbers")
local Position = require("ubermensch.position")
local Safe = require("ubermensch.safe")
local State = require("ubermensch.state")
local Tracking = require("ubermensch.tracking")

local Controller = {}
Controller.__index = Controller

--- Disables a failed validation observer without affecting product callbacks.
-- @param self Controller instance.
-- @param method Observer method that failed.
-- @param failure Failure value.
local function disable_observer(self, method, failure)
    local observer = self.observer
    local close = observer ~= nil and observer.close or nil
    if type(close) == "function" then
        pcall(close, observer, "observer_fault")
    end
    self.observer = nil
    if self.observer_error ~= nil then
        self.observer_error(method, failure)
    end
end

--- Calls an optional validation observer without allowing diagnostics to break
-- the product callback path. An observer is disabled permanently after its
-- first fault because partial diagnostic output is safer than altered HUD state.
-- @param self Controller instance.
-- @param method Observer method name.
-- @param ... Values consumed synchronously by the observer.
local function observe(self, method, ...)
    local observer = self.observer
    if observer == nil then
        return
    end
    local action = observer[method]
    if type(action) ~= "function" then
        return
    end
    local ok, failure = pcall(action, observer, ...)
    if not ok then
        disable_observer(self, method, failure)
    end
end

--- Asks the validation observer whether this capture needs verbose boundary data.
-- Product adapters never collect it. A validation observer without the optional
-- scheduling method retains the original every-capture diagnostic behavior.
-- @param self Controller instance.
-- @param capture_source `preferred` or `fallback`.
-- @param stage Normalized frame stage.
-- @return boolean Whether adapter diagnostics should be collected.
local function diagnostics_requested(self, capture_source, stage)
    if not self.adapter.diagnostics_enabled then
        return false
    end
    local observer = self.observer
    local action = observer ~= nil and observer.wants_diagnostics or nil
    if type(action) ~= "function" then
        return true
    end
    local ok, requested = pcall(
        action,
        observer,
        capture_source,
        stage
    )
    if not ok then
        disable_observer(self, "wants_diagnostics", requested)
        return false
    end
    return requested == true
end

--- Normalizes a callback stage without trusting the host value's Lua type.
-- Some native callback values stringify as their documented integer even when
-- strict comparison with an ordinary Lua number fails.
-- @param stage Raw LMAOBox FrameStageNotify value.
-- @return number|nil Finite integral stage, otherwise nil.
local function normalize_frame_stage(stage)
    if Numbers.is_finite(stage) and stage == math.floor(stage) then
        return stage
    end
    local ok, text = pcall(tostring, stage)
    local numeric = ok and tonumber(text) or nil
    if Numbers.is_finite(numeric) and numeric == math.floor(numeric) then
        return numeric
    end
    return nil
end

--- Constructs controller state from initialized collaborators.
-- @param collaborators Adapter, renderer, persistence, and position objects.
-- @return table Controller instance.
function Controller.new(collaborators)
    return setmetatable({
        adapter = collaborators.adapter,
        renderer = collaborators.renderer,
        persistence = collaborators.persistence,
        position = collaborators.position,
        frame_net_update_end = type(collaborators.frame_net_update_end) == "number"
            and collaborators.frame_net_update_end
            or Constants.FRAME_NET_UPDATE_END,
        frame_render_start = type(collaborators.frame_render_start) == "number"
            and collaborators.frame_render_start
            or Constants.FRAME_RENDER_START,
        observer = collaborators.observer,
        observer_error = collaborators.observer_error,
        preferred_capture_pending_render = false,
        last_network_revision = nil,
        has_network_revision = false,
        tracker = Tracking.new(),
        prior_selection = {},
        latest_snapshot = nil,
        prepared_cache = nil,
        bounds = {},
        latest_prepared = nil,
        latest_decision_sequence = 0,
        unloaded = false,
    }, Controller)
end

--- Captures, reconciles, and prepares one post-network snapshot.
-- @param self Controller instance.
-- @param capture_source `preferred` or `fallback` frame-stage route.
-- @param stage Normalized numeric frame stage.
local function capture_and_prepare(self, capture_source, stage)
    local snapshot = self.adapter:capture(
        diagnostics_requested(self, capture_source, stage)
    )
    if self.latest_snapshot ~= nil
        and (snapshot.map ~= self.latest_snapshot.map
            or (snapshot.local_team ~= nil
                and self.latest_snapshot.local_team ~= nil
                and snapshot.local_team ~= self.latest_snapshot.local_team)
            or (snapshot.local_userid ~= nil
                and self.latest_snapshot.local_userid ~= nil
                and snapshot.local_userid ~= self.latest_snapshot.local_userid))
    then
        self.prior_selection = {}
    end
    local tracking = Tracking.reconcile(self.tracker, snapshot)
    local model = State.resolve(tracking, self.prior_selection)
    self.latest_snapshot = snapshot
    if model ~= nil then
        self.prepared_cache = Formatting.prepare(model, self.prepared_cache)
        self.latest_prepared = self.prepared_cache
    else
        self.latest_prepared = nil
    end
    self.latest_decision_sequence = self.latest_decision_sequence + 1
    if self.observer ~= nil then
        observe(self, "on_capture", {
            sequence = self.latest_decision_sequence,
            source = capture_source,
            stage = stage,
            snapshot = snapshot,
            tracking = tracking,
            tracker = self.tracker,
            model = model,
            prepared = self.latest_prepared,
            prior_selection = self.prior_selection,
        })
    end
end

--- Determines whether a frame-stage capture has new work to reconcile.
-- A changed last-received tick or a queued event always captures. If the host
-- cannot provide a valid revision, the optimization fails open and captures.
-- @param self Controller instance.
-- @return boolean Whether a fallback capture is required.
local function capture_due(self)
    local revision = self.adapter:network_revision()
    if revision == nil then
        return true
    end
    local changed = not self.has_network_revision
        or revision ~= self.last_network_revision
    self.has_network_revision = true
    self.last_network_revision = revision
    return changed or #self.tracker.events > 0
end

--- Captures at network-update end, with a render-start compatibility fallback.
-- A preferred capture suppresses the immediately following fallback. When the
-- host omits stage 4, stage 5 is the first post-network opportunity and still
-- reaches Draw without moving entity acquisition into the drawing callback.
-- @param stage Raw LMAOBox client frame-stage value.
-- @return boolean Whether this invocation captured a snapshot.
-- @return string|nil `preferred` or `fallback` when a capture occurred.
function Controller:on_frame_stage(stage)
    if self.unloaded then
        return false, nil
    end
    local normalized_stage = normalize_frame_stage(stage)
    if normalized_stage == self.frame_net_update_end then
        self.preferred_capture_pending_render = true
        if not capture_due(self) then
            return false, nil
        end
        capture_and_prepare(self, "preferred", normalized_stage)
        return true, "preferred"
    end
    if normalized_stage == self.frame_render_start then
        if self.preferred_capture_pending_render then
            self.preferred_capture_pending_render = false
            return false, nil
        end
        if not capture_due(self) then
            return false, nil
        end
        capture_and_prepare(self, "fallback", normalized_stage)
        self.preferred_capture_pending_render = false
        return true, "fallback"
    end
    return false, nil
end

--- Normalizes and queues one relevant game event without full reconciliation.
-- @param event Transient LMAOBox GameEvent.
function Controller:on_event(event)
    if self.unloaded then
        return
    end
    local normalized = self.adapter:normalize_event(event)
    observe(self, "on_event", event, normalized)
    if normalized ~= nil then
        Tracking.enqueue(self.tracker, normalized)
    end
end

--- Reports a Draw outcome to the optional validation observer.
-- @param self Controller instance.
-- @param rendered Whether a widget was drawn.
-- @param blocker Visibility or readiness reason when no widget was drawn.
-- @return boolean The supplied rendered value.
-- @return string|nil The supplied blocker.
local function finish_draw(self, rendered, blocker)
    observe(
        self,
        "on_draw",
        self.latest_decision_sequence,
        rendered,
        blocker,
        self.latest_prepared
    )
    return rendered, blocker
end

--- Resolves screen-dependent bounds for the already prepared display.
-- @param self Controller instance.
-- @return table|nil Bounds with screen dimensions, or nil on invalid host data.
-- @return string|nil Startup-diagnostic reason when dimensions are invalid.
local function resolve_bounds(self)
    local ok, screen_width, screen_height = Safe.library(
        self.renderer.host.draw,
        "GetScreenSize"
    )
    if not ok or not Numbers.is_finite(screen_width)
        or not Numbers.is_finite(screen_height)
        or screen_width <= 0
        or screen_height <= 0
    then
        return nil, "screen size unavailable"
    end
    local width, height, line_height = self.renderer:measure(
        self.latest_prepared
    )
    local x, y = Position.pixels(
        self.position,
        screen_width,
        screen_height,
        width,
        height
    )
    local bounds = self.bounds
    bounds.x = x
    bounds.y = y
    bounds.width = width
    bounds.height = height
    bounds.line_height = line_height
    bounds.screen_width = screen_width
    bounds.screen_height = screen_height
    return bounds, nil
end

--- Handles menu-only dragging and persists only a completed move.
-- @param self Controller instance.
-- @param bounds Current widget and screen bounds, mutated after movement.
local function handle_drag(self, bounds)
    local input = self.adapter:input_sample()
    if not self.position.dragging and not input.menu_open then
        return
    end
    local ended = Position.update_drag(
        self.position,
        input,
        bounds,
        bounds.screen_width,
        bounds.screen_height
    )
    if self.position.dragging then
        bounds.x, bounds.y = Position.pixels(
            self.position,
            bounds.screen_width,
            bounds.screen_height,
            bounds.width,
            bounds.height
        )
    end
    if ended then
        self.persistence:save(self.position)
    end
end

--- Draws the latest resolved state without reacquiring network entities.
-- Visibility, screen layout, drag input, and rendering remain separate from the
-- network-stage acquisition path.
-- @return boolean Whether the widget was rendered.
-- @return string|nil Startup-diagnostic reason when it was not rendered.
function Controller:on_draw()
    if self.unloaded then
        return finish_draw(self, false, "controller unloaded")
    end
    if self.latest_snapshot == nil then
        return finish_draw(self, false, "network snapshot unavailable")
    end
    local visible, visibility_reason = self.adapter:visibility(
        self.latest_snapshot
    )
    if not visible then
        return finish_draw(self, false, visibility_reason)
    end
    if self.latest_prepared == nil then
        return finish_draw(self, false, "local team unavailable")
    end
    local bounds, bounds_reason = resolve_bounds(self)
    if bounds == nil then
        return finish_draw(self, false, bounds_reason)
    end
    handle_drag(self, bounds)
    self.renderer:draw(self.latest_prepared, bounds)
    return finish_draw(self, true, nil)
end

--- Performs idempotent unload cleanup and last dirty-position persistence.
function Controller:on_unload()
    if self.unloaded then
        return
    end
    if self.position.dragging then
        self.position.dragging = false
        self.position.dirty = true
    end
    self.persistence:save(self.position)
    Tracking.clear(self.tracker)
    self.latest_snapshot = nil
    self.latest_prepared = nil
    self.prepared_cache = nil
    self.preferred_capture_pending_render = false
    self.last_network_revision = nil
    self.has_network_revision = false
    self.unloaded = true
    observe(self, "on_unload", self.latest_decision_sequence)
end

return Controller
