--- Privacy-safe projections of live product and adapter state.
-- @module validation.views

local Views = {}
Views.__index = Views

--- Copies a primitive array into recorder-owned storage.
-- @param values Source array or nil.
-- @return table|nil Shallow primitive copy.
local function copy_array(values)
    if type(values) ~= "table" then
        return nil
    end
    local result = {}
    for index = 1, #values do
        result[index] = values[index]
    end
    return result
end

--- Returns a safe type description without retaining a raw identity value.
-- @param value Diagnostic raw primitive.
-- @return string Lua type or diagnostic sentinel.
local function raw_kind(value)
    if type(value) == "string" and string.sub(value, 1, 1) == "<" then
        return value
    end
    return type(value)
end

--- Creates a session-scoped identity projector.
-- @param charge_step Charge resolution used only for delta fingerprints.
-- @return table Projection state.
function Views.new(charge_step)
    return setmetatable({
        charge_step = charge_step,
        user_aliases = {},
        next_user_alias = 0,
    }, Views)
end

--- Quantizes charge for delta suppression without altering logged payloads.
-- @param value Exact or approximate charge percentage.
-- @param raw_fraction Whether the value is the raw zero-through-one netprop.
-- @return number|nil Quantized charge bucket.
function Views:charge_bucket(value, raw_fraction)
    if type(value) ~= "number" then
        return nil
    end
    local step = raw_fraction and self.charge_step / 100 or self.charge_step
    return math.floor(value / step + 0.5) * step
end

--- Returns an opaque alias for a positive server user ID.
-- Raw IDs never enter a projected record, while one stable alias proves
-- association across resource, entity, event, tracker, and selection data.
-- @param userid Positive server user ID or nil.
-- @return string|nil Session-local alias.
function Views:user_alias(userid)
    if type(userid) ~= "number" or userid <= 0
        or userid ~= math.floor(userid)
    then
        return nil
    end
    local alias = self.user_aliases[userid]
    if alias == nil then
        self.next_user_alias = self.next_user_alias + 1
        alias = "U" .. tostring(self.next_user_alias)
        self.user_aliases[userid] = alias
    end
    return alias
end

--- Converts a tracker key without exposing its raw user ID.
-- @param key Product tracker key.
-- @return string Privacy-safe key.
function Views:record_key(key)
    if type(key) ~= "string" then
        return "unknown"
    end
    local userid = tonumber(string.match(key, "^u:(%d+)$"))
    if userid ~= nil then
        return self:user_alias(userid) or "unknown"
    end
    local entity_index = string.match(key, "^e:(%d+)$")
    if entity_index ~= nil then
        return "E" .. entity_index
    end
    return "unknown"
end

--- Projects accepted adapter player values.
-- @param row Product snapshot row.
-- @return table Privacy-safe row.
function Views:snapshot_player(row)
    return {
        uid = self:user_alias(row.userid),
        entity_index = row.entity_index,
        resource_present = row.resource_present == true,
        connected = row.connected,
        valid = row.valid,
        alive = row.alive,
        team = row.team,
        class = row.class,
        resource_charge = row.resource_charge,
        current_present = row.current_present == true,
        is_local = row.is_local == true,
        current_team = row.current_team,
        current_class = row.current_class,
        current_alive = row.current_alive,
        current_family = row.current_family,
        current_charge = row.current_charge,
        current_deployed = row.current_deployed,
        current_equipped = row.current_equipped,
    }
end

--- Projects raw resource-row validation without writing the raw user ID.
-- @param row Adapter resource validation evidence.
-- @return table Privacy-safe resource evidence.
function Views:resource_row(row)
    return {
        uid = self:user_alias(row.userid),
        entity_index = row.entity_index,
        connected = row.connected,
        connected_raw_kind = raw_kind(row.connected_raw),
        valid = row.valid,
        valid_raw_kind = raw_kind(row.valid_raw),
        alive = row.alive,
        alive_raw_kind = raw_kind(row.alive_raw),
        team = row.team,
        team_raw_kind = raw_kind(row.team_raw),
        userid_valid = row.userid ~= nil,
        userid_raw_kind = raw_kind(row.userid_raw),
        class = row.class,
        class_raw_kind = raw_kind(row.class_raw),
        charge = row.charge,
        charge_raw = row.charge_raw,
        associated = row.associated == true,
    }
end

--- Projects current-player read and dormancy evidence.
-- @param row Current-player boundary evidence.
-- @return table Privacy-safe player evidence.
function Views:current_player(row)
    return {
        uid = self:user_alias(row.userid),
        entity_index = row.entity_index,
        valid_read = row.valid_read,
        valid_value = row.valid_value,
        dormant_read = row.dormant_read,
        dormant = row.dormant,
        non_dormant = row.non_dormant,
        team_read = row.team_read,
        team = row.team,
        class_read = row.class_read,
        class = row.class,
        alive_read = row.alive_read,
        alive = row.alive,
        active_read = row.active_read,
        active_index = row.active_index,
        active_is_medigun = row.active_is_medigun,
        loadout_read = row.loadout_read,
        loadout_index = row.loadout_index,
        loadout_is_medigun = row.loadout_is_medigun,
        rejected = row.rejected,
    }
end

--- Projects weapon ownership and independent field-read evidence.
-- @param row Adapter weapon diagnostic.
-- @return table Privacy-safe weapon evidence.
function Views:weapon(row)
    local reads = row.reads or {}
    return {
        uid = self:user_alias(row.userid),
        weapon_index = row.weapon_index,
        owner_read = row.owner_read,
        owner_index = row.owner_index,
        owner_hint = row.owner_hint,
        source_loadout = row.source_loadout,
        source_active = row.source_active,
        canonical = row.canonical,
        current = row.current,
        family = row.family,
        charge = row.charge,
        deployed = row.deployed,
        equipped = row.equipped,
        rejected = row.rejected,
        currency = reads.currency,
        valid_call = reads.valid_call,
        valid_value = reads.valid_value,
        dormant_call = reads.dormant_call,
        dormant = reads.dormant,
        player_non_dormant = reads.player_non_dormant,
        item_definition = reads.item_definition,
        family_path = reads.family_path,
        family_status = reads.family_status,
        family_nested_call = reads.family_nested_call,
        family_nested_value = reads.family_nested_value,
        family_flat_call = reads.family_flat_call,
        family_flat_value = reads.family_flat_value,
        charge_table = reads.charge_table,
        charge_call = reads.charge_call,
        charge_raw = reads.charge_raw,
        charge_status = reads.charge_status,
        deployment_call = reads.deployment_call,
        deployment_raw = reads.deployment_raw,
        deployment_status = reads.deployment_status,
        holstered_call = reads.holstered_call,
        holstered_raw = reads.holstered_raw,
    }
end

--- Projects a resolved candidate with independent source labels.
-- @param candidate Product selection candidate.
-- @return table Privacy-safe candidate evidence.
function Views:candidate(candidate)
    return {
        uid = self:user_alias(candidate.userid),
        entity_index = candidate.entity_index,
        team = candidate.team,
        class = candidate.class,
        alive = candidate.alive,
        is_local = candidate.is_local,
        family = candidate.family,
        family_source = candidate.family_source,
        charge = candidate.charge,
        charge_source = candidate.charge_source,
        deployed = candidate.deployed,
        deployment_source = candidate.deployment_source,
        unsupported = candidate.unsupported == true,
    }
end

--- Projects a retained tracker record, including its immutable anchor.
-- @param record Mutable product tracker record consumed synchronously.
-- @return table Privacy-safe retained-state evidence.
function Views:tracker_record(record)
    local anchor = record.anchor
    return {
        key = self:record_key(record.key),
        uid = self:user_alias(record.userid),
        entity_index = record.entity_index,
        created_at = record.created_at,
        last_seen = record.last_seen,
        connected = record.connected,
        valid = record.valid,
        team = record.team,
        class = record.class,
        alive = record.alive,
        resource_charge = record.resource_charge,
        family = record.family,
        unsupported = record.unsupported,
        deployed = record.deployed,
        deployment_source = record.deployment_source,
        deployment_deadline = record.deployment_deadline,
        frame_family = record.frame_family,
        frame_family_source = record.frame_family_source,
        frame_charge = record.frame_charge,
        frame_charge_source = record.frame_charge_source,
        frame_deployed = record.frame_deployed,
        frame_deployment_source = record.frame_deployment_source,
        frame_seen = record.frame_seen,
        is_local = record.is_local,
        anchor = anchor ~= nil and {
            charge = anchor.charge,
            time = anchor.time,
            deployed = anchor.deployed,
            source = anchor.source,
        } or nil,
    }
end

--- Projects a selected, unknown, or missing display side.
-- @param side Resolved product side.
-- @return table|nil Privacy-safe side evidence.
function Views:side(side)
    if side == nil then
        return nil
    end
    return {
        uid = self:user_alias(side.userid),
        entity_index = side.entity_index,
        team = side.team,
        missing = side.missing == true,
        family = side.family,
        family_source = side.family_source,
        charge = side.charge,
        charge_source = side.charge_source,
        deployed = side.deployed,
        deployment_source = side.deployment_source,
        unsupported = side.unsupported == true,
    }
end

--- Projects formatted HUD lines, colors, and warning state.
-- @param prepared Product formatting result or nil.
-- @return table|nil Recorder-owned display view.
function Views.prepared(prepared)
    if prepared == nil then
        return nil
    end
    return {
        lines = copy_array(prepared.lines),
        colors = {
            copy_array(prepared.colors[1]),
            copy_array(prepared.colors[2]),
            copy_array(prepared.colors[3]),
        },
        warning = prepared.warning == true,
    }
end

--- Projects the full product decision and formatted output.
-- @param info Controller capture notification.
-- @return table Privacy-safe decision evidence.
function Views:decision(info)
    local model = info.model
    local decision = {
        capture_sequence = info.sequence,
        capture_source = info.source,
        capture_stage = info.stage,
        roster_available = info.tracking.roster_available,
        local_uid = self:user_alias(info.tracking.local_userid),
        local_team = info.tracking.local_team,
        local_class = info.tracking.local_class,
        local_alive = info.tracking.local_alive,
        local_side = model ~= nil and self:side(model.local_side) or nil,
        enemy_side = model ~= nil and self:side(model.enemy_side) or nil,
        comparison = model ~= nil and model.comparison or nil,
        prepared = Views.prepared(info.prepared),
    }
    -- Lua's `a and false or nil` idiom loses a legitimate false value. Assign
    -- explicitly so team-comparison mode remains distinguishable from no model.
    if model ~= nil then
        decision.self_mode = model.self_mode
    end
    return decision
end

return Views
