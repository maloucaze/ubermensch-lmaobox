-- SPDX-License-Identifier: MIT
-- luacheck: globals entities client globals callbacks filesystem
-- luacheck: globals E_ClientFrameStage E_LoadoutSlot

--- Live LMAOBox boundary probe for the Ubermensch 2.0 rebuild.
--
-- This temporary diagnostic performs no gameplay writes. It records only the
-- information needed to verify the production adapter's read paths, identity
-- associations, update timing, and PVS/dormancy behavior.

local PROBE_VERSION = "1.0.2"
local PREFIX = "[Ubermensch Probe]"
local SAMPLE_INTERVAL = 0.25
local HEARTBEAT_INTERVAL = 2.0
local MEDIC_CLASS = 5
local DEFAULT_MAX_CLIENTS = 64
local DOCUMENTED_FRAME_NET_UPDATE_END = 4
local DOCUMENTED_SECONDARY_SLOT = 1

local CALLBACKS = {
    frame_stage = "ubermensch.probe.frame_stage",
    draw = "ubermensch.probe.draw",
    event = "ubermensch.probe.event",
    unload = "ubermensch.probe.unload",
}

local RELEVANT_EVENTS = {
    player_spawn = true,
    player_death = true,
    player_changeclass = true,
    player_team = true,
    post_inventory_application = true,
    player_chargedeployed = true,
}

local ITEM_FAMILY = {
    [29] = "STOCK",
    [211] = "STOCK",
    [663] = "STOCK",
    [796] = "STOCK",
    [805] = "STOCK",
    [885] = "STOCK",
    [894] = "STOCK",
    [903] = "STOCK",
    [912] = "STOCK",
    [961] = "STOCK",
    [970] = "STOCK",
    [15008] = "STOCK",
    [15010] = "STOCK",
    [15025] = "STOCK",
    [15039] = "STOCK",
    [15050] = "STOCK",
    [15078] = "STOCK",
    [15097] = "STOCK",
    [15120] = "STOCK",
    [15121] = "STOCK",
    [15122] = "STOCK",
    [15145] = "STOCK",
    [15146] = "STOCK",
    [35] = "KRITZ",
    [411] = "QUICK-FIX",
    [998] = "VACCINATOR",
}

local unpack_values = unpack or table.unpack

local state = {
    started_at = 0,
    stopped = false,
    log_handle = nil,
    log_path = nil,
    sequence = 0,
    latest_capture_at = nil,
    latest_capture_frame = nil,
    latest_capture_sequence = 0,
    last_draw_sequence = 0,
    last_sample_at = nil,
    last_full_log_at = nil,
    last_signature = nil,
    previous_players = {},
    previous_weapons = {},
}

--- Calls an object method without allowing a volatile host failure to abort the probe.
-- @param object Object that owns the method.
-- @param method_name Method name to invoke.
-- @param ... Arguments passed after the object receiver.
-- @return boolean Whether the method returned without raising an error.
-- @return any Method result, or the error object when the call failed.
local function call_method(object, method_name, ...)
    if object == nil then
        return false, "object unavailable"
    end

    local arguments = { ... }
    local argument_count = select("#", ...)
    return pcall(function()
        return object[method_name](object, unpack_values(arguments, 1, argument_count))
    end)
end

--- Calls a LMAOBox library member while preserving nil and error outcomes.
-- @param library Library table or native proxy container.
-- @param function_name Member name to invoke.
-- @param ... Arguments passed to the library function.
-- @return boolean Whether the function returned without raising an error.
-- @return any Function result, or the error object when the call failed.
local function call_library(library, function_name, ...)
    if library == nil then
        return false, "library unavailable"
    end

    local arguments = { ... }
    local argument_count = select("#", ...)
    return pcall(function()
        return library[function_name](unpack_values(arguments, 1, argument_count))
    end)
end

--- Reports whether a required library member is present without assuming it is a Lua function.
-- Native LMAOBox callables may be proxies rather than values whose type is
-- `function`, so presence is the only safe startup check.
-- @param container Library table or proxy container.
-- @param member_name Member to inspect.
-- @return boolean Whether indexing succeeded and produced a non-nil value.
local function has_member(container, member_name)
    if container == nil then
        return false
    end

    local ok, value = pcall(function()
        return container[member_name]
    end)
    return ok and value ~= nil
end

--- Produces one-line, deterministic text for a raw probe result.
-- @param value Value returned by LMAOBox or Lua.
-- @return string Printable representation safe for the line-oriented log.
local function format_value(value)
    local value_type = type(value)
    if value == nil then
        return "nil"
    end
    if value_type == "boolean" then
        return value and "true" or "false"
    end
    if value_type == "number" then
        if value ~= value then
            return "nan"
        end
        if value == math.huge then
            return "inf"
        end
        if value == -math.huge then
            return "-inf"
        end
        return string.format("%.6f", value)
    end

    local text = tostring(value)
    text = string.gsub(text, "[\r\n\t]", " ")
    return text
end

--- Formats a protected read so nil and thrown errors remain distinguishable.
-- @param ok Whether the protected call succeeded.
-- @param value Result or error returned by the protected call.
-- @return string `ok:<value>`, `nil`, or `error:<message>`.
local function format_read(ok, value)
    if not ok then
        return "error:" .. format_value(value)
    end
    if value == nil then
        return "nil"
    end
    return "ok:" .. format_value(value)
end

--- Reads the monotonic clock used to correlate network capture, events, and Draw.
-- @return number Seconds since game start, or `os.clock()` as a diagnostic fallback.
local function now()
    local ok, value = call_library(globals, "RealTime")
    if ok and type(value) == "number" and value == value then
        return value
    end
    if os ~= nil and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

--- Reads the current frame number when the optional API is available.
-- @return number|nil Current frame count, or nil when unreadable.
local function frame_count()
    local ok, value = call_library(globals, "FrameCount")
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

--- Resolves an entity index without retaining or stringifying the entity object.
-- @param entity Transient LMAOBox Entity.
-- @return number|nil Entity index when readable.
local function entity_index(entity)
    local ok, value = call_method(entity, "GetIndex")
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

--- Reads the user id exposed by `client.GetPlayerInfo` for an entity index.
-- @param index Player entity index.
-- @return number|nil Positive server user id when available.
local function player_info_userid(index)
    if type(index) ~= "number" then
        return nil
    end

    local ok, info = call_library(client, "GetPlayerInfo", index)
    if not ok or type(info) ~= "table" then
        return nil
    end

    local userid = info.UserID
    if type(userid) == "number" and userid > 0 then
        return userid
    end
    return nil
end

--- Resolves a documented enum member while retaining its numeric fallback.
-- @param enum_table LMAOBox enum table, which may be unavailable on a host build.
-- @param member_name Enum member to inspect.
-- @param fallback Numeric value published by the current official documentation.
-- @return number Resolved enum value.
-- @return string `enum` when resolved from the host or `documented-fallback` otherwise.
local function resolve_enum(enum_table, member_name, fallback)
    if enum_table ~= nil then
        local ok, value = pcall(function()
            return enum_table[member_name]
        end)
        if ok and type(value) == "number" then
            return value, "enum"
        end
    end
    return fallback, "documented-fallback"
end

local NETWORK_UPDATE_END, NETWORK_UPDATE_END_SOURCE = resolve_enum(
    E_ClientFrameStage,
    "FRAME_NET_UPDATE_END",
    DOCUMENTED_FRAME_NET_UPDATE_END
)
local SECONDARY_SLOT, SECONDARY_SLOT_SOURCE = resolve_enum(
    E_LoadoutSlot,
    "LOADOUT_POSITION_SECONDARY",
    DOCUMENTED_SECONDARY_SLOT
)

--- Adds a distinct, usable path to the ordered log-path candidates.
-- @param candidates Ordered candidate-path table to mutate.
-- @param seen Set of paths already added.
-- @param path Raw path returned by a host API or constructed by the probe.
local function append_log_path(candidates, seen, path)
    if type(path) ~= "string" or path == "" or seen[path] then
        return
    end
    candidates[#candidates + 1] = path
    seen[path] = true
end

--- Chooses log locations in the order most likely to satisfy host restrictions.
-- LMAOBox may deny `io.open` outside TF2 even when Lua can read the process
-- environment. Its filesystem API provides the full path of a directory it
-- created relative to the game directory, so that path is preferred.
-- @return table Ordered paths for the caller to try.
local function resolve_log_paths()
    local candidates = {}
    local seen = {}
    local directory_ok, _, directory = call_library(
        filesystem,
        "CreateDirectory",
        "ubermensch_probe"
    )
    if directory_ok and type(directory) == "string" and directory ~= "" then
        append_log_path(
            candidates,
            seen,
            directory .. "\\ubermensch_probe_log.txt"
        )
    end
    -- Try the relative form even when an existing directory causes the host to
    -- return false: the path can still be writable and `io.open` decides.
    append_log_path(
        candidates,
        seen,
        "ubermensch_probe\\ubermensch_probe_log.txt"
    )

    if os ~= nil and type(os.getenv) == "function" then
        local ok, local_app_data = pcall(function()
            return os.getenv("LOCALAPPDATA")
        end)
        if ok and type(local_app_data) == "string" and local_app_data ~= "" then
            append_log_path(
                candidates,
                seen,
                local_app_data .. "\\lua\\ubermensch_probe_log.txt"
            )
        end
    end

    append_log_path(candidates, seen, "ubermensch_probe_log.txt")
    return candidates
end

--- Describes one failed attempt to open a candidate log file.
-- @param path Candidate path passed to `io.open`.
-- @param protected_ok Whether the protected call itself completed.
-- @param handle File handle, nil result, or raised error object.
-- @param open_error Standard `io.open` error detail when supplied by the host.
-- @return string Single-line failure suitable for the startup diagnostic.
local function format_open_failure(path, protected_ok, handle, open_error)
    local reason = protected_ok and open_error or handle
    return string.format(
        "%s (%s)",
        path,
        reason == nil and "no error detail" or format_value(reason)
    )
end

--- Opens a fresh log file for the current probe run.
-- @return boolean Whether file logging is available.
-- @return string|nil Error text when the file could not be opened.
local function open_log()
    if io == nil or type(io.open) ~= "function" then
        return false, "io.open unavailable"
    end

    local failures = {}
    local candidates = resolve_log_paths()
    for i = 1, #candidates do
        local path = candidates[i]
        local ok, handle, open_error = pcall(io.open, path, "w")
        if ok and handle ~= nil then
            state.log_path = path
            state.log_handle = handle
            return true, nil
        end
        failures[#failures + 1] = format_open_failure(
            path,
            ok,
            handle,
            open_error
        )
    end

    state.log_path = "console-only"
    return false, table.concat(failures, "; ")
end

--- Emits a timestamped probe record to the file and, when useful, the console.
-- @param message Record body without a timestamp or prefix.
-- @param announce Whether to echo the record to the LMAOBox console.
local function emit(message, announce)
    local elapsed = now() - state.started_at
    local line = string.format("%s t=%.3f %s", PREFIX, elapsed, message)

    if state.log_handle ~= nil then
        local ok = pcall(function()
            state.log_handle:write(line, "\n")
            state.log_handle:flush()
        end)
        if not ok then
            pcall(function()
                state.log_handle:close()
            end)
            state.log_handle = nil
            print(PREFIX .. " log write failed; continuing in console only")
        end
    end

    if announce or state.log_handle == nil then
        print(line)
    end
end

--- Reads a complete player-resource data table and records its availability.
-- @param resource Transient `CTFPlayerResource` entity.
-- @param method_name Typed data-table getter.
-- @param prop_name Netprop name.
-- @return table|nil Lua table returned by LMAOBox.
-- @return string Diagnostic status for the read.
local function read_resource_table(resource, method_name, prop_name)
    local ok, value = call_method(resource, method_name, prop_name)
    if not ok then
        return nil, "error:" .. format_value(value)
    end
    if value == nil then
        return nil, "nil"
    end
    if type(value) ~= "table" then
        return nil, "wrong-type:" .. type(value)
    end
    return value, "ok"
end

--- Reads all roster tables used by the proposed production adapter.
-- @param resource Transient `CTFPlayerResource` entity.
-- @return table Tables keyed by logical field name.
-- @return string One-line availability summary for every raw table.
local function collect_resource_tables(resource)
    local result = {}
    local statuses = {}
    local definitions = {
        { "connected", "GetPropDataTableBool", "m_bConnected" },
        { "valid", "GetPropDataTableBool", "m_bValid" },
        { "alive", "GetPropDataTableBool", "m_bAlive" },
        { "team", "GetPropDataTableInt", "m_iTeam" },
        { "userid", "GetPropDataTableInt", "m_iUserID" },
        { "class", "GetPropDataTableInt", "m_iPlayerClass" },
        { "charge", "GetPropDataTableInt", "m_iChargeLevel" },
    }

    for i = 1, #definitions do
        local definition = definitions[i]
        local values, status = read_resource_table(
            resource,
            definition[2],
            definition[3]
        )
        result[definition[1]] = values
        statuses[#statuses + 1] = definition[1] .. "=" .. status
    end

    return result, table.concat(statuses, " ")
end

--- Converts a TF2 entity index to the corresponding Lua data-table index.
-- LMAOBox exposes network arrays as ordinary 1-based Lua tables, so entity
-- index 1 is stored at table index 2.
-- @param player_index TF2 player entity index.
-- @return number|nil One-based Lua table index, or nil for an invalid input.
local function resource_table_index(player_index)
    if type(player_index) ~= "number" or player_index < 0 then
        return nil
    end
    return math.floor(player_index) + 1
end

--- Reads one resource value while preserving a missing-table distinction.
-- @param values Resource table or nil when its typed read failed.
-- @param player_index TF2 player entity index, not the Lua table index.
-- @return any Value stored for that entity, or nil.
local function resource_value(values, player_index)
    if values == nil then
        return nil
    end
    local table_index = resource_table_index(player_index)
    if table_index == nil then
        return nil
    end
    return values[table_index]
end

--- Returns the server's player-slot capacity with a conservative fallback.
-- @return number Positive maximum slot count.
-- @return string `api` or `fallback` to identify the source.
local function max_clients()
    local ok, value = call_library(globals, "MaxClients")
    if ok and type(value) == "number" and value >= 1 then
        return math.floor(value), "api"
    end
    return DEFAULT_MAX_CLIENTS, "fallback"
end

--- Reads a player entity's essential identity and weapon-discovery fields.
-- @param player Transient `CTFPlayer` entity.
-- @param resources Resource tables for corroborating identity.
-- @return table Plain diagnostic record with no retained entity references.
local function inspect_player(player, resources)
    local index = entity_index(player)
    local class_ok, class_value = call_method(player, "GetPropInt", "m_PlayerClass", "m_iClass")
    local team_ok, team_value = call_method(player, "GetTeamNumber")
    local alive_ok, alive_value = call_method(player, "IsAlive")
    local dormant_ok, dormant_value = call_method(player, "IsDormant")
    local active_ok, active_weapon = call_method(player, "GetPropEntity", "m_hActiveWeapon")
    local loadout_ok, loadout_weapon = call_method(
        player,
        "GetEntityForLoadoutSlot",
        SECONDARY_SLOT
    )

    local active_medigun_ok, active_medigun = call_method(active_weapon, "IsMedigun")
    local loadout_medigun_ok, loadout_medigun = call_method(loadout_weapon, "IsMedigun")
    local resource_class = resource_value(resources.class, index)

    return {
        index = index,
        userid = player_info_userid(index),
        resource_userid = resource_value(resources.userid, index),
        class_ok = class_ok,
        class_value = class_value,
        resource_class = resource_class,
        team_ok = team_ok,
        team_value = team_value,
        resource_team = resource_value(resources.team, index),
        alive_ok = alive_ok,
        alive_value = alive_value,
        resource_alive = resource_value(resources.alive, index),
        dormant_ok = dormant_ok,
        dormant_value = dormant_value,
        active_ok = active_ok,
        active_weapon = active_weapon,
        active_index = entity_index(active_weapon),
        active_medigun_ok = active_medigun_ok,
        active_medigun = active_medigun,
        loadout_ok = loadout_ok,
        loadout_weapon = loadout_weapon,
        loadout_index = entity_index(loadout_weapon),
        loadout_medigun_ok = loadout_medigun_ok,
        loadout_medigun = loadout_medigun,
    }
end

--- Determines whether a player record is relevant to Medi Gun discovery.
-- @param record Plain record returned by `inspect_player`.
-- @return boolean Whether the record should appear in the diagnostic log.
local function is_medic_record(record)
    return record.class_value == MEDIC_CLASS
        or record.resource_class == MEDIC_CLASS
        or record.loadout_medigun == true
end

--- Converts a player record into a stable, line-oriented diagnostic row.
-- @param record Plain record returned by `inspect_player`.
-- @return string Player diagnostic row.
local function format_player(record)
    return string.format(
        "PLAYER idx=%s userid=%s resource_userid=%s class=%s resource_class=%s "
            .. "team=%s resource_team=%s alive=%s resource_alive=%s dormant=%s "
            .. "active_weapon=%s active_is_medigun=%s loadout_secondary=%s "
            .. "loadout_is_medigun=%s",
        format_value(record.index),
        format_value(record.userid),
        format_value(record.resource_userid),
        format_read(record.class_ok, record.class_value),
        format_value(record.resource_class),
        format_read(record.team_ok, record.team_value),
        format_value(record.resource_team),
        format_read(record.alive_ok, record.alive_value),
        format_value(record.resource_alive),
        format_read(record.dormant_ok, record.dormant_value),
        record.active_ok and format_value(record.active_index) or "error",
        format_read(record.active_medigun_ok, record.active_medigun),
        record.loadout_ok and format_value(record.loadout_index) or "error",
        format_read(record.loadout_medigun_ok, record.loadout_medigun)
    )
end

--- Adds resource-only Medic rows so distant roster visibility is explicit.
-- @param rows Destination array of log lines.
-- @param resources Resource tables returned by `collect_resource_tables`.
-- @param player_by_index Current entity records indexed by player slot.
-- @param maximum Maximum player slot to inspect.
local function append_resource_medics(rows, resources, player_by_index, maximum)
    for player_index = 1, maximum do
        if resource_value(resources.class, player_index) == MEDIC_CLASS then
            rows[#rows + 1] = string.format(
                "RESOURCE_MEDIC entity_idx=%d table_idx=%d connected=%s valid=%s "
                    .. "alive=%s team=%s userid=%s class=%s charge=%s "
                    .. "entity_present=%s",
                player_index,
                resource_table_index(player_index),
                format_value(resource_value(resources.connected, player_index)),
                format_value(resource_value(resources.valid, player_index)),
                format_value(resource_value(resources.alive, player_index)),
                format_value(resource_value(resources.team, player_index)),
                format_value(resource_value(resources.userid, player_index)),
                format_value(resource_value(resources.class, player_index)),
                format_value(resource_value(resources.charge, player_index)),
                player_by_index[player_index] ~= nil and "true" or "false"
            )
        end
    end
end

--- Adds or augments one transient Medi Gun candidate without duplicating it.
-- @param candidates Ordered candidate records to mutate.
-- @param by_key Candidate records indexed by weapon identity.
-- @param weapon Transient weapon entity obtained from a host discovery path.
-- @param source Discovery path, such as `direct`, `loadout`, or `active`.
-- @param owner_hint Player entity index associated by a per-player lookup.
local function add_weapon_candidate(candidates, by_key, weapon, source, owner_hint)
    if weapon == nil then
        return
    end

    local index = entity_index(weapon)
    local key = index == nil and tostring(weapon) or tostring(index)
    local candidate = by_key[key]
    if candidate == nil then
        candidate = {
            key = key,
            weapon = weapon,
            owner_hint = owner_hint,
            sources = {},
        }
        candidates[#candidates + 1] = candidate
        by_key[key] = candidate
    elseif candidate.owner_hint == nil and owner_hint ~= nil then
        candidate.owner_hint = owner_hint
    end
    candidate.sources[source] = true
end

--- Combines direct enumeration with per-player active/loadout discovery.
-- Direct `CWeaponMedigun` enumeration is retained as evidence, but loadout
-- lookup is essential on hosts where that enumeration returns an empty table.
-- @param direct_weapons Raw result of `entities.FindByClass`.
-- @param players Player records returned by `inspect_player`.
-- @return table Deduplicated transient weapon candidate records.
local function collect_weapon_candidates(direct_weapons, players)
    local candidates = {}
    local by_key = {}

    for i = 1, #direct_weapons do
        add_weapon_candidate(candidates, by_key, direct_weapons[i], "direct", nil)
    end
    for owner_index, player in pairs(players) do
        if player.loadout_medigun == true then
            add_weapon_candidate(
                candidates,
                by_key,
                player.loadout_weapon,
                "loadout",
                owner_index
            )
        end
        if player.active_medigun == true then
            add_weapon_candidate(
                candidates,
                by_key,
                player.active_weapon,
                "active",
                owner_index
            )
        end
    end

    table.sort(candidates, function(left, right)
        return left.key < right.key
    end)
    return candidates
end

--- Formats the discovery paths that exposed one weapon candidate.
-- @param sources Set of source labels.
-- @return string Sorted comma-separated source labels.
local function format_sources(sources)
    local result = {}
    for source in pairs(sources) do
        result[#result + 1] = source
    end
    table.sort(result)
    return table.concat(result, ",")
end

--- Reads one Medi Gun and its owner through every path needed by the adapter.
-- @param candidate Transient weapon plus its discovery and owner context.
-- @param resources Resource tables for corroborating owner identity.
-- @param players Current player records indexed by entity index.
-- @return string Stable diagnostic row.
-- @return string|nil Weapon key used to detect appearance/disappearance.
local function inspect_weapon(candidate, resources, players)
    local weapon = candidate.weapon
    local weapon_index = entity_index(weapon)
    local dormant_ok, dormant_value = call_method(weapon, "IsDormant")
    local class_ok, class_value = call_method(weapon, "GetClass")
    local is_medigun_ok, is_medigun_value = call_method(weapon, "IsMedigun")
    local owner_ok, owner = call_method(weapon, "GetPropEntity", "m_hOwner")
    local direct_owner_index = entity_index(owner)
    local owner_index = direct_owner_index or candidate.owner_hint
    local owner_source = direct_owner_index ~= nil and "netprop"
        or (candidate.owner_hint ~= nil and "player-lookup" or "unavailable")
    local owner_record = players[owner_index]
    local owner_userid = player_info_userid(owner_index)
    local resource_userid = resource_value(resources.userid, owner_index)

    local nested_item_ok, nested_item = call_method(
        weapon,
        "GetPropInt",
        "m_AttributeManager",
        "m_Item",
        "m_iItemDefinitionIndex"
    )
    local bare_item_ok, bare_item = call_method(weapon, "GetPropInt", "m_iItemDefinitionIndex")
    local family = ITEM_FAMILY[nested_item] or ITEM_FAMILY[bare_item] or "UNMAPPED"

    local holstered_ok, holstered_value = call_method(weapon, "GetPropBool", "m_bHolstered")
    local deployed_ok, deployed_value = call_method(weapon, "GetPropBool", "m_bChargeRelease")
    local local_charge_ok, local_charge = call_method(
        weapon,
        "GetPropFloat",
        "LocalTFWeaponMedigunData",
        "m_flChargeLevel"
    )
    local nonlocal_charge_ok, nonlocal_charge = call_method(
        weapon,
        "GetPropFloat",
        "NonLocalTFWeaponMedigunData",
        "m_flChargeLevel"
    )
    local bare_charge_ok, bare_charge = call_method(weapon, "GetPropFloat", "m_flChargeLevel")

    local local_player_ok, local_player = call_library(entities, "GetLocalPlayer")
    local local_index = local_player_ok and entity_index(local_player) or nil
    local is_local_owner = owner_index ~= nil and owner_index == local_index
    local active_match = owner_record ~= nil
        and owner_record.active_index ~= nil
        and owner_record.active_index == weapon_index
    local loadout_match = owner_record ~= nil
        and owner_record.loadout_index ~= nil
        and owner_record.loadout_index == weapon_index

    local row = string.format(
        "WEAPON idx=%s sources=%s class=%s is_medigun=%s dormant=%s "
            .. "owner_read=%s owner_source=%s owner_idx=%s owner_userid=%s "
            .. "resource_userid=%s local_owner=%s "
            .. "active_match=%s loadout_match=%s holstered=%s item_nested=%s "
            .. "item_bare=%s family=%s charge_local=%s charge_nonlocal=%s "
            .. "charge_bare=%s deployed=%s",
        format_value(weapon_index),
        format_sources(candidate.sources),
        format_read(class_ok, class_value),
        format_read(is_medigun_ok, is_medigun_value),
        format_read(dormant_ok, dormant_value),
        owner_ok and "ok" or "error",
        owner_source,
        format_value(owner_index),
        format_value(owner_userid),
        format_value(resource_userid),
        is_local_owner and "true" or "false",
        active_match and "true" or "false",
        loadout_match and "true" or "false",
        format_read(holstered_ok, holstered_value),
        format_read(nested_item_ok, nested_item),
        format_read(bare_item_ok, bare_item),
        family,
        format_read(local_charge_ok, local_charge),
        format_read(nonlocal_charge_ok, nonlocal_charge),
        format_read(bare_charge_ok, bare_charge),
        format_read(deployed_ok, deployed_value)
    )

    if weapon_index == nil then
        return row, nil
    end
    return row, tostring(weapon_index)
end

--- Collects a complete diagnostic snapshot using only transient host objects.
-- @return table Ordered log rows describing context, roster, players, and weapons.
-- @return table Set of relevant player indexes.
-- @return table Set of Medi Gun indexes observed by any discovery path.
local function collect_snapshot()
    local rows = {}
    local player_set = {}
    local weapon_set = {}

    local maximum, maximum_source = max_clients()
    local resource_ok, resource = call_library(entities, "GetPlayerResources")
    local resources = {}
    local resource_status = "resource=" .. format_read(resource_ok, resource)
    if resource_ok and resource ~= nil then
        resources, resource_status = collect_resource_tables(resource)
    end

    local local_ok, local_player = call_library(entities, "GetLocalPlayer")
    local local_index = local_ok and entity_index(local_player) or nil
    local local_userid = player_info_userid(local_index)

    local players_ok, player_entities = call_library(entities, "FindByClass", "CTFPlayer")
    if not players_ok or type(player_entities) ~= "table" then
        player_entities = {}
    end

    local player_records = {}
    local player_lines = {}
    for i = 1, #player_entities do
        local record = inspect_player(player_entities[i], resources)
        if record.index ~= nil then
            player_records[record.index] = record
        end
        if is_medic_record(record) then
            player_lines[#player_lines + 1] = format_player(record)
            if record.index ~= nil then
                player_set[tostring(record.index)] = true
            end
        end
    end
    table.sort(player_lines)

    local weapons_ok, direct_weapon_entities = call_library(
        entities,
        "FindByClass",
        "CWeaponMedigun"
    )
    if not weapons_ok or type(direct_weapon_entities) ~= "table" then
        direct_weapon_entities = {}
    end

    local weapon_candidates = collect_weapon_candidates(
        direct_weapon_entities,
        player_records
    )
    local weapon_lines = {}
    for i = 1, #weapon_candidates do
        local row, key = inspect_weapon(weapon_candidates[i], resources, player_records)
        weapon_lines[#weapon_lines + 1] = row
        if key ~= nil then
            weapon_set[key] = true
        end
    end
    table.sort(weapon_lines)

    rows[#rows + 1] = string.format(
        "CONTEXT local_idx=%s local_userid=%s max_clients=%d max_source=%s "
            .. "players_call=%s players_count=%d weapons_call=%s "
            .. "direct_weapons_count=%d observed_weapons_count=%d",
        format_value(local_index),
        format_value(local_userid),
        maximum,
        maximum_source,
        players_ok and "ok" or "error",
        #player_entities,
        weapons_ok and "ok" or "error",
        #direct_weapon_entities,
        #weapon_candidates
    )
    rows[#rows + 1] = "RESOURCE_TABLES " .. resource_status

    append_resource_medics(rows, resources, player_records, maximum)
    for i = 1, #player_lines do
        rows[#rows + 1] = player_lines[i]
    end
    for i = 1, #weapon_lines do
        rows[#rows + 1] = weapon_lines[i]
    end

    return rows, player_set, weapon_set
end

--- Logs which tracked indexes appeared or disappeared between snapshots.
-- @param label `PLAYER` or `WEAPON`.
-- @param previous Set from the preceding sample.
-- @param current Set from the current sample.
local function log_set_transitions(label, previous, current)
    for key in pairs(current) do
        if not previous[key] then
            emit("TRANSITION " .. label .. "_APPEARED idx=" .. key, true)
        end
    end
    for key in pairs(previous) do
        if not current[key] then
            emit("TRANSITION " .. label .. "_DISAPPEARED idx=" .. key, true)
        end
    end
end

--- Finds resource/entity indexes currently carrying a server user id.
-- @param userid Positive server user id from a game event.
-- @return string Comma-separated `entity-index:table-index` pairs or `none`.
local function resource_slots_for_userid(userid)
    if type(userid) ~= "number" or userid <= 0 then
        return "none"
    end

    local resource_ok, resource = call_library(entities, "GetPlayerResources")
    if not resource_ok or resource == nil then
        return "resource-unavailable"
    end

    local values = read_resource_table(resource, "GetPropDataTableInt", "m_iUserID")
    if values == nil then
        return "userid-table-unavailable"
    end

    local maximum = max_clients()
    local slots = {}
    for player_index = 1, maximum do
        if resource_value(values, player_index) == userid then
            slots[#slots + 1] = string.format(
                "%d:%d",
                player_index,
                resource_table_index(player_index)
            )
        end
    end
    if #slots == 0 then
        return "none"
    end
    return table.concat(slots, ",")
end

--- Captures the observable Medi Gun owner map at a relevant event boundary.
-- @return string Comma-separated `userid:player-index:weapon-index:sources` entries.
local function current_weapon_owner_map()
    local players_ok, player_entities = call_library(entities, "FindByClass", "CTFPlayer")
    if not players_ok or type(player_entities) ~= "table" then
        player_entities = {}
    end

    local player_records = {}
    for i = 1, #player_entities do
        local record = inspect_player(player_entities[i], {})
        if record.index ~= nil then
            player_records[record.index] = record
        end
    end

    local weapons_ok, direct_weapons = call_library(
        entities,
        "FindByClass",
        "CWeaponMedigun"
    )
    if not weapons_ok or type(direct_weapons) ~= "table" then
        direct_weapons = {}
    end
    if not players_ok and not weapons_ok then
        return "enumeration-unavailable"
    end

    local candidates = collect_weapon_candidates(direct_weapons, player_records)
    local entries = {}
    for i = 1, #candidates do
        local candidate = candidates[i]
        local weapon = candidate.weapon
        local owner_ok, owner = call_method(weapon, "GetPropEntity", "m_hOwner")
        local owner_index = owner_ok and entity_index(owner) or candidate.owner_hint
        entries[#entries + 1] = string.format(
            "%s:%s:%s:%s",
            format_value(player_info_userid(owner_index)),
            format_value(owner_index),
            format_value(entity_index(weapon)),
            format_sources(candidate.sources)
        )
    end
    table.sort(entries)
    if #entries == 0 then
        return "none"
    end
    return table.concat(entries, ",")
end

local function on_frame_stage(stage)
    if state.stopped or stage ~= NETWORK_UPDATE_END then
        return
    end

    local captured_at = now()
    if state.last_sample_at ~= nil
        and captured_at - state.last_sample_at < SAMPLE_INTERVAL
    then
        return
    end

    state.last_sample_at = captured_at
    state.sequence = state.sequence + 1
    state.latest_capture_sequence = state.sequence
    state.latest_capture_at = captured_at
    state.latest_capture_frame = frame_count()

    local rows, players, weapons = collect_snapshot()
    local signature = table.concat(rows, "\n")
    local changed = signature ~= state.last_signature
    local heartbeat = state.last_full_log_at == nil
        or captured_at - state.last_full_log_at >= HEARTBEAT_INTERVAL

    log_set_transitions("PLAYER", state.previous_players, players)
    log_set_transitions("WEAPON", state.previous_weapons, weapons)
    state.previous_players = players
    state.previous_weapons = weapons

    if changed or heartbeat then
        emit(string.format(
            "SNAPSHOT_BEGIN seq=%d frame=%s changed=%s",
            state.sequence,
            format_value(state.latest_capture_frame),
            changed and "true" or "false"
        ), false)
        for i = 1, #rows do
            emit(rows[i], false)
        end
        emit("SNAPSHOT_END seq=" .. tostring(state.sequence), false)
        state.last_full_log_at = captured_at
        state.last_signature = signature
    end
end

local function on_draw()
    if state.stopped or state.latest_capture_sequence == state.last_draw_sequence then
        return
    end

    local drawn_at = now()
    state.last_draw_sequence = state.latest_capture_sequence
    emit(string.format(
        "DRAW_ACK seq=%d capture_frame=%s draw_frame=%s delay=%.6f",
        state.latest_capture_sequence,
        format_value(state.latest_capture_frame),
        format_value(frame_count()),
        drawn_at - state.latest_capture_at
    ), false)
end

local function on_game_event(event)
    if state.stopped then
        return
    end

    local name_ok, name = call_method(event, "GetName")
    if not name_ok or not RELEVANT_EVENTS[name] then
        return
    end

    local userid_ok, userid = call_method(event, "GetInt", "userid")
    local team_ok, team = call_method(event, "GetInt", "team")
    local class_ok, class_value = call_method(event, "GetInt", "class")
    local resolved_ok, resolved_entity = call_library(entities, "GetByUserID", userid)
    local resolved_index = resolved_ok and entity_index(resolved_entity) or nil

    emit(string.format(
        "EVENT name=%s userid=%s team=%s class=%s resolved_entity=%s "
            .. "resource_matches=%s weapon_owner_map=%s",
        tostring(name),
        format_read(userid_ok, userid),
        format_read(team_ok, team),
        format_read(class_ok, class_value),
        format_value(resolved_index),
        resource_slots_for_userid(userid),
        current_weapon_owner_map()
    ), true)
end

--- Removes every callback id owned by the diagnostic, including stale registrations.
local function unregister_callbacks()
    call_library(callbacks, "Unregister", "FrameStageNotify", CALLBACKS.frame_stage)
    call_library(callbacks, "Unregister", "Draw", CALLBACKS.draw)
    call_library(callbacks, "Unregister", "FireGameEvent", CALLBACKS.event)
    call_library(callbacks, "Unregister", "Unload", CALLBACKS.unload)
end

local function on_unload()
    if state.stopped then
        return
    end
    state.stopped = true
    emit("STOP log=" .. tostring(state.log_path), true)
    unregister_callbacks()
    if state.log_handle ~= nil then
        pcall(function()
            state.log_handle:close()
        end)
        state.log_handle = nil
    end
end

--- Verifies the minimum host surface required for a meaningful probe run.
-- @return table Ordered names of unavailable capabilities.
local function missing_capabilities()
    local requirements = {
        { "entities.FindByClass", entities, "FindByClass" },
        { "entities.GetLocalPlayer", entities, "GetLocalPlayer" },
        { "entities.GetPlayerResources", entities, "GetPlayerResources" },
        { "entities.GetByUserID", entities, "GetByUserID" },
        { "client.GetPlayerInfo", client, "GetPlayerInfo" },
        { "globals.RealTime", globals, "RealTime" },
        { "callbacks.Register", callbacks, "Register" },
        { "callbacks.Unregister", callbacks, "Unregister" },
    }

    local missing = {}
    for i = 1, #requirements do
        local requirement = requirements[i]
        if not has_member(requirement[2], requirement[3]) then
            missing[#missing + 1] = requirement[1]
        end
    end
    return missing
end

--- Registers the probe callbacks after removing stale callbacks from an earlier load.
-- @return boolean Whether all callback registrations succeeded.
-- @return string|nil Registration error when startup failed.
local function register_callbacks()
    unregister_callbacks()

    local registrations = {
        { "FrameStageNotify", CALLBACKS.frame_stage, on_frame_stage },
        { "Draw", CALLBACKS.draw, on_draw },
        { "FireGameEvent", CALLBACKS.event, on_game_event },
        { "Unload", CALLBACKS.unload, on_unload },
    }

    for i = 1, #registrations do
        local registration = registrations[i]
        local ok, result = call_library(
            callbacks,
            "Register",
            registration[1],
            registration[2],
            registration[3]
        )
        if not ok then
            unregister_callbacks()
            return false, format_value(result)
        end
    end
    return true, nil
end

--- Starts one probe run and reports all startup failures without partial registration.
local function start()
    local missing = missing_capabilities()
    if #missing > 0 then
        print(PREFIX .. " required LMAOBox API unavailable:")
        for i = 1, #missing do
            print(PREFIX .. " missing: " .. missing[i])
        end
        return
    end

    state.started_at = now()
    local file_ok, file_error = open_log()
    if not file_ok then
        print(PREFIX .. " file logging unavailable: " .. tostring(file_error))
        print(PREFIX .. " full diagnostic output will be written to the console")
    end

    emit("BEGIN version=" .. PROBE_VERSION .. " lua=" .. tostring(_VERSION), true)
    emit(string.format(
        "CONSTANT frame_net_update_end=%d source=%s secondary_slot=%d source=%s",
        NETWORK_UPDATE_END,
        NETWORK_UPDATE_END_SOURCE,
        SECONDARY_SLOT,
        SECONDARY_SLOT_SOURCE
    ), true)
    emit("LOG path=" .. tostring(state.log_path), true)

    local registered, register_error = register_callbacks()
    if not registered then
        emit("START_FAILED callback_error=" .. tostring(register_error), true)
        if state.log_handle ~= nil then
            state.log_handle:close()
            state.log_handle = nil
        end
        return
    end

    emit("READY perform the documented near/far, holster, and deployment scenarios", true)
end

start()
