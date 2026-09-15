--- Defensive acquisition and normalization of the LMAOBox boundary.
-- @module ubermensch.adapter

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")
local Safe = require("ubermensch.safe")
local Weapons = require("ubermensch.weapons")

local Adapter = {}
Adapter.__index = Adapter

local MENU_CLOSED_INPUT = {
    menu_open = false,
    mouse_x = -1,
    mouse_y = -1,
    pressed = false,
    down = false,
    released = false,
}

--- Reduces an arbitrary host value to a log-safe primitive description.
-- This helper is used only when the validation runtime requests boundary
-- diagnostics; ordinary product snapshots do not allocate these descriptions.
-- @param value Raw LMAOBox value.
-- @return string|number|boolean|nil Primitive value or its Lua type name.
local function diagnostic_value(value)
    local kind = type(value)
    if kind == "number" and not Numbers.is_finite(value) then
        return "<nonfinite>"
    end
    if kind == "string" or kind == "number" or kind == "boolean" then
        return value
    end
    if value ~= nil then
        return "<" .. kind .. ">"
    end
    return nil
end

--- Converts a player entity index to LMAOBox's one-based resource-table index.
-- @param entity_index Valid TF2 player entity index.
-- @return number Lua array index, exactly one greater than the entity index.
function Adapter.resource_table_index(entity_index)
    return entity_index + 1
end

--- Reads a typed player-resource table without accepting partial scalar values.
-- @param resource Transient player-resource entity.
-- @param method_name Typed data-table getter.
-- @param property Netprop name.
-- @return table|nil Valid Lua table, otherwise nil.
local function resource_table(resource, method_name, property)
    local ok, value = Safe.method(resource, method_name, property)
    if ok and type(value) == "table" then
        return value
    end
    return nil
end

--- Reads a resource value using the documented N-to-N+1 mapping.
-- @param values Resource table or nil.
-- @param entity_index TF2 player entity index.
-- @return any Value for that player, or nil when the table is unavailable.
local function resource_value(values, entity_index)
    if values == nil then
        return nil
    end
    return values[Adapter.resource_table_index(entity_index)]
end

--- Validates a raw boolean without Lua truthiness coercion.
-- @param value Raw host value.
-- @return boolean|nil Valid boolean, otherwise nil.
local function boolean(value)
    if type(value) == "boolean" then
        return value
    end
    return nil
end

--- Validates an integral field returned by an integer netprop API.
-- @param value Raw host value.
-- @return number|nil Finite integer, otherwise nil.
local function integer(value)
    if Numbers.is_finite(value) and value == math.floor(value) then
        return value
    end
    return nil
end

--- Resolves a transient entity's validated positive index.
-- @param entity Transient LMAOBox Entity.
-- @return number|nil Entity index.
local function entity_index(entity)
    local ok, value = Safe.method(entity, "GetIndex")
    if ok then
        return Numbers.entity_index(value)
    end
    return nil
end

--- Reads the server user ID associated with a current player index.
-- @param host LMAOBox host libraries.
-- @param index Validated player entity index.
-- @return number|nil Positive server user ID.
local function player_userid(host, index)
    if index == nil then
        return nil
    end
    local ok, info = Safe.library(host.client, "GetPlayerInfo", index)
    if not ok or type(info) ~= "table" then
        return nil
    end
    return Numbers.userid(info.UserID)
end

--- Adds one transient weapon to a deduplicated observation set.
-- @param candidates Ordered candidate array.
-- @param by_key Candidate lookup by weapon identity.
-- @param weapon Transient weapon entity.
-- @param source `loadout` or `active`.
-- @param owner_hint Player index that exposed the weapon, if any.
-- @param known_index Already validated weapon index, if available.
local function add_weapon(
    candidates,
    by_key,
    weapon,
    source,
    owner_hint,
    known_index
)
    if weapon == nil then
        return
    end
    local index = known_index or entity_index(weapon)
    local key = index ~= nil and ("i:" .. tostring(index)) or tostring(weapon)
    local candidate = by_key[key]
    if candidate == nil then
        candidate = {
            weapon = weapon,
            weapon_index = index,
            owner_hint = owner_hint,
        }
        candidates[#candidates + 1] = candidate
        by_key[key] = candidate
    elseif candidate.owner_hint == nil then
        candidate.owner_hint = owner_hint
    end
    candidate["source_" .. source] = true
end

--- Returns discovery priority while keeping the loadout secondary authoritative.
-- @param candidate Deduplicated loadout/active weapon observation.
-- @return number Priority used independently for each valid weapon field.
local function discovery_rank(candidate)
    return candidate.source_loadout and 2 or 1
end

--- Creates a plain player row or reuses the row for a current user identity.
-- @param rows Ordered snapshot rows.
-- @param by_userid Rows keyed by server user ID.
-- @param by_index Rows keyed by resource entity index.
-- @param userid Validated user ID or nil.
-- @param index Validated entity index.
-- @return table Plain row.
local function obtain_row(rows, by_userid, by_index, userid, index)
    local row = userid ~= nil and by_userid[userid] or nil
    if row == nil then
        local indexed = by_index[index]
        if indexed ~= nil and (userid == nil or indexed.userid == userid) then
            row = indexed
        end
    end
    if row == nil then
        row = {
            userid = userid,
            entity_index = index,
        }
        rows[#rows + 1] = row
    end
    if userid ~= nil then
        row.userid = userid
        by_userid[userid] = row
    end
    if index ~= nil and by_index[index] == nil then
        by_index[index] = row
    end
    return row
end

--- Reads current player lifecycle fields only from a non-dormant entity.
-- Weapon handles are deliberately deferred until resource/current lifecycle
-- facts establish that the player may be an alive Medic. This avoids two
-- protected native calls for every definitively irrelevant player.
-- @param player Transient CTFPlayer entity.
-- @param diagnostics_enabled Whether to retain primitive boundary-read evidence.
-- @return table Plain current-player observation.
local function inspect_player(player, diagnostics_enabled)
    local observation = {
        entity = player,
        index = entity_index(player),
    }
    local valid_ok, valid = Safe.method(player, "IsValid")
    if diagnostics_enabled then
        observation.valid_read = valid_ok
        observation.valid_value = valid_ok and boolean(valid) or nil
    end
    if valid_ok and valid ~= true then
        return observation
    end
    local dormant_ok, dormant = Safe.method(player, "IsDormant")
    observation.non_dormant = dormant_ok and dormant == false
    if diagnostics_enabled then
        observation.dormant_read = dormant_ok
        observation.dormant = dormant_ok and boolean(dormant) or nil
    end
    if not observation.non_dormant then
        return observation
    end

    local team_ok, team = Safe.method(player, "GetTeamNumber")
    local class_ok, class = Safe.method(
        player,
        "GetPropInt",
        "m_PlayerClass",
        "m_iClass"
    )
    local alive_ok, alive = Safe.method(player, "IsAlive")
    observation.team = team_ok and integer(team) or nil
    observation.class = class_ok and integer(class) or nil
    if diagnostics_enabled then
        observation.team_read = team_ok
        observation.class_read = class_ok
        observation.alive_read = alive_ok
    end
    if alive_ok then
        observation.alive = boolean(alive)
    end
    return observation
end

--- Reads active and secondary weapon handles for one possible alive Medic.
-- @param observation Mutable current-player observation.
-- @param diagnostics_enabled Whether to retain boundary-read evidence.
local function inspect_player_weapons(observation, diagnostics_enabled)
    local player = observation.entity
    local active_ok, active = Safe.method(player, "GetPropEntity", "m_hActiveWeapon")
    if diagnostics_enabled then
        observation.active_read = active_ok
    end
    if active_ok then
        observation.active_weapon = active
        observation.active_index = entity_index(active)
    end
    local loadout_ok, loadout = Safe.method(
        player,
        "GetEntityForLoadoutSlot",
        Constants.SECONDARY_SLOT
    )
    if diagnostics_enabled then
        observation.loadout_read = loadout_ok
    end
    if loadout_ok then
        observation.loadout_weapon = loadout
        observation.loadout_index = entity_index(loadout)
    end
end

--- Determines whether weapon reads can affect the current snapshot.
-- Current lifecycle fields override the resource row independently. A player
-- with unknown class/alive state remains probeable so boundary failures cannot
-- hide a Medic; a player definitively known to be dead or non-Medic is skipped.
-- @param observation Current player lifecycle observation.
-- @param resource_row Associated validated resource row, if available.
-- @return boolean Whether active/loadout weapon handles must be inspected.
local function may_be_alive_medic(observation, resource_row)
    if not observation.non_dormant then
        return false
    end
    local class = observation.class
    if class == nil and resource_row ~= nil then
        class = resource_row.class
    end
    if class ~= nil and class ~= Constants.MEDIC_CLASS then
        return false
    end
    local alive = observation.alive
    if alive == nil and resource_row ~= nil then
        alive = resource_row.alive
    end
    return alive ~= false
end

--- Reads an item family using the nested schema path and compatibility fallback.
-- @param weapon Transient Medi Gun entity.
-- @param diagnostic Optional mutable validation evidence table.
-- @return string|nil Supported or confirmed unsupported family observation.
local function read_family(weapon, diagnostic)
    local ok, item = Safe.method(
        weapon,
        "GetPropInt",
        "m_AttributeManager",
        "m_Item",
        "m_iItemDefinitionIndex"
    )
    if diagnostic ~= nil then
        diagnostic.family_nested_call = ok
        diagnostic.family_nested_value = diagnostic_value(item)
    end
    if ok and integer(item) ~= nil then
        if diagnostic ~= nil then
            diagnostic.item_definition = item
            diagnostic.family_path = "nested"
            diagnostic.family_status = "accepted"
        end
        return Weapons.classify(item) or "UNSUPPORTED"
    end
    ok, item = Safe.method(weapon, "GetPropInt", "m_iItemDefinitionIndex")
    if diagnostic ~= nil then
        diagnostic.family_flat_call = ok
        diagnostic.family_flat_value = diagnostic_value(item)
    end
    if ok and integer(item) ~= nil then
        if diagnostic ~= nil then
            diagnostic.item_definition = item
            diagnostic.family_path = "flat"
            diagnostic.family_status = "accepted"
        end
        return Weapons.classify(item) or "UNSUPPORTED"
    end
    if diagnostic ~= nil then
        diagnostic.family_status = "unavailable_or_malformed"
    end
    return nil
end

--- Reads only the owner-appropriate qualified charge data table.
-- The unqualified property is deliberately never queried because live evidence
-- showed that it can return unrelated values.
-- @param weapon Transient Medi Gun entity.
-- @param local_owner Whether the weapon belongs to the local player.
-- @param diagnostic Optional mutable validation evidence table.
-- @return number|nil Valid charge percentage.
local function read_charge(weapon, local_owner, diagnostic)
    local data_table = local_owner
        and "LocalTFWeaponMedigunData"
        or "NonLocalTFWeaponMedigunData"
    local ok, fraction = Safe.method(
        weapon,
        "GetPropFloat",
        data_table,
        "m_flChargeLevel"
    )
    if diagnostic ~= nil then
        diagnostic.charge_table = data_table
        diagnostic.charge_call = ok
        diagnostic.charge_raw = diagnostic_value(fraction)
    end
    if not ok or not Numbers.is_finite(fraction) then
        if diagnostic ~= nil then
            diagnostic.charge_status = "unavailable_or_malformed"
        end
        return nil
    end
    local charge = Numbers.percent(fraction * 100)
    if diagnostic ~= nil then
        diagnostic.charge_status = charge ~= nil and "accepted" or "out_of_range"
    end
    return charge
end

--- Reads independent current fields from a non-dormant player/weapon pair.
-- A malformed family, charge, deployment, or holster field cannot suppress the
-- other valid fields. Active-weapon identity overrides contradictory holster
-- state only for the informational `equipped` observation.
-- @param candidate Deduplicated transient weapon candidate.
-- @param player Current owner observation.
-- @param local_index Current local player index.
-- @param diagnostics_enabled Whether to retain primitive boundary-read evidence.
-- @return table Plain field observation and optional validation evidence.
local function inspect_weapon(candidate, player, local_index, diagnostics_enabled)
    local weapon = candidate.weapon
    local diagnostic = diagnostics_enabled and {} or nil
    local observation = {
        current = false,
        diagnostic = diagnostic,
    }
    local valid_ok, valid = Safe.method(weapon, "IsValid")
    if diagnostic ~= nil then
        diagnostic.valid_call = valid_ok
        diagnostic.valid_value = valid_ok and boolean(valid) or nil
    end
    if valid_ok and valid ~= true then
        if diagnostic ~= nil then diagnostic.currency = "invalid_weapon" end
        return observation
    end
    local dormant_ok, dormant = Safe.method(weapon, "IsDormant")
    if diagnostic ~= nil then
        diagnostic.dormant_call = dormant_ok
        diagnostic.dormant = dormant_ok and boolean(dormant) or nil
        diagnostic.player_non_dormant = player.non_dormant
    end
    if not dormant_ok or dormant ~= false or not player.non_dormant then
        if diagnostic ~= nil then
            diagnostic.currency = not player.non_dormant
                and "player_not_current"
                or "weapon_not_current"
        end
        return observation
    end
    observation.current = true
    if diagnostic ~= nil then diagnostic.currency = "current" end

    local deployed_ok, deployed = Safe.method(
        weapon,
        "GetPropBool",
        "m_bChargeRelease"
    )
    local holstered_ok, holstered = Safe.method(
        weapon,
        "GetPropBool",
        "m_bHolstered"
    )
    if diagnostic ~= nil then
        diagnostic.deployment_call = deployed_ok
        diagnostic.deployment_raw = diagnostic_value(deployed)
        diagnostic.deployment_status = deployed_ok
            and type(deployed) == "boolean"
            and "accepted"
            or "unavailable_or_malformed"
        diagnostic.holstered_call = holstered_ok
        diagnostic.holstered_raw = diagnostic_value(holstered)
    end
    local active_known = player.active_weapon ~= nil
    local active_match = candidate.weapon_index ~= nil
        and player.active_index == candidate.weapon_index
    local equipped
    if active_known then
        equipped = active_match
    elseif holstered_ok and type(holstered) == "boolean" then
        equipped = not holstered
    end

    local deployment
    if deployed_ok then
        deployment = boolean(deployed)
    end
    observation.family = read_family(weapon, diagnostic)
    observation.charge = read_charge(
        weapon,
        player.index == local_index,
        diagnostic
    )
    observation.deployed = deployment
    observation.equipped = equipped
    observation.rank = discovery_rank(candidate)
    return observation
end

--- Applies valid weapon fields to an owner row independently by priority.
-- @param row Plain owner row.
-- @param observation Plain current weapon observation.
local function merge_weapon(row, observation)
    if observation == nil or not observation.current then
        return
    end
    row.current_present = true
    if observation.family ~= nil
        and (row.family_rank == nil or observation.rank > row.family_rank)
    then
        row.current_family = observation.family
        row.family_rank = observation.rank
    end
    if observation.charge ~= nil
        and (row.charge_rank == nil or observation.rank > row.charge_rank)
    then
        row.current_charge = observation.charge
        row.charge_rank = observation.rank
    end
    if observation.deployed ~= nil
        and (row.deployment_rank == nil or observation.rank > row.deployment_rank)
    then
        row.current_deployed = observation.deployed
        row.deployment_rank = observation.rank
    end
    if observation.equipped ~= nil
        and (row.equipped_rank == nil or observation.rank > row.equipped_rank)
    then
        row.current_equipped = observation.equipped
        row.equipped_rank = observation.rank
    end
end

--- Constructs an adapter around the host libraries without retaining entities.
-- @param host LMAOBox libraries and standard Lua APIs supplied by composition.
-- @param diagnostics_enabled Whether to attach primitive validation evidence.
-- @return table Adapter instance.
function Adapter.new(host, diagnostics_enabled)
    return setmetatable({
        host = host,
        diagnostics_enabled = diagnostics_enabled == true,
    }, Adapter)
end

--- Reads an optional simulation/network revision for duplicate fallback checks.
-- The client tick covers predicted local changes; the last-received server tick
-- is a compatibility fallback. Unavailable or malformed values fail open so
-- the controller captures every render-start callback rather than risking stale
-- information.
-- @return number|nil Valid integral network revision.
function Adapter:network_revision()
    local ok, value = Safe.library(self.host.globals, "TickCount")
    if ok and integer(value) ~= nil then
        return value
    end
    ok, value = Safe.library(self.host.clientstate, "GetDeltaTick")
    return ok and integer(value) or nil
end

--- Captures one complete validated snapshot at the network-update boundary.
-- Work is linear in available player slots and observed entities. All Entity
-- references are confined to this call and only primitive rows are returned.
-- @param diagnostics_override Optional per-capture validation-evidence switch.
-- @return table Primitive context, roster, lifecycle, and Medi Gun observations.
function Adapter:capture(diagnostics_override)
    local host = self.host
    local collect_diagnostics = diagnostics_override
    if collect_diagnostics == nil then
        collect_diagnostics = self.diagnostics_enabled
    end
    local diagnostics = collect_diagnostics == true and {
        resource_tables = {},
        resource_rows = {},
        resource_disconnected_count = 0,
        resource_malformed_connected_count = 0,
        current_players = {},
        weapons = {},
    } or nil
    local now_ok, now = Safe.library(host.globals, "RealTime")
    if not now_ok or not Numbers.is_finite(now) then
        now = 0
    end
    local map_ok, map = Safe.library(host.engine, "GetMapName")
    if not map_ok or type(map) ~= "string" or map == "" then
        map = nil
    end
    local round_ok, round_state = Safe.library(host.gamerules, "GetRoundState")
    round_state = round_ok and integer(round_state) or nil
    local mvm_ok, is_mvm = Safe.library(host.gamerules, "IsMvM")
    if mvm_ok then
        is_mvm = boolean(is_mvm)
    else
        is_mvm = nil
    end

    local rows = {}
    local by_userid = {}
    local resource_by_index = {}
    local resource_ok, resource = Safe.library(host.entities, "GetPlayerResources")
    local tables = {}
    if resource_ok and resource ~= nil then
        tables.connected = resource_table(resource, "GetPropDataTableBool", "m_bConnected")
        tables.valid = resource_table(resource, "GetPropDataTableBool", "m_bValid")
        tables.alive = resource_table(resource, "GetPropDataTableBool", "m_bAlive")
        tables.team = resource_table(resource, "GetPropDataTableInt", "m_iTeam")
        tables.userid = resource_table(resource, "GetPropDataTableInt", "m_iUserID")
        tables.class = resource_table(resource, "GetPropDataTableInt", "m_iPlayerClass")
        tables.charge = resource_table(resource, "GetPropDataTableInt", "m_iChargeLevel")
    end
    local roster_available = tables.connected ~= nil
        and tables.valid ~= nil
        and tables.alive ~= nil
        and tables.team ~= nil
        and tables.userid ~= nil
        and tables.class ~= nil

    if diagnostics ~= nil then
        for _, name in ipairs({
            "connected", "valid", "alive", "team", "userid", "class", "charge",
        }) do
            diagnostics.resource_tables[name] = tables[name] ~= nil
        end
        diagnostics.resource_entity_available = resource_ok and resource ~= nil
    end

    for index = 1, Constants.MAX_PLAYERS do
        local connected_raw = resource_value(tables.connected, index)
        local connected = boolean(connected_raw)
        -- Other resource columns have no domain meaning for a slot that is
        -- authoritatively disconnected. Skipping them keeps validation-mode
        -- capture proportional to the actual roster instead of allocating a
        -- full diagnostic row for every empty slot on every network update.
        local inspect_row = connected == true
        local valid_raw
        local alive_raw
        local team_raw
        local userid_raw
        local class_raw
        local charge_raw
        if inspect_row then
            valid_raw = resource_value(tables.valid, index)
            alive_raw = resource_value(tables.alive, index)
            team_raw = resource_value(tables.team, index)
            userid_raw = resource_value(tables.userid, index)
            class_raw = resource_value(tables.class, index)
            charge_raw = resource_value(tables.charge, index)
        end
        local valid = boolean(valid_raw)
        local alive = boolean(alive_raw)
        local team = integer(team_raw)
        local userid = Numbers.userid(userid_raw)
        local class = integer(class_raw)
        local charge = Numbers.resource_percent(charge_raw)
        if diagnostics ~= nil and connected ~= false then
            diagnostics.resource_rows[#diagnostics.resource_rows + 1] = {
                entity_index = index,
                connected = connected,
                connected_raw = diagnostic_value(connected_raw),
                valid = valid,
                valid_raw = diagnostic_value(valid_raw),
                alive = alive,
                alive_raw = diagnostic_value(alive_raw),
                team = team,
                team_raw = diagnostic_value(team_raw),
                userid = userid,
                userid_raw = diagnostic_value(userid_raw),
                class = class,
                class_raw = diagnostic_value(class_raw),
                charge = charge,
                charge_raw = diagnostic_value(charge_raw),
                associated = connected == true and valid == true
                    and userid ~= nil,
            }
            if connected == nil then
                diagnostics.resource_malformed_connected_count =
                    diagnostics.resource_malformed_connected_count + 1
            end
        elseif diagnostics ~= nil then
            diagnostics.resource_disconnected_count =
                diagnostics.resource_disconnected_count + 1
        end
        if connected == nil then
            roster_available = false
        elseif connected then
            if valid == nil or alive == nil or team == nil
                or userid == nil or class == nil
            then
                roster_available = false
            elseif valid then
                local row = obtain_row(
                    rows,
                    by_userid,
                    resource_by_index,
                    userid,
                    index
                )
                row.resource_present = true
                row.connected = connected
                row.valid = valid
                row.alive = alive
                row.team = team
                row.class = class
                row.resource_charge = charge
            end
        end
    end

    local local_ok, local_entity = Safe.library(host.entities, "GetLocalPlayer")
    if not local_ok then
        local_entity = nil
    end
    local local_index = entity_index(local_entity)
    local local_userid = player_userid(host, local_index)
    if local_userid == nil and local_index ~= nil
        and resource_by_index[local_index] ~= nil
    then
        local_userid = resource_by_index[local_index].userid
    end

    local players_ok, player_entities = Safe.library(
        host.entities,
        "FindByClass",
        "CTFPlayer"
    )
    if not players_ok or type(player_entities) ~= "table" then
        player_entities = {}
    end
    if diagnostics ~= nil then
        diagnostics.player_enumeration_call = players_ok
        diagnostics.player_enumeration_count = #player_entities
    end
    local current_by_index = {}
    local weapon_candidates = {}
    local weapons_by_key = {}
    local enumerated_player_count = #player_entities
    for i = 1, enumerated_player_count + 1 do
        local player_entity = player_entities[i]
        if i > enumerated_player_count then
            -- LMAOBox can omit the local player from CTFPlayer enumeration even
            -- while GetLocalPlayer returns a usable entity. Inspect that entity
            -- through the normal boundary path only when enumeration missed it.
            if local_index ~= nil and current_by_index[local_index] == nil then
                player_entity = local_entity
            end
        end
        local observation = player_entity ~= nil
            and inspect_player(player_entity, diagnostics ~= nil)
            or nil
        if observation ~= nil and observation.index ~= nil then
            observation.userid = player_userid(host, observation.index)
            local resource_row = resource_by_index[observation.index]
            if observation.userid ~= nil
                and resource_row ~= nil
                and resource_row.userid ~= observation.userid
            then
                -- A current user identity proves that a lagging resource row at
                -- this entity index must not donate facts to the new player.
                roster_available = false
                resource_row.valid = false
                resource_row.alive = false
                resource_row.resource_charge = nil
            end
            current_by_index[observation.index] = observation
            local row = obtain_row(
                rows,
                by_userid,
                resource_by_index,
                observation.userid,
                observation.index
            )
            if observation.non_dormant then
                row.current_present = true
                row.is_local = observation.index == local_index
                row.current_team = observation.team
                row.current_class = observation.class
                row.current_alive = observation.alive
            end
            local inspect_weapons = may_be_alive_medic(
                observation,
                resource_row
            )
            if diagnostics ~= nil then
                observation.weapon_inspection = inspect_weapons
            end
            if inspect_weapons then
                inspect_player_weapons(observation, diagnostics ~= nil)
            end
            local loadout_medigun_ok, loadout_medigun = Safe.method(
                observation.loadout_weapon,
                "IsMedigun"
            )
            observation.loadout_is_medigun = loadout_medigun_ok
                and loadout_medigun == true
            if loadout_medigun_ok and loadout_medigun == true then
                add_weapon(
                    weapon_candidates,
                    weapons_by_key,
                    observation.loadout_weapon,
                    "loadout",
                    observation.index,
                    observation.loadout_index
                )
            end
            local same_weapon = observation.active_weapon ~= nil
                and (observation.active_weapon == observation.loadout_weapon
                    or (observation.active_index ~= nil
                        and observation.active_index
                            == observation.loadout_index))
            local active_medigun_ok
            local active_medigun
            if same_weapon and loadout_medigun_ok then
                active_medigun_ok = true
                active_medigun = loadout_medigun
            else
                active_medigun_ok, active_medigun = Safe.method(
                    observation.active_weapon,
                    "IsMedigun"
                )
            end
            observation.active_is_medigun = active_medigun_ok
                and active_medigun == true
            if active_medigun_ok and active_medigun == true then
                add_weapon(
                    weapon_candidates,
                    weapons_by_key,
                    observation.active_weapon,
                    "active",
                    observation.index,
                    observation.active_index
                )
            end
            if diagnostics ~= nil then
                diagnostics.current_players[#diagnostics.current_players + 1] = {
                    entity_index = observation.index,
                    userid = observation.userid,
                    valid_read = observation.valid_read,
                    valid_value = observation.valid_value,
                    dormant_read = observation.dormant_read,
                    dormant = observation.dormant,
                    non_dormant = observation.non_dormant,
                    team_read = observation.team_read,
                    team = observation.team,
                    class_read = observation.class_read,
                    class = observation.class,
                    alive_read = observation.alive_read,
                    alive = observation.alive,
                    weapon_inspection = observation.weapon_inspection,
                    active_read = observation.active_read,
                    active_index = observation.active_index,
                    active_is_medigun = observation.active_is_medigun,
                    loadout_read = observation.loadout_read,
                    loadout_index = observation.loadout_index,
                    loadout_is_medigun = observation.loadout_is_medigun,
                }
            end
        elseif observation ~= nil and diagnostics ~= nil then
            diagnostics.current_players[#diagnostics.current_players + 1] = {
                entity_index = nil,
                valid_read = observation.valid_read,
                valid_value = observation.valid_value,
                dormant_read = observation.dormant_read,
                dormant = observation.dormant,
                rejected = "invalid_entity_index",
            }
        end
    end

    for i = 1, #weapon_candidates do
        local candidate = weapon_candidates[i]
        local owner_ok, owner = Safe.method(
            candidate.weapon,
            "GetPropEntity",
            "m_hOwner"
        )
        local owner_index = owner_ok and entity_index(owner) or nil
        owner_index = owner_index or candidate.owner_hint
        local player = current_by_index[owner_index]
        local weapon_diagnostic = diagnostics ~= nil and {
            weapon_index = candidate.weapon_index,
            owner_read = owner_ok,
            owner_index = owner_index,
            owner_hint = candidate.owner_hint,
            source_loadout = candidate.source_loadout == true,
            source_active = candidate.source_active == true,
        } or nil
        if player ~= nil then
            local canonical = true
            if player.loadout_is_medigun then
                canonical = candidate.weapon == player.loadout_weapon
                    or (candidate.weapon_index ~= nil
                        and candidate.weapon_index == player.loadout_index)
            elseif player.active_is_medigun then
                canonical = candidate.weapon == player.active_weapon
                    or (candidate.weapon_index ~= nil
                        and candidate.weapon_index == player.active_index)
            end
            local userid = player.userid or player_userid(host, owner_index)
            local row = obtain_row(
                rows,
                by_userid,
                resource_by_index,
                userid,
                owner_index
            )
            local inspection
            if canonical then
                inspection = inspect_weapon(
                    candidate,
                    player,
                    local_index,
                    diagnostics ~= nil
                )
                merge_weapon(row, inspection)
            end
            if weapon_diagnostic ~= nil then
                weapon_diagnostic.userid = userid
                weapon_diagnostic.canonical = canonical
                if inspection ~= nil then
                    weapon_diagnostic.current = inspection.current
                    weapon_diagnostic.family = inspection.family
                    weapon_diagnostic.charge = inspection.charge
                    weapon_diagnostic.deployed = inspection.deployed
                    weapon_diagnostic.equipped = inspection.equipped
                    weapon_diagnostic.reads = inspection.diagnostic
                end
            end
        elseif weapon_diagnostic ~= nil then
            weapon_diagnostic.canonical = false
            weapon_diagnostic.rejected = "owner_not_associated"
        end
        if weapon_diagnostic ~= nil then
            diagnostics.weapons[#diagnostics.weapons + 1] = weapon_diagnostic
        end
    end

    local local_row = local_userid ~= nil and by_userid[local_userid]
        or resource_by_index[local_index]
    local local_team = local_row ~= nil
        and (local_row.current_team or local_row.team)
        or nil
    local local_class = local_row ~= nil
        and (local_row.current_class or local_row.class)
        or nil
    local local_alive
    if local_row ~= nil and local_row.current_alive ~= nil then
        local_alive = local_row.current_alive
    elseif local_row ~= nil then
        local_alive = local_row.alive
    end

    return {
        now = now,
        map = map,
        round_state = round_state,
        is_mvm = is_mvm,
        phase = Constants.SETUP_ROUND_STATE[round_state] and "setup" or "running",
        roster_available = roster_available,
        players = rows,
        local_userid = local_userid,
        local_team = local_team,
        local_class = local_class,
        local_alive = local_alive,
        observed_weapon_count = #weapon_candidates,
        diagnostics = diagnostics,
    }
end

--- Normalizes a relevant GameEvent to primitive data for bounded queuing.
-- Raw GameEvent objects are consumed immediately and never retained.
-- @param event Transient LMAOBox GameEvent.
-- @return table|nil Normalized event, or nil when irrelevant or malformed.
function Adapter:normalize_event(event)
    local name_ok, name = Safe.method(event, "GetName")
    if not name_ok or not Constants.EVENTS[name] then
        return nil
    end
    local userid_ok, userid = Safe.method(event, "GetInt", "userid")
    userid = userid_ok and Numbers.userid(userid) or nil
    if userid == nil then
        return nil
    end
    local now_ok, now = Safe.library(self.host.globals, "RealTime")
    if not now_ok or not Numbers.is_finite(now) then
        return nil
    end
    local normalized = {
        name = name,
        userid = userid,
        time = now,
    }
    if name == "player_team" then
        local ok, team = Safe.method(event, "GetInt", "team")
        normalized.team = ok and integer(team) or nil
        if normalized.team == nil then
            return nil
        end
    elseif name == "player_changeclass" then
        local ok, class = Safe.method(event, "GetInt", "class")
        normalized.class = ok and integer(class) or nil
        if normalized.class == nil then
            return nil
        end
    end
    return normalized
end

--- Evaluates visibility gates and identifies a rejected live context.
-- The reason is intended for bounded startup diagnostics, not steady-state
-- logging; ordinary expected visibility changes remain silent after first render.
-- @param snapshot Latest captured context.
-- @return boolean Whether the HUD may render this Draw.
-- @return string|nil Stable blocker description when rendering is rejected.
function Adapter:visibility(snapshot)
    if snapshot == nil then
        return false, "network snapshot unavailable"
    end
    if snapshot.map == nil then
        return false, "map unavailable"
    end
    if snapshot.is_mvm == true then
        return false, "MvM is hidden"
    end
    if snapshot.is_mvm ~= false then
        return false, "MvM state unavailable"
    end
    if snapshot.round_state == nil then
        return false, "round state unavailable"
    end
    if not Constants.VISIBLE_ROUND_STATE[snapshot.round_state] then
        return false, "round state " .. tostring(snapshot.round_state) .. " is hidden"
    end
    local console_ok, console_visible = Safe.library(
        self.host.engine,
        "Con_IsVisible"
    )
    local ui_ok, ui_visible = Safe.library(
        self.host.engine,
        "IsGameUIVisible"
    )
    if not console_ok or type(console_visible) ~= "boolean" then
        return false, "Source console state unavailable"
    end
    if console_visible then
        return false, "Source console visible"
    end
    if not ui_ok or type(ui_visible) ~= "boolean" then
        return false, "TF2 game UI state unavailable"
    end
    if ui_visible then
        return false, "TF2 game UI visible"
    end
    return true, nil
end

--- Reports only the boolean visibility decision for domain callers and tests.
-- @param snapshot Latest captured context.
-- @return boolean Whether the HUD may render this Draw.
function Adapter:is_visible(snapshot)
    local visible = self:visibility(snapshot)
    return visible
end

--- Captures the primitive input sample needed by menu-only dragging.
-- @return table Mouse coordinates and menu/button states.
function Adapter:input_sample()
    local mouse_left = integer(self.host.mouse_left) or Constants.MOUSE_LEFT
    local menu_ok, menu_open = Safe.library(self.host.gui, "IsMenuOpen")
    if not menu_ok or menu_open ~= true then
        return MENU_CLOSED_INPUT
    end
    local mouse_ok, mouse = Safe.library(self.host.input, "GetMousePos")
    local pressed_ok, pressed = Safe.library(
        self.host.input,
        "IsButtonPressed",
        mouse_left
    )
    local down_ok, down = Safe.library(
        self.host.input,
        "IsButtonDown",
        mouse_left
    )
    local released_ok, released = Safe.library(
        self.host.input,
        "IsButtonReleased",
        mouse_left
    )
    return {
        menu_open = true,
        mouse_x = mouse_ok and type(mouse) == "table"
            and (mouse.x or mouse[1]) or -1,
        mouse_y = mouse_ok and type(mouse) == "table"
            and (mouse.y or mouse[2]) or -1,
        pressed = pressed_ok and pressed == true,
        down = down_ok and down == true,
        released = released_ok and released == true,
    }
end

return Adapter
