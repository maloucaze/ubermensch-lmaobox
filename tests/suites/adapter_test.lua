local Harness = require("support.harness")
local Adapter = require("ubermensch.adapter")
local Fakes = require("support.fakes")

local function row_by_userid(snapshot, userid)
    for i = 1, #snapshot.players do
        if snapshot.players[i].userid == userid then
            return snapshot.players[i]
        end
    end
end

local function medic_pair()
    local local_weapon_options = {
        index = 101,
        item = 29,
        local_charge = 0.75,
        nonlocal_charge = 0.01,
        deployed = false,
        holstered = true,
    }
    local enemy_weapon_options = {
        index = 102,
        item = 35,
        local_charge = 0.02,
        nonlocal_charge = 0.5,
        deployed = true,
        holstered = false,
    }
    local local_weapon = Fakes.weapon(local_weapon_options)
    local enemy_weapon = Fakes.weapon(enemy_weapon_options)
    local local_player = Fakes.player({
        index = 1,
        team = 2,
        class = 5,
        alive = true,
        loadout_weapon = local_weapon,
        active_weapon = local_weapon,
    })
    local enemy_player = Fakes.player({
        index = 2,
        team = 3,
        class = 5,
        alive = true,
        loadout_weapon = enemy_weapon,
        active_weapon = enemy_weapon,
    })
    local_weapon_options.owner = local_player
    enemy_weapon_options.owner = enemy_player
    return local_player, enemy_player, local_weapon, enemy_weapon
end

Harness.test("qualified local and nonlocal charge paths are exclusive", function()
    local local_player, enemy_player, local_weapon, enemy_weapon = medic_pair()
    local host = Fakes.host({
        players = { local_player, enemy_player },
        direct_weapons = {},
        local_player = local_player,
        userids = { [1] = 10, [2] = 20 },
        resource = Fakes.resource({
            [1] = { connected = true, valid = true, alive = true, team = 2, userid = 10, class = 5, charge = 75 },
            [2] = { connected = true, valid = true, alive = true, team = 3, userid = 20, class = 5, charge = 50 },
        }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(row_by_userid(snapshot, 10).current_charge, 75)
    Harness.equal(row_by_userid(snapshot, 20).current_charge, 50)
    Harness.same_table(local_weapon.options.float_reads, {
        "LocalTFWeaponMedigunData.m_flChargeLevel",
    })
    Harness.same_table(enemy_weapon.options.float_reads, {
        "NonLocalTFWeaponMedigunData.m_flChargeLevel",
    })
end)

Harness.test("loadout discovery does not require or query direct enumeration", function()
    local local_player, enemy_player = medic_pair()
    local host = Fakes.host({
        players = { local_player, enemy_player },
        direct_weapons = {},
        local_player = local_player,
        userids = { [1] = 10, [2] = 20 },
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(snapshot.observed_weapon_count, 2)
    Harness.equal(row_by_userid(snapshot, 10).current_family, "STOCK")
    Harness.equal(row_by_userid(snapshot, 20).current_family, "KRITZ")
    Harness.same_table(host.state.find_by_class_calls, { "CTFPlayer" })
end)

Harness.test("local Medic omitted from player enumeration is still inspected", function()
    local families = {
        { item = 29, family = "STOCK" },
        { item = 35, family = "KRITZ" },
    }
    for i = 1, #families do
        local expected = families[i]
        local weapon_options = {
            index = 100 + i,
            item = expected.item,
            local_charge = 0.42,
            deployed = true,
            holstered = false,
        }
        local weapon = Fakes.weapon(weapon_options)
        local player = Fakes.player({
            index = 1,
            team = 2,
            class = 5,
            alive = true,
            loadout_weapon = weapon,
            active_weapon = weapon,
        })
        weapon_options.owner = player
        local host = Fakes.host({
            players = {},
            direct_weapons = {},
            local_player = player,
            userids = { [1] = 10 },
        })

        local snapshot = Adapter.new(host, true):capture()
        local row = row_by_userid(snapshot, 10)
        Harness.equal(snapshot.diagnostics.player_enumeration_count, 0)
        Harness.equal(#snapshot.diagnostics.current_players, 1)
        Harness.equal(snapshot.observed_weapon_count, 1)
        Harness.equal(row.current_family, expected.family)
        Harness.equal(row.current_charge, 42)
        Harness.equal(row.current_deployed, true)
        Harness.same_table(weapon.options.float_reads, {
            "LocalTFWeaponMedigunData.m_flChargeLevel",
        })
    end
end)

Harness.test("identical active and loadout observations deduplicate", function()
    local local_player, enemy_player, local_weapon, enemy_weapon = medic_pair()
    local host = Fakes.host({
        players = { local_player, enemy_player },
        direct_weapons = { local_weapon, enemy_weapon },
        local_player = local_player,
        userids = { [1] = 10, [2] = 20 },
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(snapshot.observed_weapon_count, 2)
    Harness.equal(row_by_userid(snapshot, 10).current_charge, 75)
    Harness.equal(row_by_userid(snapshot, 20).current_charge, 50)
    Harness.equal(local_weapon.options.medigun_reads, 1)
    Harness.equal(enemy_weapon.options.medigun_reads, 1)
    Harness.same_table(host.state.find_by_class_calls, { "CTFPlayer" })
end)

Harness.test("known non-Medics skip weapon handles", function()
    local stale_options = { index = 999, item = 35, nonlocal_charge = 0.99 }
    local stale = Fakes.weapon(stale_options)
    local player = Fakes.player({
        index = 1,
        team = 2,
        class = 1,
        alive = true,
        loadout_weapon = stale,
        active_weapon = stale,
    })
    stale_options.owner = player
    local host = Fakes.host({
        players = { player },
        local_player = player,
        userids = { [1] = 10 },
        resource = Fakes.resource({
            [1] = {
                connected = true,
                valid = true,
                alive = true,
                team = 2,
                userid = 10,
                class = 1,
                charge = 0,
            },
        }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(snapshot.observed_weapon_count, 0)
    Harness.equal(player.options.active_reads or 0, 0)
    Harness.equal(#(player.options.loadout_slots or {}), 0)
    Harness.equal(stale.options.medigun_reads or 0, 0)
end)

Harness.test("known dead Medics skip weapon handles", function()
    local weapon_options = { index = 101, item = 29, nonlocal_charge = 0.50 }
    local weapon = Fakes.weapon(weapon_options)
    local player = Fakes.player({
        index = 1,
        team = 2,
        class = 5,
        alive = false,
        loadout_weapon = weapon,
        active_weapon = weapon,
    })
    weapon_options.owner = player
    local host = Fakes.host({
        players = { player },
        userids = { [1] = 10 },
        resource = Fakes.resource({
            [1] = {
                connected = true,
                valid = true,
                alive = false,
                team = 2,
                userid = 10,
                class = 5,
                charge = 50,
            },
        }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(snapshot.observed_weapon_count, 0)
    Harness.equal(player.options.active_reads or 0, 0)
    Harness.equal(#(player.options.loadout_slots or {}), 0)
end)

Harness.test("unknown lifecycle still probes a possible Medic", function()
    local weapon_options = {
        index = 101,
        item = 29,
        nonlocal_charge = 0.40,
        deployed = false,
    }
    local weapon = Fakes.weapon(weapon_options)
    local player = Fakes.player({
        index = 1,
        team = 2,
        class_error = true,
        alive = true,
        loadout_weapon = weapon,
    })
    weapon_options.owner = player
    local host = Fakes.host({
        players = { player },
        userids = { [1] = 10 },
        resource = Fakes.resource({}, { m_iPlayerClass = true }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(snapshot.observed_weapon_count, 1)
    Harness.equal(row_by_userid(snapshot, 10).current_family, "STOCK")
    Harness.equal(#player.options.loadout_slots, 1)
end)

Harness.test("unknown alive state still probes a current Medic", function()
    local weapon_options = {
        index = 101,
        item = 35,
        nonlocal_charge = 0.40,
        deployed = false,
    }
    local weapon = Fakes.weapon(weapon_options)
    local player = Fakes.player({
        index = 1,
        team = 2,
        class = 5,
        alive_error = true,
        loadout_weapon = weapon,
    })
    weapon_options.owner = player
    local host = Fakes.host({
        players = { player },
        userids = { [1] = 10 },
        resource = Fakes.resource({}, { m_bAlive = true }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(snapshot.observed_weapon_count, 1)
    Harness.equal(row_by_userid(snapshot, 10).current_family, "KRITZ")
end)

Harness.test("active handle overrides contradictory holster without dropping fields", function()
    local local_player, _, local_weapon = medic_pair()
    local host = Fakes.host({
        players = { local_player },
        direct_weapons = { local_weapon },
        local_player = local_player,
        userids = { [1] = 10 },
    })
    local row = row_by_userid(Adapter.new(host):capture(), 10)
    Harness.truthy(row.current_equipped)
    Harness.equal(row.current_family, "STOCK")
    Harness.equal(row.current_charge, 75)
    Harness.equal(row.current_deployed, false)
end)

Harness.test("family charge and deployment failures remain independent", function()
    local options = {
        index = 101,
        item = 29,
        local_charge = 0.4,
        deployed = "invalid",
        family_error = true,
    }
    local weapon = Fakes.weapon(options)
    local player = Fakes.player({
        index = 1, team = 2, class = 5, alive = true,
        loadout_weapon = weapon,
    })
    options.owner = player
    local host = Fakes.host({
        players = { player }, local_player = player, userids = { [1] = 10 },
    })
    local row = row_by_userid(Adapter.new(host):capture(), 10)
    Harness.is_nil(row.current_family)
    Harness.equal(row.current_charge, 40)
    Harness.is_nil(row.current_deployed)
end)

Harness.test("dormant player or weapon never yields exact weapon fields", function()
    local local_player, enemy_player, _, enemy_weapon = medic_pair()
    enemy_player.options.dormant = true
    local host = Fakes.host({
        players = { local_player, enemy_player },
        local_player = local_player,
        userids = { [1] = 10, [2] = 20 },
        resource = Fakes.resource({
            [1] = { connected = true, valid = true, alive = true, team = 2, userid = 10, class = 5, charge = 75 },
            [2] = { connected = true, valid = true, alive = true, team = 3, userid = 20, class = 5, charge = 61 },
        }),
    })
    local row = row_by_userid(Adapter.new(host):capture(), 20)
    Harness.is_nil(row.current_charge)
    Harness.equal(row.resource_charge, 61)

    enemy_player.options.dormant = false
    enemy_weapon.options.dormant = true
    row = row_by_userid(Adapter.new(host):capture(), 20)
    Harness.is_nil(row.current_charge)
    Harness.equal(row.resource_charge, 61)
end)

Harness.test("resource mapping and casual charge endpoints are accepted", function()
    local host = Fakes.host({
        resource = Fakes.resource({
            [4] = { connected = true, valid = true, alive = true, team = 3, userid = 44, class = 5, charge = 0 },
            [7] = { connected = true, valid = true, alive = true, team = 2, userid = 77, class = 5, charge = 100 },
        }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.truthy(snapshot.roster_available)
    Harness.equal(Adapter.resource_table_index(4), 5)
    Harness.equal(row_by_userid(snapshot, 44).resource_charge, 0)
    Harness.equal(row_by_userid(snapshot, 77).resource_charge, 100)
end)

Harness.test("malformed and out-of-range resource charge is rejected independently", function()
    local host = Fakes.host({
        resource = Fakes.resource({
            [1] = { connected = true, valid = true, alive = true, team = 2, userid = 10, class = 5, charge = 101 },
            [2] = { connected = true, valid = true, alive = true, team = 3, userid = 20, class = 5, charge = 42.5 },
        }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.truthy(snapshot.roster_available)
    Harness.is_nil(row_by_userid(snapshot, 10).resource_charge)
    Harness.is_nil(row_by_userid(snapshot, 20).resource_charge)
end)

Harness.test("every required roster table failure withdraws roster authority", function()
    local properties = {
        "m_bConnected", "m_bValid", "m_bAlive", "m_iTeam",
        "m_iUserID", "m_iPlayerClass",
    }
    for i = 1, #properties do
        local host = Fakes.host({
            resource = Fakes.resource({}, { [properties[i]] = true }),
        })
        Harness.falsy(Adapter.new(host):capture().roster_available)
    end
end)

Harness.test("unassociated resource charge is never exposed", function()
    local host = Fakes.host({
        resource = Fakes.resource({
            [2] = { connected = true, valid = true, alive = true, team = 3, userid = 0, class = 5, charge = 88 },
        }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.falsy(snapshot.roster_available)
    Harness.is_nil(row_by_userid(snapshot, 0))
end)

Harness.test("current lifecycle overlays lagging resource lifecycle", function()
    local player, _, weapon = medic_pair()
    local host = Fakes.host({
        players = { player }, local_player = player, userids = { [1] = 10 },
        resource = Fakes.resource({
            [1] = { connected = true, valid = true, alive = false, team = 3, userid = 10, class = 1, charge = 20 },
        }),
    })
    weapon.options.owner = player
    local row = row_by_userid(Adapter.new(host):capture(), 10)
    Harness.equal(row.team, 3)
    Harness.equal(row.current_team, 2)
    Harness.equal(row.class, 1)
    Harness.equal(row.current_class, 5)
    Harness.equal(row.alive, false)
    Harness.equal(row.current_alive, true)
end)

Harness.test("failed resource table falls back without proving empty roster", function()
    local player = medic_pair()
    local host = Fakes.host({
        players = { player }, local_player = player, userids = { [1] = 10 },
        resource = Fakes.resource({}, { m_bConnected = true }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.falsy(snapshot.roster_available)
    Harness.truthy(row_by_userid(snapshot, 10).current_present)
end)

Harness.test("recognized and unknown item definitions remain distinct", function()
    local unknown_options = { index = 101, item = 123456, local_charge = 0.5, deployed = false }
    local quickfix_options = { index = 102, item = 411, nonlocal_charge = 0.5, deployed = false }
    local vacc_options = { index = 103, item = 998, nonlocal_charge = 0.75, deployed = false }
    local unknown_weapon = Fakes.weapon(unknown_options)
    local quickfix_weapon = Fakes.weapon(quickfix_options)
    local vacc_weapon = Fakes.weapon(vacc_options)
    local first = Fakes.player({ index = 1, team = 2, class = 5, alive = true, loadout_weapon = unknown_weapon })
    local second = Fakes.player({ index = 2, team = 3, class = 5, alive = true, loadout_weapon = quickfix_weapon })
    local third = Fakes.player({ index = 3, team = 3, class = 5, alive = true, loadout_weapon = vacc_weapon })
    unknown_options.owner = first
    quickfix_options.owner = second
    vacc_options.owner = third
    local host = Fakes.host({
        players = { first, second, third }, local_player = first,
        userids = { [1] = 10, [2] = 20, [3] = 30 },
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(row_by_userid(snapshot, 10).current_family, "UNSUPPORTED")
    Harness.equal(row_by_userid(snapshot, 20).current_family, "QF")
    Harness.equal(row_by_userid(snapshot, 30).current_family, "VACC")
end)

Harness.test("disguised Spy lifecycle remains Spy and bots need no exception", function()
    local player = Fakes.player({ index = 1, team = 3, class = 8, alive = true })
    local host = Fakes.host({ players = { player }, userids = { [1] = 10 } })
    local row = row_by_userid(Adapter.new(host):capture(), 10)
    Harness.equal(row.current_class, 8)
    Harness.is_nil(row.current_family)
end)

Harness.test("events normalize user ID and reject irrelevant or malformed data", function()
    local host = Fakes.host({ now = 25 })
    local adapter = Adapter.new(host)
    local event = adapter:normalize_event(Fakes.event("player_chargedeployed", { userid = 44 }))
    Harness.equal(event.userid, 44)
    Harness.equal(event.name, "player_chargedeployed")
    Harness.equal(event.time, 25)
    Harness.is_nil(adapter:normalize_event(Fakes.event("round_start", { userid = 44 })))
    Harness.is_nil(adapter:normalize_event(Fakes.event("player_death", { userid = 0 })))
    Harness.is_nil(adapter:normalize_event(Fakes.event("player_team", { userid = 44 })))
    Harness.is_nil(adapter:normalize_event(Fakes.event("player_changeclass", { userid = 44 })))
end)

Harness.test("local user ID and empirical team numbers remain associated", function()
    local local_player = Fakes.player({ index = 1, team = 2, class = 1, alive = true })
    local host = Fakes.host({
        players = { local_player }, local_player = local_player,
        userids = { [1] = 777 },
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(snapshot.local_userid, 777)
    Harness.equal(snapshot.local_team, 2)
end)

Harness.test("resource identity can supply a temporarily unreadable local user ID", function()
    local local_player = Fakes.player({ index = 1, team = 2, class = 1, alive = true })
    local host = Fakes.host({
        players = { local_player }, local_player = local_player,
        resource = Fakes.resource({
            [1] = { connected = true, valid = true, alive = true, team = 2, userid = 777, class = 1, charge = 0 },
        }),
    })
    Harness.equal(Adapter.new(host):capture().local_userid, 777)
end)

Harness.test("current user ID prevents resource facts crossing entity reuse", function()
    local weapon_options = {
        index = 101, item = 29, nonlocal_charge = 0.12, deployed = false,
    }
    local weapon = Fakes.weapon(weapon_options)
    local player = Fakes.player({
        index = 2, team = 3, class = 5, alive = true,
        loadout_weapon = weapon,
    })
    weapon_options.owner = player
    local host = Fakes.host({
        players = { player }, userids = { [2] = 30 },
        resource = Fakes.resource({
            [2] = { connected = true, valid = true, alive = true, team = 3, userid = 20, class = 5, charge = 88 },
        }),
    })
    local snapshot = Adapter.new(host):capture()
    Harness.falsy(snapshot.roster_available)
    Harness.equal(row_by_userid(snapshot, 20).valid, false)
    Harness.equal(row_by_userid(snapshot, 30).current_charge, 12)
end)

Harness.test("visibility gates map round MvM console and game UI", function()
    local host = Fakes.host({})
    local adapter = Adapter.new(host)
    local snapshot = adapter:capture()
    local visible, reason = adapter:visibility(snapshot)
    Harness.truthy(visible)
    Harness.is_nil(reason)
    host.state.console = true
    visible, reason = adapter:visibility(snapshot)
    Harness.falsy(visible)
    Harness.equal(reason, "Source console visible")
    host.state.console = false
    host.state.game_ui = true
    visible, reason = adapter:visibility(snapshot)
    Harness.falsy(visible)
    Harness.equal(reason, "TF2 game UI visible")
    host.state.game_ui = false
    snapshot.is_mvm = true
    visible, reason = adapter:visibility(snapshot)
    Harness.falsy(visible)
    Harness.equal(reason, "MvM is hidden")
    snapshot.is_mvm = false
    snapshot.round_state = 5
    visible, reason = adapter:visibility(snapshot)
    Harness.falsy(visible)
    Harness.equal(reason, "round state 5 is hidden")
    snapshot.round_state = 4
    snapshot.map = nil
    visible, reason = adapter:visibility(snapshot)
    Harness.falsy(visible)
    Harness.equal(reason, "map unavailable")
end)

Harness.test("malformed visibility values have specific fail-closed reasons", function()
    local host = Fakes.host({})
    local adapter = Adapter.new(host)
    local snapshot = adapter:capture()
    snapshot.is_mvm = nil
    local visible, reason = adapter:visibility(snapshot)
    Harness.falsy(visible)
    Harness.equal(reason, "MvM state unavailable")
    snapshot.is_mvm = false
    snapshot.round_state = nil
    visible, reason = adapter:visibility(snapshot)
    Harness.falsy(visible)
    Harness.equal(reason, "round state unavailable")
end)

Harness.test("only documented round states one through four are visible", function()
    local host = Fakes.host({})
    local adapter = Adapter.new(host)
    local snapshot = adapter:capture()
    for round = 0, 10 do
        snapshot.round_state = round
        Harness.equal(adapter:is_visible(snapshot), round >= 1 and round <= 4)
    end
end)

Harness.test("drag input uses the documented left mouse code", function()
    local host = Fakes.host({})
    host.state.menu_open = true
    Adapter.new(host):input_sample()
    Harness.equal(host.state.button, 107)
end)

Harness.test("closed menu skips all mouse and button queries", function()
    local host = Fakes.host({})
    local input = Adapter.new(host):input_sample()
    Harness.falsy(input.menu_open)
    Harness.same_table(host.state.input_calls, {})
end)

Harness.test("client tick is the preferred duplicate-capture revision", function()
    local host = Fakes.host({ delta_tick = 200 })
    host.globals.TickCount = function() return 100 end
    Harness.equal(Adapter.new(host):network_revision(), 100)
end)

Harness.test("last received tick is the duplicate-capture revision fallback", function()
    local host = Fakes.host({ delta_tick = 200 })
    Harness.equal(Adapter.new(host):network_revision(), 200)
    host.state.delta_tick = "malformed"
    Harness.is_nil(Adapter.new(host):network_revision())
end)

Harness.test("malformed entity does not block another readable entity", function()
    local _, good_player, _, good_weapon = medic_pair()
    local bad = Fakes.player({ index = 1, dormant_error = true })
    good_player.options.index = 2
    good_weapon.options.owner = good_player
    local host = Fakes.host({
        players = { bad, good_player }, userids = { [1] = 10, [2] = 20 },
    })
    local snapshot = Adapter.new(host):capture()
    Harness.equal(row_by_userid(snapshot, 20).current_family, "KRITZ")
end)

Harness.test("validation diagnostics expose independent boundary evidence", function()
    local host = Fakes.validation_host()
    local snapshot = Adapter.new(host, true):capture()
    Harness.truthy(snapshot.diagnostics ~= nil)
    Harness.truthy(snapshot.diagnostics.resource_tables.charge)
    Harness.equal(snapshot.diagnostics.resource_disconnected_count, 29)
    Harness.equal(snapshot.diagnostics.resource_malformed_connected_count, 0)
    Harness.equal(#snapshot.diagnostics.resource_rows, 3)
    Harness.equal(snapshot.diagnostics.player_enumeration_count, 3)
    Harness.equal(#snapshot.diagnostics.weapons, 2)
    Harness.falsy(snapshot.diagnostics.current_players[1].weapon_inspection)
    Harness.equal(snapshot.diagnostics.weapons[1].reads.charge_status, "accepted")
    Harness.equal(
        snapshot.diagnostics.weapons[1].reads.deployment_status,
        "accepted"
    )
    Harness.equal(
        snapshot.diagnostics.weapons[1].reads.charge_table,
        "NonLocalTFWeaponMedigunData"
    )
end)

Harness.test("validation diagnostics retain partial failures and dormancy", function()
    local host, _, _, enemy = Fakes.validation_host()
    enemy.family_error = true
    enemy.deployment_error = true
    local snapshot = Adapter.new(host, true):capture()
    local evidence = snapshot.diagnostics.weapons[2]
    Harness.equal(evidence.reads.family_status, "unavailable_or_malformed")
    Harness.equal(evidence.reads.charge_status, "accepted")
    Harness.equal(
        evidence.reads.deployment_status,
        "unavailable_or_malformed"
    )

    enemy.family_error = false
    enemy.deployment_error = false
    enemy.dormant = true
    snapshot = Adapter.new(host, true):capture()
    evidence = snapshot.diagnostics.weapons[2]
    Harness.falsy(evidence.current)
    Harness.equal(evidence.reads.currency, "weapon_not_current")
end)
