--- User-ID-keyed Medic tracking, reconciliation, and source precedence.
-- @module ubermensch.tracking

local Constants = require("ubermensch.constants")
local Estimation = require("ubermensch.estimation")
local Numbers = require("ubermensch.numbers")
local Weapons = require("ubermensch.weapons")

local Tracking = {}

--- Clears an internal bounded dictionary without replacing its storage.
-- @param values Mutable table used only as tracking scratch state.
local function clear_table(values)
    for key in pairs(values) do
        values[key] = nil
    end
end

--- Replaces the trustworthy charge fact without anchoring from an estimate.
-- Reusing the small anchor table reduces capture-frequency allocation; every
-- field is still written only from a new current, resource, or event fact.
-- @param record Retained Medic record.
-- @param charge Trustworthy percentage.
-- @param time Trustworthy observation time.
-- @param deployed Deployment state associated with the charge.
-- @param source `current`, `resource`, or `event`.
local function set_anchor(record, charge, time, deployed, source)
    local anchor = record.anchor
    if anchor == nil then
        anchor = {}
        record.anchor = anchor
    end
    anchor.charge = charge
    anchor.time = time
    anchor.deployed = deployed
    anchor.source = source
end

--- Creates a fresh retained Medic record containing no host objects.
-- @param key Stable user-ID key or temporary entity-index key.
-- @param now Monotonic creation time.
-- @return table Mutable retained record.
local function new_record(key, now)
    return {
        key = key,
        created_at = now,
        last_seen = now,
    }
end

--- Returns the preferred record key for validated identity fields.
-- @param userid Positive server user ID, if available.
-- @param entity_index Positive player entity index, if available.
-- @return string|nil Stable or temporary key.
local function record_key(userid, entity_index)
    if userid ~= nil then
        return "u:" .. tostring(userid)
    end
    if entity_index ~= nil then
        return "e:" .. tostring(entity_index)
    end
    return nil
end

--- Clears charge and deployment facts invalidated by a hard lifecycle change.
-- Family can optionally survive spawn and inventory resets, but must not survive
-- a confirmed class, team, disconnect, map, or unsupported-weapon transition.
-- @param record Retained Medic record.
-- @param clear_family Whether the retained family is incompatible too.
local function clear_gameplay(record, clear_family)
    record.anchor = nil
    record.deployed = nil
    record.deployment_source = nil
    record.deployment_deadline = nil
    record.pending_deployment_time = nil
    record.frame_charge = nil
    record.frame_charge_source = nil
    record.frame_deployed = nil
    record.frame_deployment_source = nil
    if clear_family then
        record.died_at = nil
        record.family = nil
        record.unsupported = nil
        record.frame_family = nil
        record.frame_family_source = nil
    end
end

--- Clears team-incompatible gameplay while preserving an existing Medic death.
-- A dead Medic still exists after switching teams, but its old weapon family
-- and charge cannot follow it to the new team.
-- @param record Retained player record.
-- @param next_class Authoritative next class, or nil to retain current class.
-- @param next_alive Authoritative next alive state, or nil to retain current state.
local function clear_for_team_change(record, next_class, next_alive)
    local died_at = record.died_at
    local medic = (next_class or record.class) == Constants.MEDIC_CLASS
    local dead = next_alive == false
        or (next_alive == nil and record.alive == false)
    clear_gameplay(record, true)
    if medic and dead then
        record.died_at = died_at
    end
end

--- Applies an authoritative alive transition and timestamps a new death.
-- Repeated dead observations retain the original transition time so selection
-- does not become dependent on roster polling order or frequency.
-- @param record Retained player record.
-- @param alive Authoritative alive value or nil.
-- @param now Monotonic observation time.
local function set_alive(record, alive, now)
    if alive == nil then
        return
    end
    if alive == false and record.alive ~= false then
        record.died_at = now
    elseif alive == true then
        record.died_at = nil
    end
    record.alive = alive
end

--- Creates a tracking store with bounded event and phase histories.
-- @return table Tracker state accepted by the module functions.
function Tracking.new()
    return {
        records = {},
        index_to_key = {},
        events = {},
        scratch_present = {},
        phase_history = {},
        phase = nil,
        map = nil,
        local_userid = nil,
        local_team = nil,
        last_local_team = nil,
        generation = 0,
    }
end

--- Appends a normalized primitive event while retaining only the newest 64.
-- @param tracker Tracking store.
-- @param event Normalized event table with a positive user ID.
function Tracking.enqueue(tracker, event)
    if type(event) ~= "table" or Numbers.userid(event.userid) == nil then
        return
    end
    local events = tracker.events
    if #events == Constants.EVENT_QUEUE_LIMIT then
        table.remove(events, 1)
    end
    events[#events + 1] = event
end

--- Associates an entity index with identity and safely handles index reuse.
-- Temporary entity-keyed facts migrate to a later validated user-ID key. Facts
-- from a different user ID are never transferred across a reused entity index.
-- @param tracker Tracking store.
-- @param userid Validated user ID or nil.
-- @param entity_index Validated entity index or nil.
-- @param now Current monotonic time.
-- @return table|nil Associated retained record.
local function obtain_record(tracker, userid, entity_index, now)
    local key = record_key(userid, entity_index)
    if key == nil then
        return nil
    end

    if userid ~= nil and entity_index ~= nil then
        local temporary_key = "e:" .. tostring(entity_index)
        local temporary = tracker.records[temporary_key]
        if temporary ~= nil and tracker.records[key] == nil then
            tracker.records[temporary_key] = nil
            temporary.key = key
            tracker.records[key] = temporary
        end
    end

    local previous_key = entity_index ~= nil
        and tracker.index_to_key[entity_index]
        or nil
    if previous_key ~= nil and previous_key ~= key then
        local previous = tracker.records[previous_key]
        if previous ~= nil then
            previous.entity_index = nil
            if string.sub(previous_key, 1, 2) == "e:" then
                tracker.records[previous_key] = nil
            end
        end
    end

    local record = tracker.records[key]
    if record == nil then
        record = new_record(key, now)
        tracker.records[key] = record
    end
    record.userid = userid or record.userid
    record.entity_index = entity_index or record.entity_index
    record.last_seen = now
    if entity_index ~= nil then
        tracker.index_to_key[entity_index] = key
    end
    return record
end

--- Resets all match-scoped facts on an authoritative context change.
-- @param tracker Tracking store.
local function reset_match(tracker)
    tracker.records = {}
    tracker.index_to_key = {}
    tracker.events = {}
    tracker.scratch_present = {}
    tracker.phase_history = {}
    tracker.phase = nil
    tracker.local_userid = nil
    tracker.local_team = nil
    tracker.last_local_team = nil
end

--- Records a setup/running phase transition for exact piecewise integration.
-- The history is bounded; normal TF2 phase progression stays far below the cap.
-- @param tracker Tracking store.
-- @param phase `setup` or `running`.
-- @param now Current monotonic time.
local function update_phase(tracker, phase, now)
    if phase ~= "setup" then
        phase = "running"
    end
    if tracker.phase == phase then
        return
    end
    tracker.phase = phase
    local history = tracker.phase_history
    history[#history + 1] = {
        time = now,
        multiplier = phase == "setup" and Constants.SETUP_MULTIPLIER or 1,
    }
    if #history > Constants.PHASE_HISTORY_LIMIT then
        table.remove(history, 1)
    end
end

--- Applies a queued event only to its server-user-ID record.
-- Events establish lifecycle or trustworthy charge anchors but never select a
-- Medic by team, current selection, or entity index.
-- @param tracker Tracking store.
-- @param event Normalized primitive event.
-- @param now Current reconciliation time.
local function apply_event(tracker, event, now)
    local userid = Numbers.userid(event.userid)
    if userid == nil then
        return
    end
    local record = obtain_record(tracker, userid, nil, now)
    local name = event.name
    if name == "player_death" then
        set_alive(record, false, event.time or now)
        clear_gameplay(record, false)
    elseif name == "player_spawn" then
        set_alive(record, true, event.time or now)
        set_anchor(record, 0, event.time or now, false, "event")
        record.deployed = false
        record.deployment_source = "event"
        record.deployment_deadline = nil
    elseif name == "post_inventory_application" then
        set_anchor(record, 0, event.time or now, false, "event")
        record.deployed = false
        record.deployment_source = "event"
        record.deployment_deadline = nil
    elseif name == "player_chargedeployed" then
        -- The event has no family field. Defer its meter semantics until an
        -- already retained or newly overlaid family can identify whether this
        -- is a conventional full-charge deployment or a Vaccinator segment.
        record.pending_deployment_time = event.time or now
    elseif name == "player_team" then
        if record.team ~= event.team then
            clear_for_team_change(record, nil, nil)
        end
        record.team = event.team
    elseif name == "player_changeclass" then
        if record.class ~= event.class then
            clear_gameplay(record, event.class ~= Constants.MEDIC_CLASS)
        end
        record.class = event.class
    end
end

--- Removes per-frame overlay fields before the next reconciliation.
-- @param tracker Tracking store.
local function clear_frame_fields(tracker)
    for _, record in pairs(tracker.records) do
        record.frame_family = nil
        record.frame_family_source = nil
        record.frame_charge = nil
        record.frame_charge_source = nil
        record.frame_deployed = nil
        record.frame_deployment_source = nil
        record.frame_seen = false
        record.is_local = false
    end
end

--- Applies authoritative resource lifecycle rows and returns the present-key set.
-- @param tracker Tracking store.
-- @param players Snapshot player rows.
-- @param now Current time.
-- @return table Keys proven present by the complete roster.
local function apply_resource_lifecycle(tracker, players, now)
    local present = tracker.scratch_present
    clear_table(present)
    for i = 1, #players do
        local player = players[i]
        if player.resource_present then
            local record = obtain_record(
                tracker,
                player.userid,
                player.entity_index,
                now
            )
            if record ~= nil then
                present[record.key] = true
                record.connected = player.connected
                record.valid = player.valid
                if record.team ~= nil and player.team ~= nil
                    and record.team ~= player.team
                then
                    clear_for_team_change(
                        record,
                        player.class,
                        player.alive
                    )
                end
                if record.class ~= nil and player.class ~= nil
                    and record.class ~= player.class
                then
                    clear_gameplay(
                        record,
                        player.class ~= Constants.MEDIC_CLASS
                    )
                end
                record.team = player.team
                record.class = player.class
                set_alive(record, player.alive, now)
                record.resource_charge = player.resource_charge
                record.frame_seen = true
                if player.connected == false
                    or player.valid == false
                    or player.class ~= Constants.MEDIC_CLASS
                then
                    clear_gameplay(record, true)
                elseif player.alive == false then
                    clear_gameplay(record, false)
                end
            end
        end
    end
    return present
end

--- Applies current entity lifecycle and independent weapon fields.
-- Each validated current field overrides only its own older sources. Unsupported
-- family evidence invalidates retained supported-weapon facts without discarding
-- unrelated current lifecycle information.
-- @param tracker Tracking store.
-- @param players Snapshot player rows.
-- @param now Current time.
local function apply_current_overlay(tracker, players, now)
    for i = 1, #players do
        local player = players[i]
        if player.current_present then
            local record = obtain_record(
                tracker,
                player.userid,
                player.entity_index,
                now
            )
            if record ~= nil then
                record.frame_seen = true
                record.is_local = player.is_local == true
                if player.current_team ~= nil then
                    if record.team ~= nil and record.team ~= player.current_team then
                        clear_for_team_change(
                            record,
                            player.current_class,
                            player.current_alive
                        )
                    end
                    record.team = player.current_team
                end
                if player.current_class ~= nil then
                    if record.class ~= nil
                        and record.class ~= player.current_class
                    then
                        clear_gameplay(
                            record,
                            player.current_class ~= Constants.MEDIC_CLASS
                        )
                    end
                    record.class = player.current_class
                end
                if player.current_alive ~= nil then
                    set_alive(record, player.current_alive, now)
                    if player.current_alive == false then
                        clear_gameplay(record, false)
                    end
                end

                if player.current_family ~= nil then
                    if player.current_family == "UNSUPPORTED" then
                        clear_gameplay(record, true)
                        record.unsupported = true
                        record.frame_family = "UNSUPPORTED"
                        record.frame_family_source = "current"
                    elseif Weapons.is_displayable(player.current_family) then
                        if record.family ~= nil
                            and record.family ~= player.current_family
                        then
                            local pending = record.pending_deployment_time
                            clear_gameplay(record, false)
                            record.pending_deployment_time = pending
                        end
                        record.unsupported = false
                        record.family = player.current_family
                        record.frame_family = player.current_family
                        record.frame_family_source = "current"
                    end
                end
                if player.current_deployed ~= nil then
                    record.deployed = player.current_deployed
                    record.deployment_source = "current"
                    if player.current_deployed == false then
                        record.deployment_deadline = nil
                    end
                    record.frame_deployed = player.current_deployed
                    record.frame_deployment_source = "current"
                end
                if player.current_charge ~= nil then
                    record.frame_charge = player.current_charge
                    record.frame_charge_source = "current"
                end
            end
        end
    end
end

--- Applies deferred deployment semantics once a current or retained family is known.
-- Conventional families establish the existing 100% eight-second deployment.
-- Vaccinator events are intentionally ignored by limited support because they
-- reveal neither a comparable meter nor a continuing `m_bChargeRelease` state.
-- @param tracker Tracking store.
local function resolve_pending_deployments(tracker)
    for _, record in pairs(tracker.records) do
        local event_time = record.pending_deployment_time
        if event_time ~= nil then
            local family = record.frame_family or record.family
            if Weapons.is_supported(family) then
                set_anchor(record, 100, event_time, true, "event")
                if record.frame_deployed == nil then
                    record.deployed = true
                    record.deployment_source = "event"
                    record.deployment_deadline = event_time
                        + 100 / Constants.DEPLOY_DRAIN_RATE
                end
                record.pending_deployment_time = nil
            elseif family == "VACC" or record.unsupported == true then
                record.pending_deployment_time = nil
            end
        end
    end
end

--- Establishes current or resource charge anchors after all field overlays.
-- Current charge wins field-by-field and never waits for current family or
-- deployment. Resource charge is used only when the exact field is unavailable.
-- @param tracker Tracking store.
-- @param players Snapshot player rows.
-- @param now Current time.
local function apply_charge_sources(tracker, players, now)
    for i = 1, #players do
        local player = players[i]
        local key = record_key(player.userid, player.entity_index)
        local record = key ~= nil and tracker.records[key] or nil
        if record ~= nil and record.class == Constants.MEDIC_CLASS
            and record.alive == true
        then
            local charge = record.frame_charge
            local source = record.frame_charge_source
            if charge == nil and player.resource_charge ~= nil then
                charge = player.resource_charge
                source = "resource"
                record.frame_charge = charge
                record.frame_charge_source = source
            end
            if charge ~= nil then
                local deployed = record.frame_deployed
                if deployed == nil then
                    deployed = record.deployed == true
                end
                set_anchor(record, charge, now, deployed, source)
                if deployed then
                    if source == "current"
                        and record.frame_deployed == true
                    then
                        record.deployment_deadline = now
                            + charge / Constants.DEPLOY_DRAIN_RATE
                    elseif record.deployment_deadline == nil then
                        record.deployment_deadline = now
                            + charge / Constants.DEPLOY_DRAIN_RATE
                    end
                end
            end
        end
    end
end

--- Prunes records excluded by a complete roster and rebuilds index ownership.
-- @param tracker Tracking store.
-- @param present Keys proven present by the roster.
local function prune_authoritative(tracker, present)
    for key in pairs(tracker.records) do
        if not present[key] then
            tracker.records[key] = nil
        end
    end
    clear_table(tracker.index_to_key)
    for key, record in pairs(tracker.records) do
        if record.entity_index ~= nil then
            tracker.index_to_key[record.entity_index] = key
        end
    end
end

--- Enforces a conservative memory bound during prolonged roster outages.
-- @param tracker Tracking store.
local function prune_fallback_bound(tracker)
    local count = 0
    for _ in pairs(tracker.records) do
        count = count + 1
    end
    local excess = count - Constants.MAX_PLAYERS * 2
    if excess <= 0 then
        return
    end
    for key, record in pairs(tracker.records) do
        if excess > 0 and not record.frame_seen then
            tracker.records[key] = nil
            excess = excess - 1
        end
    end
    for key in pairs(tracker.records) do
        if excess <= 0 then
            break
        end
        tracker.records[key] = nil
        excess = excess - 1
    end
    clear_table(tracker.index_to_key)
    for key, record in pairs(tracker.records) do
        if record.entity_index ~= nil then
            tracker.index_to_key[record.entity_index] = key
        end
    end
end

--- Resolves one retained record into a plain selection candidate.
-- @param record Retained record.
-- @param now Current monotonic time.
-- @param phase_history Phase transitions used by immutable-anchor estimation.
-- @return table Candidate containing independently sourced fields.
local function resolve_candidate(record, now, phase_history)
    local family = record.frame_family or record.family
    local unsupported = record.unsupported == true
        or record.frame_family == "UNSUPPORTED"
    if unsupported then
        family = nil
    end
    local family_source = record.frame_family_source
        or (record.family ~= nil and "retained" or "unknown")
    local charge = record.frame_charge
    local charge_source = record.frame_charge_source
    local estimated_deployed
    if charge == nil and record.anchor ~= nil and Weapons.is_supported(family) then
        charge, estimated_deployed = Estimation.from_anchor(
            record.anchor,
            family,
            now,
            phase_history
        )
        if charge ~= nil then
            charge_source = "estimate"
        end
    end

    local deployed = record.frame_deployed
    local deployment_source = record.frame_deployment_source
    if deployed == nil and estimated_deployed ~= nil then
        deployed = estimated_deployed
        deployment_source = "estimate"
    elseif deployed == nil and record.deployed ~= nil then
        deployed = record.deployed
        deployment_source = record.deployment_source == "current"
            and "retained"
            or (record.deployment_source or "retained")
    elseif deployed == nil then
        deployment_source = "unknown"
    end

    return {
        userid = record.userid,
        entity_index = record.entity_index,
        team = record.team,
        class = record.class,
        alive = record.alive,
        is_local = record.is_local,
        family = family,
        family_source = family_source,
        charge = charge,
        charge_source = charge_source or "unknown",
        deployed = deployed,
        deployment_source = deployment_source,
        unsupported = unsupported,
    }
end

--- Advances a retained deployment through its fixed drain deadline.
-- This prevents an event-derived active state from sticking after the modeled
-- eight-second drain when current deployment becomes unavailable.
-- @param record Retained Medic record.
-- @param now Current monotonic time.
local function advance_deployment(record, now)
    if record.frame_deployed == nil
        and record.deployed == true
        and record.deployment_deadline ~= nil
        and now >= record.deployment_deadline
    then
        record.deployed = false
        record.deployment_source = "estimate"
        record.deployment_deadline = nil
    end
end

--- Reconciles queued events, resource roster, and current entity observations.
-- The precedence order follows the specification, and the returned view holds
-- primitives only. No LMAOBox Entity or GameEvent survives this call.
-- @param tracker Tracking store.
-- @param snapshot Validated primitive adapter snapshot.
-- @return table Latest tracking view for selection and state resolution.
function Tracking.reconcile(tracker, snapshot)
    local now = snapshot.now
    if snapshot.map ~= tracker.map then
        local initial_events = tracker.generation == 0 and tracker.events or nil
        reset_match(tracker)
        tracker.map = snapshot.map
        if initial_events ~= nil then
            tracker.events = initial_events
        end
    end
    update_phase(tracker, snapshot.phase, now)
    clear_frame_fields(tracker)

    local queued = tracker.events
    for i = 1, #queued do
        apply_event(tracker, queued[i], now)
        queued[i] = nil
    end

    local present = apply_resource_lifecycle(tracker, snapshot.players, now)
    apply_current_overlay(tracker, snapshot.players, now)
    resolve_pending_deployments(tracker)
    apply_charge_sources(tracker, snapshot.players, now)

    if snapshot.roster_available then
        prune_authoritative(tracker, present)
    else
        prune_fallback_bound(tracker)
    end

    local local_userid = snapshot.local_userid
    if tracker.local_userid ~= nil and local_userid ~= nil
        and tracker.local_userid ~= local_userid
    then
        -- A changed local identity must not inherit a prior player's local facts.
        local old = tracker.records["u:" .. tostring(tracker.local_userid)]
        if old ~= nil then
            old.is_local = false
        end
    end
    tracker.local_userid = local_userid or tracker.local_userid
    tracker.local_team = snapshot.local_team
    if snapshot.local_team == Constants.TEAM.RED
        or snapshot.local_team == Constants.TEAM.BLU
    then
        tracker.last_local_team = snapshot.local_team
    end
    tracker.generation = tracker.generation + 1

    local candidates = {}
    local dead_candidates = {}
    local alive_counts = snapshot.roster_available and {
        [Constants.TEAM.RED] = 0,
        [Constants.TEAM.BLU] = 0,
    } or nil
    local team_player_counts = snapshot.roster_available and {
        [Constants.TEAM.RED] = 0,
        [Constants.TEAM.BLU] = 0,
    } or nil
    local offclass_counts = snapshot.roster_available and {
        [Constants.TEAM.RED] = {
            [Constants.SNIPER_CLASS] = { total = 0, alive = 0 },
            [Constants.SPY_CLASS] = { total = 0, alive = 0 },
        },
        [Constants.TEAM.BLU] = {
            [Constants.SNIPER_CLASS] = { total = 0, alive = 0 },
            [Constants.SPY_CLASS] = { total = 0, alive = 0 },
        },
    } or nil
    local local_class = snapshot.local_class
    local local_alive = snapshot.local_alive
    for _, record in pairs(tracker.records) do
        if alive_counts ~= nil
            and record.connected == true
            and record.valid == true
            and record.alive == true
            and alive_counts[record.team] ~= nil
        then
            alive_counts[record.team] = alive_counts[record.team] + 1
        end
        if team_player_counts ~= nil
            and record.connected == true
            and record.valid == true
            and team_player_counts[record.team] ~= nil
        then
            team_player_counts[record.team] =
                team_player_counts[record.team] + 1
            local class_facts = offclass_counts[record.team][record.class]
            if class_facts ~= nil then
                class_facts.total = class_facts.total + 1
                if record.alive == true then
                    class_facts.alive = class_facts.alive + 1
                end
            end
        end
        if record.class == Constants.MEDIC_CLASS
            and record.connected ~= false and record.valid ~= false
        then
            if record.alive == true then
                advance_deployment(record, now)
                local candidate = resolve_candidate(
                    record,
                    now,
                    tracker.phase_history
                )
                candidates[#candidates + 1] = candidate
                if candidate.is_local
                    or candidate.userid == tracker.local_userid
                then
                    candidate.is_local = true
                    local_class = record.class
                    local_alive = record.alive
                end
            elseif record.alive == false then
                dead_candidates[#dead_candidates + 1] = {
                    userid = record.userid,
                    entity_index = record.entity_index,
                    team = record.team,
                    class = record.class,
                    alive = false,
                    dead = true,
                    family = record.family,
                    family_source = "retained",
                    unsupported = record.unsupported == true,
                    died_at = record.died_at,
                }
            end
        end
    end

    return {
        now = now,
        generation = tracker.generation,
        roster_available = snapshot.roster_available,
        alive_counts = alive_counts,
        team_player_counts = team_player_counts,
        offclass_counts = offclass_counts,
        candidates = candidates,
        dead_candidates = dead_candidates,
        local_userid = tracker.local_userid,
        local_team = tracker.local_team,
        last_local_team = tracker.last_local_team,
        local_class = local_class,
        local_alive = local_alive,
        is_casual = snapshot.is_casual,
        is_competitive = snapshot.is_competitive,
        is_tournament = snapshot.is_tournament,
        is_highlander = snapshot.is_highlander,
        configured_player_slots = snapshot.configured_player_slots,
    }
end

--- Releases all retained gameplay and queued-event state on unload.
-- @param tracker Tracking store.
function Tracking.clear(tracker)
    reset_match(tracker)
    tracker.map = nil
    tracker.last_local_team = nil
end

return Tracking
