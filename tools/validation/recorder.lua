--- Match-event, product-decision, and recorder-health orchestration.
-- @module validation.recorder

local Json = require("validation.json")
local ProductConstants = require("ubermensch.constants")
local Safe = require("ubermensch.safe")
local ValidationConstants = require("validation.constants")
local Views = require("validation.views")
local Writer = require("validation.writer")

local Recorder = {}
Recorder.__index = Recorder

--- Creates empty per-category fingerprints for bounded delta recording.
-- @return table Delta caches keyed by privacy-safe identity.
local function new_delta_cache()
    return {
        snapshot_player = {},
        resource_tables = {},
        resource_row = {},
        current_player = {},
        weapon = {},
        tracker = {},
        candidate = {},
    }
end

--- Reads current monotonic host time, falling back to zero for logging only.
-- @param host Validation runtime host.
-- @return number Finite nonnegative timestamp.
local function monotonic_time(host)
    local ok, value = Safe.library(host.globals, "RealTime")
    if ok and type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
    then
        return math.max(0, value)
    end
    return 0
end

--- Counts dictionary entries for periodic health records.
-- @param values Dictionary table.
-- @return number Number of keys.
local function table_count(values)
    local count = 0
    for _ in pairs(values or {}) do
        count = count + 1
    end
    return count
end

--- Copies capture-route counters into immutable log payload storage.
-- @param self Recorder instance.
-- @return table Preferred, fallback, and unexpected-route counts.
local function capture_source_counts(self)
    return {
        preferred = self.capture_sources.preferred,
        fallback = self.capture_sources.fallback,
        other = self.capture_sources.other,
    }
end

--- Increments the aggregate for the frame-stage route used by one capture.
-- Unexpected values remain visible without creating unbounded dictionary keys.
-- @param self Recorder instance.
-- @param source Controller capture-source label.
local function count_capture_source(self, source)
    if source == "preferred" or source == "fallback" then
        self.capture_sources[source] = self.capture_sources[source] + 1
    else
        self.capture_sources.other = self.capture_sources.other + 1
    end
end

--- Adds a record through the bounded writer.
-- @param self Recorder instance.
-- @param kind Stable record kind.
-- @param data Record payload.
-- @param now Monotonic record time.
-- @return boolean Whether the record entered the buffer.
local function append(self, kind, data, now)
    return self.writer:append(kind, data, now)
end

--- Compares the latest capture context without serializing an unchanged table.
-- @param self Recorder instance.
-- @param info Controller capture notification.
-- @param local_alias Privacy-safe local user alias.
-- @return boolean Whether a context record is required.
local function context_changed(self, info, local_alias)
    local snapshot = info.snapshot
    local previous = self.last_context
    local changed = previous == nil
        or previous.map ~= snapshot.map
        or previous.round_state ~= snapshot.round_state
        or previous.phase ~= snapshot.phase
        or previous.is_mvm ~= snapshot.is_mvm
        or previous.roster_available ~= snapshot.roster_available
        or previous.local_alias ~= local_alias
        or previous.local_team ~= snapshot.local_team
        or previous.local_class ~= snapshot.local_class
        or previous.local_alive ~= snapshot.local_alive
        or previous.observed_weapon_count ~= snapshot.observed_weapon_count
    if changed then
        previous = previous or {}
        previous.map = snapshot.map
        previous.round_state = snapshot.round_state
        previous.phase = snapshot.phase
        previous.is_mvm = snapshot.is_mvm
        previous.roster_available = snapshot.roster_available
        previous.local_alias = local_alias
        previous.local_team = snapshot.local_team
        previous.local_class = snapshot.local_class
        previous.local_alive = snapshot.local_alive
        previous.observed_weapon_count = snapshot.observed_weapon_count
        self.last_context = previous
    end
    return changed
end

--- Reads one selected side into allocation-free fingerprint values.
-- @param side Product side, confirmed missing side, or nil.
-- @return string Identity state.
-- @return number|nil Server user ID.
-- @return number|nil Entity index.
-- @return number|nil Team number.
-- @return string|nil Family source.
-- @return string|nil Charge source.
-- @return string|nil Deployment source.
-- @return boolean|nil Deployment state.
local function side_fingerprint(side)
    if side == nil then
        return "unknown", nil, nil, nil, nil, nil, nil, nil
    end
    if side.missing == true then
        return "missing", nil, nil, side.team, nil, nil, nil, false
    end
    if side.dead == true then
        return "dead", side.userid, side.entity_index, side.team,
            side.family_source, side.charge_source,
            side.deployment_source, false
    end
    return "medic", side.userid, side.entity_index, side.team,
        side.family_source, side.charge_source, side.deployment_source,
        side.deployed
end

--- Preserves an explicit false comparison mode while representing no model as nil.
-- @param model Product model or nil.
-- @return boolean|nil Self-Medic mode, team mode, or unavailable model.
local function self_mode(model)
    if model ~= nil then
        return model.self_mode
    end
    return nil
end

--- Compares the observable decision using flat scalar values.
-- JSON projection is deferred until an actual decision change, avoiding a full
-- allocation and encode at every high-frequency capture.
-- @param self Recorder instance.
-- @param info Controller capture notification.
-- @return boolean Whether a decision record is required.
local function decision_changed(self, info)
    local model = info.model
    local local_side = model ~= nil and model.local_side or nil
    local enemy_side = model ~= nil and model.enemy_side or nil
    local ls, lu, le, lt, lf, lc, ld, la = side_fingerprint(local_side)
    local es, eu, ee, et, ef, ec, ed, ea = side_fingerprint(enemy_side)
    local prepared = info.prepared
    local lines = prepared ~= nil and prepared.lines or nil
    local colors = prepared ~= nil and prepared.colors or nil
    local previous = self.last_decision
    local changed = previous == nil
        or previous.roster_available ~= info.tracking.roster_available
        or previous.local_state ~= ls or previous.local_userid ~= lu
        or previous.local_entity ~= le or previous.local_team ~= lt
        or previous.local_family_source ~= lf
        or previous.local_charge_source ~= lc
        or previous.local_deployment_source ~= ld
        or previous.local_deployed ~= la
        or previous.enemy_state ~= es or previous.enemy_userid ~= eu
        or previous.enemy_entity ~= ee or previous.enemy_team ~= et
        or previous.enemy_family_source ~= ef
        or previous.enemy_charge_source ~= ec
        or previous.enemy_deployment_source ~= ed
        or previous.enemy_deployed ~= ea
        or previous.self_mode ~= self_mode(model)
        or previous.line1 ~= (lines ~= nil and lines[1] or nil)
        or previous.line2 ~= (lines ~= nil and lines[2] or nil)
        or previous.line3 ~= (lines ~= nil and lines[3] or nil)
        or previous.color1 ~= (colors ~= nil and colors[1] or nil)
        or previous.color2 ~= (colors ~= nil and colors[2] or nil)
        or previous.color3 ~= (colors ~= nil and colors[3] or nil)
        or previous.warning ~= (prepared ~= nil and prepared.warning or nil)
    if changed then
        previous = previous or {}
        previous.roster_available = info.tracking.roster_available
        previous.local_state = ls
        previous.local_userid = lu
        previous.local_entity = le
        previous.local_team = lt
        previous.local_family_source = lf
        previous.local_charge_source = lc
        previous.local_deployment_source = ld
        previous.local_deployed = la
        previous.enemy_state = es
        previous.enemy_userid = eu
        previous.enemy_entity = ee
        previous.enemy_team = et
        previous.enemy_family_source = ef
        previous.enemy_charge_source = ec
        previous.enemy_deployment_source = ed
        previous.enemy_deployed = ea
        previous.self_mode = self_mode(model)
        previous.line1 = lines ~= nil and lines[1] or nil
        previous.line2 = lines ~= nil and lines[2] or nil
        previous.line3 = lines ~= nil and lines[3] or nil
        previous.color1 = colors ~= nil and colors[1] or nil
        previous.color2 = colors ~= nil and colors[2] or nil
        previous.color3 = colors ~= nil and colors[3] or nil
        previous.warning = prepared ~= nil and prepared.warning or nil
        self.last_decision = previous
    end
    return changed
end

--- Reports whether either selected identity or comparison mode changed.
-- @param self Recorder instance.
-- @param model Current product model or nil.
-- @return boolean Whether a selection checkpoint is required.
local function selection_changed(self, model)
    local local_side = model ~= nil and model.local_side or nil
    local enemy_side = model ~= nil and model.enemy_side or nil
    local ls, lu, le, lt = side_fingerprint(local_side)
    local es, eu, ee, et = side_fingerprint(enemy_side)
    local previous = self.selection_fingerprint
    local changed = previous == nil
        or previous.self_mode ~= self_mode(model)
        or previous.local_state ~= ls or previous.local_userid ~= lu
        or previous.local_entity ~= le or previous.local_team ~= lt
        or previous.enemy_state ~= es or previous.enemy_userid ~= eu
        or previous.enemy_entity ~= ee or previous.enemy_team ~= et
    if changed then
        previous = previous or {}
        previous.self_mode = self_mode(model)
        previous.local_state = ls
        previous.local_userid = lu
        previous.local_entity = le
        previous.local_team = lt
        previous.enemy_state = es
        previous.enemy_userid = eu
        previous.enemy_entity = ee
        previous.enemy_team = et
        self.selection_fingerprint = previous
    end
    return changed
end

--- Emits a changed keyed view and remembers its fingerprint.
-- @param self Recorder instance.
-- @param cache Cache category and emitted record type.
-- @param key Stable identity inside the category.
-- @param view Exact record payload.
-- @param fingerprint Reduced value used for change detection.
-- @param capture_sequence Product capture sequence.
-- @param now Current monotonic time.
local function emit_delta(
    self,
    cache,
    key,
    view,
    fingerprint,
    capture_sequence,
    now
)
    local encoded = Json.encode(fingerprint or view)
    if self.delta[cache][key] ~= encoded then
        self.delta[cache][key] = encoded
        append(self, cache, {
            capture_sequence = capture_sequence,
            key = key,
            value = view,
        }, now)
    end
end

--- Emits removals for identities absent from the latest delta set.
-- @param self Recorder instance.
-- @param cache Cache category.
-- @param seen Keys present in the latest set.
-- @param capture_sequence Product capture sequence.
-- @param now Current monotonic time.
local function emit_removals(self, cache, seen, capture_sequence, now)
    for key in pairs(self.delta[cache]) do
        if not seen[key] then
            self.delta[cache][key] = nil
            append(self, cache .. "_removed", {
                capture_sequence = capture_sequence,
                key = key,
            }, now)
        end
    end
end

--- Records changed adapter player and resource evidence.
-- @param self Recorder instance.
-- @param info Controller capture notification.
-- @param now Current monotonic time.
local function record_adapter_details(self, info, now)
    local snapshot = info.snapshot
    local sequence = info.sequence
    local views = self.views
    local seen_snapshot = {}
    for index = 1, #snapshot.players do
        local view = views:snapshot_player(snapshot.players[index])
        local key = view.uid or ("E" .. tostring(view.entity_index or index))
        seen_snapshot[key] = true
        local fingerprint = views:snapshot_player(snapshot.players[index])
        fingerprint.resource_charge = views:charge_bucket(
            fingerprint.resource_charge
        )
        fingerprint.current_charge = views:charge_bucket(
            fingerprint.current_charge
        )
        emit_delta(
            self,
            "snapshot_player",
            key,
            view,
            fingerprint,
            sequence,
            now
        )
    end
    emit_removals(self, "snapshot_player", seen_snapshot, sequence, now)

    local diagnostics = snapshot.diagnostics or {}
    local resource_tables = diagnostics.resource_tables or {}
    emit_delta(
        self,
        "resource_tables",
        "all",
        {
            entity_available = diagnostics.resource_entity_available,
            connected = resource_tables.connected,
            valid = resource_tables.valid,
            alive = resource_tables.alive,
            team = resource_tables.team,
            userid = resource_tables.userid,
            class = resource_tables.class,
            charge = resource_tables.charge,
            disconnected_slots = diagnostics.resource_disconnected_count,
            malformed_connected_slots =
                diagnostics.resource_malformed_connected_count,
        },
        nil,
        sequence,
        now
    )

    local seen_resource = {}
    for index = 1, #(diagnostics.resource_rows or {}) do
        local view = views:resource_row(diagnostics.resource_rows[index])
        local key = tostring(view.entity_index or index)
        seen_resource[key] = true
        emit_delta(self, "resource_row", key, view, view, sequence, now)
    end
    emit_removals(self, "resource_row", seen_resource, sequence, now)

    local seen_player = {}
    for index = 1, #(diagnostics.current_players or {}) do
        local view = views:current_player(diagnostics.current_players[index])
        local key = view.uid or ("E" .. tostring(view.entity_index or index))
        seen_player[key] = true
        emit_delta(self, "current_player", key, view, view, sequence, now)
    end
    emit_removals(self, "current_player", seen_player, sequence, now)

    local seen_weapon = {}
    for index = 1, #(diagnostics.weapons or {}) do
        local view = views:weapon(diagnostics.weapons[index])
        local key = "W" .. tostring(view.weapon_index or index)
        seen_weapon[key] = true
        local fingerprint = views:weapon(diagnostics.weapons[index])
        fingerprint.charge = views:charge_bucket(fingerprint.charge)
        fingerprint.charge_raw = views:charge_bucket(
            fingerprint.charge_raw,
            true
        )
        emit_delta(self, "weapon", key, view, fingerprint, sequence, now)
    end
    emit_removals(self, "weapon", seen_weapon, sequence, now)
end

--- Records changed retained tracker state and selection candidates.
-- @param self Recorder instance.
-- @param info Controller capture notification.
-- @param now Current monotonic time.
local function record_domain_details(self, info, now)
    local sequence = info.sequence
    local views = self.views
    local seen_tracker = {}
    for key, record in pairs(info.tracker.records) do
        local view = views:tracker_record(record)
        local safe_key = views:record_key(key)
        seen_tracker[safe_key] = true
        local fingerprint = views:tracker_record(record)
        fingerprint.last_seen = nil
        fingerprint.resource_charge = views:charge_bucket(
            fingerprint.resource_charge
        )
        fingerprint.frame_charge = views:charge_bucket(
            fingerprint.frame_charge
        )
        if fingerprint.anchor ~= nil then
            fingerprint.anchor.charge = views:charge_bucket(
                fingerprint.anchor.charge
            )
            fingerprint.anchor.time = nil
        end
        emit_delta(
            self,
            "tracker",
            safe_key,
            view,
            fingerprint,
            sequence,
            now
        )
    end
    emit_removals(self, "tracker", seen_tracker, sequence, now)

    local seen_candidate = {}
    for index = 1, #info.tracking.candidates do
        local view = views:candidate(info.tracking.candidates[index])
        local key = view.uid or ("E" .. tostring(view.entity_index or index))
        seen_candidate[key] = true
        local fingerprint = views:candidate(info.tracking.candidates[index])
        fingerprint.charge = views:charge_bucket(fingerprint.charge)
        emit_delta(
            self,
            "candidate",
            key,
            view,
            fingerprint,
            sequence,
            now
        )
    end
    local dead_candidates = info.tracking.dead_candidates or {}
    for index = 1, #dead_candidates do
        local candidate = dead_candidates[index]
        local view = views:candidate(candidate)
        local key = view.uid or ("E" .. tostring(view.entity_index or index))
        seen_candidate[key] = true
        emit_delta(
            self,
            "candidate",
            key,
            view,
            view,
            sequence,
            now
        )
    end
    emit_removals(self, "candidate", seen_candidate, sequence, now)
end

--- Records detailed evidence at the fixed diagnostic ceiling.
-- Observable decisions are handled separately without this ceiling.
-- @param self Recorder instance.
-- @param info Controller capture notification.
-- @param now Current monotonic time.
local function record_details(self, info, now)
    record_adapter_details(self, info, now)
    record_domain_details(self, info, now)
end

--- Creates a full recovery checkpoint from current product state.
-- @param self Recorder instance.
-- @param info Controller capture notification.
-- @return table Complete privacy-safe checkpoint.
local function checkpoint_view(self, info)
    local views = self.views
    local players = {}
    for index = 1, #info.snapshot.players do
        players[index] = views:snapshot_player(info.snapshot.players[index])
    end
    local candidates = {}
    for index = 1, #info.tracking.candidates do
        candidates[index] = views:candidate(info.tracking.candidates[index])
    end
    local dead_candidates = {}
    for index = 1, #(info.tracking.dead_candidates or {}) do
        dead_candidates[index] = views:candidate(
            info.tracking.dead_candidates[index]
        )
    end
    local records = {}
    for _, record in pairs(info.tracker.records) do
        records[#records + 1] = views:tracker_record(record)
    end
    local diagnostics = info.snapshot.diagnostics or {}
    local resource_rows = {}
    for index = 1, #(diagnostics.resource_rows or {}) do
        resource_rows[index] = views:resource_row(diagnostics.resource_rows[index])
    end
    local current_players = {}
    for index = 1, #(diagnostics.current_players or {}) do
        current_players[index] = views:current_player(
            diagnostics.current_players[index]
        )
    end
    local weapons = {}
    for index = 1, #(diagnostics.weapons or {}) do
        weapons[index] = views:weapon(diagnostics.weapons[index])
    end
    return {
        capture_sequence = info.sequence,
        context = {
            source = info.source,
            stage = info.stage,
            map = info.snapshot.map,
            round_state = info.snapshot.round_state,
            phase = info.snapshot.phase,
            is_mvm = info.snapshot.is_mvm,
            roster_available = info.snapshot.roster_available,
            local_uid = views:user_alias(info.snapshot.local_userid),
            local_team = info.snapshot.local_team,
            local_class = info.snapshot.local_class,
            local_alive = info.snapshot.local_alive,
            observed_weapon_count = info.snapshot.observed_weapon_count,
        },
        players = players,
        resource_tables = diagnostics.resource_tables,
        resource_summary = {
            disconnected_slots = diagnostics.resource_disconnected_count,
            malformed_connected_slots =
                diagnostics.resource_malformed_connected_count,
        },
        resource_rows = resource_rows,
        current_players = current_players,
        weapons = weapons,
        tracker_records = records,
        phase_history = info.tracker.phase_history,
        candidates = candidates,
        dead_candidates = dead_candidates,
        decision = views:decision(info),
    }
end

--- Reduces one display side to facts that identify the selected slot or state.
-- Charge and field sources are intentionally omitted so ordinary value changes
-- cannot create expensive full selection checkpoints.
-- @param side Privacy-safe selected side, missing side, or nil.
-- @return table Stable identity view.
local function selection_side(side)
    if side == nil then
        return { state = "unknown" }
    end
    if side.missing == true then
        return {
            state = "missing",
            team = side.team,
        }
    end
    if side.dead == true then
        return {
            state = "dead",
            uid = side.uid,
            entity_index = side.entity_index,
            team = side.team,
        }
    end
    return {
        state = "medic",
        uid = side.uid,
        entity_index = side.entity_index,
        team = side.team,
    }
end

--- Builds the compact identity fingerprint used for selection transitions.
-- @param decision Projected product decision.
-- @return table Local/enemy selection identity and comparison mode.
local function selection_view(decision)
    return {
        self_mode = decision.self_mode,
        local_side = selection_side(decision.local_side),
        enemy_side = selection_side(decision.enemy_side),
    }
end

--- Records complete upstream evidence whenever either selected identity changes.
-- This record bypasses the 10 Hz detail ceiling because a one-capture selection
-- transition must remain diagnosable even when it reverses immediately.
-- @param self Recorder instance.
-- @param info Synchronous controller capture notification.
-- @param decision Projected decision for the capture.
-- @param now Current monotonic time.
local function record_selection_transition(self, info, decision, now)
    local selection = selection_view(decision)
    local evidence = checkpoint_view(self, info)
    evidence.previous_selection = self.last_selection
    evidence.selection = selection
    evidence.adapter_diagnostics_available = info.snapshot.diagnostics ~= nil
    append(self, "selection_checkpoint", evidence, now)
    self.last_selection = selection
end

--- Resolves the software-defined recorder limits.
-- Overrides are accepted only by unit tests; the bundled entrypoint exposes no
-- user configuration surface.
-- @param limits Optional test-only overrides.
-- @return table Complete fixed limit set.
local function resolve_limits(limits)
    limits = limits or {}
    return {
        flush_interval = limits.flush_interval
            or ValidationConstants.FLUSH_INTERVAL,
        heartbeat_interval = limits.heartbeat_interval
            or ValidationConstants.HEARTBEAT_INTERVAL,
        checkpoint_interval = limits.checkpoint_interval
            or ValidationConstants.CHECKPOINT_INTERVAL,
        detail_interval = limits.detail_interval
            or ValidationConstants.DETAIL_INTERVAL,
        max_buffer_bytes = limits.max_buffer_bytes
            or ValidationConstants.MAX_BUFFER_BYTES,
        max_file_bytes = limits.max_file_bytes
            or ValidationConstants.MAX_FILE_BYTES,
        charge_log_step = limits.charge_log_step
            or ValidationConstants.CHARGE_LOG_STEP,
    }
end

--- Creates the recorder and immediately persists a session header.
-- @param host LMAOBox host and standard Lua APIs.
-- @param test_limits Optional unit-test-only fixed-limit overrides.
-- @return table Recorder instance, possibly disabled when no path is writable.
function Recorder.new(host, test_limits)
    local now = monotonic_time(host)
    local limits = resolve_limits(test_limits)
    local writer = Writer.new(host, now, limits)
    local self = setmetatable({
        host = host,
        print_function = host.print_function or host.print or print,
        limits = limits,
        writer = writer,
        views = Views.new(limits.charge_log_step),
        delta = new_delta_cache(),
        closed = false,
        captures = 0,
        draws = 0,
        events = 0,
        decisions = 0,
        markers = 0,
        marker_held = false,
        capture_sources = {
            preferred = 0,
            fallback = 0,
            other = 0,
        },
        last_heartbeat = now,
        last_checkpoint = now,
        last_detail = -math.huge,
        force_diagnostics = true,
        last_map = nil,
        last_context = nil,
        last_decision = nil,
        selection_fingerprint = nil,
        last_selection = nil,
        last_blocker = nil,
        pending_draw_sequence = nil,
        last_drawn_sequence = nil,
    }, Recorder)
    if writer.disabled then
        return self
    end
    append(self, "session_start", {
        recorder_version = ValidationConstants.RECORDER_VERSION,
        product_version = ProductConstants.VERSION,
        lua_version = host.lua_version or "unknown",
        marker_key = "F8",
        privacy = "session aliases; no names, Steam IDs, chat, or server address",
        charge_detail_step = limits.charge_log_step,
        detail_interval = limits.detail_interval,
        flush_interval = limits.flush_interval,
        checkpoint_interval = limits.checkpoint_interval,
        max_file_bytes = limits.max_file_bytes,
    }, now)
    writer:flush(now)
    self.print_function(ValidationConstants.PREFIX .. " recording: " .. writer.path)
    self.print_function(ValidationConstants.PREFIX .. " press F8 to add a marker")
    return self
end

--- Requests verbose adapter evidence only at the fixed detail cadence.
-- Product snapshots, decisions, events, and Draw correlation remain immediate;
-- this controls only the expensive raw boundary-diagnostic projection.
-- @return boolean Whether the next capture should collect diagnostics.
function Recorder:wants_diagnostics()
    if self.writer.disabled or self.closed then
        return false
    end
    local now = monotonic_time(self.host)
    return self.force_diagnostics
        or now - self.last_detail >= self.limits.detail_interval
end

--- Records relevant match or product events without retaining the GameEvent.
-- Product acceptance is logged separately from broader round/map segmentation.
-- @param event Transient LMAOBox GameEvent.
-- @param normalized Product-normalized event or nil.
function Recorder:on_event(event, normalized)
    if self.writer.disabled or self.closed then
        return
    end
    local name_ok, name = Safe.method(event, "GetName")
    if not name_ok or type(name) ~= "string" then
        return
    end
    local product_relevant = ProductConstants.EVENTS[name] == true
    local match_relevant = ValidationConstants.MATCH_EVENTS[name] == true
        or string.sub(name, 1, 15) == "teamplay_round_"
    if not product_relevant and not match_relevant then
        return
    end
    local now = normalized ~= nil and normalized.time or monotonic_time(self.host)
    local _, raw_userid = Safe.method(event, "GetInt", "userid")
    local _, team = Safe.method(event, "GetInt", "team")
    local _, class = Safe.method(event, "GetInt", "class")
    local _, win_reason = Safe.method(event, "GetInt", "winreason")
    local _, full_round = Safe.method(event, "GetBool", "full_round")
    local _, map_name = Safe.method(event, "GetString", "mapname")
    local alias = self.views:user_alias(
        normalized ~= nil and normalized.userid or raw_userid
    )
    self.events = self.events + 1
    append(self, "event", {
        name = name,
        product_relevant = product_relevant,
        product_accepted = normalized ~= nil,
        uid = alias,
        userid_valid = alias ~= nil,
        team = type(team) == "number" and team or nil,
        class = type(class) == "number" and class or nil,
        win_reason = type(win_reason) == "number" and win_reason or nil,
        full_round = type(full_round) == "boolean" and full_round or nil,
        map = type(map_name) == "string" and map_name or nil,
    }, now)
end

--- Records one resolved product capture and decision using bounded deltas.
-- Every observable decision change is immediate; verbose boundary/tracker
-- evidence is sampled at 10 Hz and recovered by periodic full checkpoints.
-- @param info Synchronous controller capture notification.
function Recorder:on_capture(info)
    if self.writer.disabled or self.closed then
        return
    end
    local now = info.snapshot.now
    local views = self.views
    self.captures = self.captures + 1
    count_capture_source(self, info.source)
    local local_alias = views:user_alias(info.snapshot.local_userid)
    if context_changed(self, info, local_alias) then
        append(self, "context", {
            capture_sequence = info.sequence,
            source = info.source,
            stage = info.stage,
            map = info.snapshot.map,
            round_state = info.snapshot.round_state,
            phase = info.snapshot.phase,
            is_mvm = info.snapshot.is_mvm,
            roster_available = info.snapshot.roster_available,
            local_uid = local_alias,
            local_team = info.snapshot.local_team,
            local_class = info.snapshot.local_class,
            local_alive = info.snapshot.local_alive,
            observed_weapon_count = info.snapshot.observed_weapon_count,
        }, now)
    end

    local map_changed = self.last_map ~= nil and self.last_map ~= info.snapshot.map
    if map_changed then
        append(self, "map_transition", {
            capture_sequence = info.sequence,
            from = self.last_map,
            to = info.snapshot.map,
        }, now)
        self.delta = new_delta_cache()
        self.last_decision = nil
        self.selection_fingerprint = nil
        self.last_detail = -math.huge
        self.force_diagnostics = true
    end
    self.last_map = info.snapshot.map

    local changed_decision = decision_changed(self, info)
    local changed_selection = selection_changed(self, info.model)
    local decision
    if changed_decision or changed_selection then
        decision = views:decision(info)
    end
    if changed_decision then
        append(self, "decision", decision, now)
        self.decisions = self.decisions + 1
        self.pending_draw_sequence = info.sequence
    end
    if changed_selection then
        record_selection_transition(self, info, decision, now)
        if info.snapshot.diagnostics == nil then
            self.force_diagnostics = true
        end
    end

    if info.snapshot.diagnostics ~= nil then
        record_details(self, info, now)
        self.last_detail = now
        self.force_diagnostics = false
    end

    if now - self.last_heartbeat >= self.limits.heartbeat_interval then
        append(self, "heartbeat", {
            capture_sequence = info.sequence,
            captures = self.captures,
            draws = self.draws,
            events = self.events,
            decisions = self.decisions,
            markers = self.markers,
            capture_sources = capture_source_counts(self),
            tracker_records = table_count(info.tracker.records),
            candidates = #info.tracking.candidates,
            dead_candidates = #(info.tracking.dead_candidates or {}),
            queued_events = #info.tracker.events,
            buffer_bytes = self.writer.buffer_bytes,
            dropped_records = self.writer.dropped_records,
            part = self.writer.part,
        }, now)
        self.last_heartbeat = now
    end

    if now - self.last_checkpoint >= self.limits.checkpoint_interval then
        append(self, "checkpoint", checkpoint_view(self, info), now)
        self.last_checkpoint = now
    end

    if map_changed
        or now - self.writer.last_flush >= self.limits.flush_interval
        or self.writer.buffer_bytes >= self.limits.max_buffer_bytes / 2
    then
        self.writer:flush(now)
    end
    if self.writer.pending_drops > 0 and not self.writer.disabled then
        local dropped = self.writer.pending_drops
        self.writer.pending_drops = 0
        append(self, "recorder_drop", {
            capture_sequence = info.sequence,
            count = dropped,
            total = self.writer.dropped_records,
        }, now)
    end
end

--- Records the first Draw that consumes a logged decision and F8 markers.
-- This path appends only to memory; file flushing remains outside Draw.
-- @param decision_sequence Latest controller decision sequence.
-- @param rendered Whether the widget was drawn.
-- @param blocker Visibility/readiness blocker when not drawn.
-- @param prepared Latest formatted HUD state.
function Recorder:on_draw(decision_sequence, rendered, blocker, prepared)
    if self.writer.disabled or self.closed then
        return
    end
    self.draws = self.draws + 1
    local record_draw = rendered and self.pending_draw_sequence ~= nil
        and decision_sequence >= self.pending_draw_sequence
    local record_blocker = not rendered and blocker ~= self.last_blocker

    local key = self.host.key_f8 or ValidationConstants.KEY_F8
    local pressed_ok, pressed = Safe.library(
        self.host.input,
        "IsButtonPressed",
        key
    )
    local record_marker = pressed_ok and pressed == true
        and not self.marker_held
    if pressed_ok then
        self.marker_held = pressed == true
    end

    if not record_draw and not record_blocker and not record_marker then
        self.last_blocker = rendered and nil or blocker
        return
    end

    local now = monotonic_time(self.host)
    if record_draw then
        append(self, "draw", {
            decision_sequence = self.pending_draw_sequence,
            consumed_capture_sequence = decision_sequence,
            rendered = true,
            prepared = Views.prepared(prepared),
        }, now)
        self.last_drawn_sequence = self.pending_draw_sequence
        self.pending_draw_sequence = nil
    elseif record_blocker then
        append(self, "draw_blocked", {
            decision_sequence = decision_sequence,
            blocker = blocker,
        }, now)
    end
    self.last_blocker = rendered and nil or blocker

    if record_marker then
        self.markers = self.markers + 1
        append(self, "marker", {
            number = self.markers,
            decision_sequence = decision_sequence,
            rendered = rendered,
            blocker = blocker,
            prepared = Views.prepared(prepared),
        }, now)
        self.print_function(
            ValidationConstants.PREFIX
                .. " marker "
                .. tostring(self.markers)
                .. " recorded"
        )
    end
end

--- Records an unexpected product callback fault and forces durable output.
-- @param path Product callback path that was disabled.
-- @param failure Error text already reduced by the application boundary.
function Recorder:on_callback_fault(path, failure)
    if self.writer.disabled or self.closed then
        return
    end
    local now = monotonic_time(self.host)
    append(self, "callback_fault", {
        path = path,
        failure = failure,
    }, now)
    self.writer:flush(now)
end

--- Flushes final counters, closes the file, and becomes idempotent.
-- @param decision_sequence Last controller decision sequence.
function Recorder:on_unload(decision_sequence)
    self:close("unload", decision_sequence)
end

--- Closes a recorder that could not enter or has left app lifecycle.
-- @param reason Session termination reason.
-- @param decision_sequence Last product decision sequence, if available.
function Recorder:close(reason, decision_sequence)
    if self.closed then
        return
    end
    self.closed = true
    local now = monotonic_time(self.host)
    if not self.writer.disabled then
        append(self, "session_end", {
            reason = reason,
            decision_sequence = decision_sequence,
            captures = self.captures,
            draws = self.draws,
            events = self.events,
            decisions = self.decisions,
            markers = self.markers,
            capture_sources = capture_source_counts(self),
            dropped_records = self.writer.dropped_records,
            parts = #self.writer.paths,
        }, now)
        self.writer:flush(now)
        self.writer:close()
        self.print_function(
            ValidationConstants.PREFIX
                .. " stopped; parts="
                .. tostring(#self.writer.paths)
                .. "; dropped="
                .. tostring(self.writer.dropped_records)
        )
    end
end

return Recorder
