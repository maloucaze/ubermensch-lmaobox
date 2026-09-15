local Harness = require("support.harness")
local Fixtures = require("support.fixtures")
local Tracking = require("ubermensch.tracking")

local function find(view, userid)
    for i = 1, #view.candidates do
        if view.candidates[i].userid == userid then
            return view.candidates[i]
        end
    end
end

local function baseline(tracker, players, overrides)
    return Tracking.reconcile(
        tracker,
        Fixtures.snapshot(setmetatable({ players = players }, {
            __index = overrides or {},
        }))
    )
end

Harness.test("authoritative alive counts include every playable class", function()
    local tracker = Tracking.new()
    local local_player = Fixtures.player(10, 1, 2, nil, nil, "resource")
    local_player.class = 1
    local_player.current_present = true
    local_player.current_team = 2
    local_player.current_class = 1
    local_player.current_alive = false
    local ally = Fixtures.player(11, 2, 2, nil, nil, "resource")
    ally.class = 3
    local enemy_one = Fixtures.player(20, 3, 3, nil, nil, "resource")
    enemy_one.class = 7
    local enemy_two = Fixtures.player(21, 4, 3, nil, nil, "resource")
    enemy_two.class = 8

    local view = baseline(tracker, {
        local_player,
        ally,
        enemy_one,
        enemy_two,
    })
    Harness.equal(view.alive_counts[2], 1)
    Harness.equal(view.alive_counts[3], 2)
end)

Harness.test("failed roster authority withholds alive counts", function()
    local tracker = Tracking.new()
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        players = {},
        roster_available = false,
    }))
    Harness.is_nil(view.alive_counts)
end)

Harness.test("authoritative roster membership and team changes replace counts", function()
    local tracker = Tracking.new()
    local local_player = Fixtures.player(10, 1, 2, nil, nil, "resource")
    local_player.class = 1
    local enemy = Fixtures.player(20, 2, 3, nil, nil, "resource")
    enemy.class = 1
    local view = baseline(tracker, { local_player, enemy })
    Harness.equal(view.alive_counts[2], 1)
    Harness.equal(view.alive_counts[3], 1)

    enemy.team = 2
    view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { local_player, enemy },
    }))
    Harness.equal(view.alive_counts[2], 2)
    Harness.equal(view.alive_counts[3], 0)

    view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = { local_player },
    }))
    Harness.equal(view.alive_counts[2], 1)
    Harness.equal(view.alive_counts[3], 0)
end)

Harness.test("current fields retain independent current sources", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 73, "current")
    local medic = find(baseline(tracker, { row }), 20)
    Harness.equal(medic.family, "STOCK")
    Harness.equal(medic.family_source, "current")
    Harness.equal(medic.charge, 73)
    Harness.equal(medic.charge_source, "current")
    Harness.equal(medic.deployed, false)
    Harness.equal(medic.deployment_source, "current")
end)

Harness.test("partial current failures preserve readable fields", function()
    local tracker = Tracking.new()
    local charge_only = Fixtures.player(20, 2, 3, nil, 63, "current")
    charge_only.current_deployed = nil
    local medic = find(baseline(tracker, { charge_only }), 20)
    Harness.is_nil(medic.family)
    Harness.equal(medic.charge, 63)
    Harness.equal(medic.charge_source, "current")
    Harness.equal(medic.deployment_source, "unknown")

    local family_only = Fixtures.player(20, 2, 3, "KRITZ", nil, "current")
    family_only.current_deployed = false
    medic = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { family_only },
    })), 20)
    Harness.equal(medic.family, "KRITZ")
    Harness.equal(medic.family_source, "current")
    Harness.truthy(medic.charge ~= nil)
end)

Harness.test("current deployment remains independent without family or charge", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, nil, nil, "current")
    row.current_deployed = true
    local medic = find(baseline(tracker, { row }), 20)
    Harness.is_nil(medic.family)
    Harness.is_nil(medic.charge)
    Harness.equal(medic.deployed, true)
    Harness.equal(medic.deployment_source, "current")
end)

Harness.test("resource endpoints are approximate anchors", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, nil, 0, "resource")
    row.current_present = true
    row.current_family = "STOCK"
    row.current_deployed = false
    local medic = find(baseline(tracker, { row }), 20)
    Harness.equal(medic.charge, 0)
    Harness.equal(medic.charge_source, "resource")
    row.resource_charge = 100
    medic = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { row },
    })), 20)
    Harness.equal(medic.charge, 100)
    Harness.equal(medic.charge_source, "resource")
end)

Harness.test("deployment event is user-ID-specific and drains", function()
    local tracker = Tracking.new()
    local first = Fixtures.player(20, 2, 3, "STOCK", 50, "current")
    local second = Fixtures.player(21, 3, 3, "STOCK", 60, "current")
    baseline(tracker, { first, second })
    Tracking.enqueue(tracker, { name = "player_chargedeployed", userid = 21, time = 10 })
    first.current_charge = nil
    first.resource_charge = nil
    first.current_deployed = nil
    second.current_charge = nil
    second.resource_charge = nil
    second.current_deployed = nil
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = { first, second },
    }))
    Harness.near(find(view, 21).charge, 75, 1e-9)
    Harness.truthy(find(view, 21).deployed)
    Harness.near(find(view, 20).charge, 55, 1e-9)
    Harness.falsy(find(view, 20).deployed)
end)

Harness.test("death event creates a fallback only for its user ID", function()
    local tracker = Tracking.new()
    local first = Fixtures.player(20, 2, 3, "STOCK", 50, "current")
    local second = Fixtures.player(21, 3, 3, "KRITZ", 60, "current")
    baseline(tracker, { first, second })
    Tracking.enqueue(tracker, {
        name = "player_death", userid = 21, time = 10.5,
    })
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = {},
        roster_available = false,
    }))
    Harness.equal(find(view, 20).userid, 20)
    Harness.equal(#view.dead_candidates, 1)
    Harness.equal(view.dead_candidates[1].userid, 21)
    Harness.equal(view.dead_candidates[1].died_at, 10.5)
end)

Harness.test("event-derived deployment cannot remain active after its drain", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 90, "current")
    baseline(tracker, { row })
    Tracking.enqueue(tracker, {
        name = "player_chargedeployed", userid = 20, time = 10,
    })
    row.current_family = nil
    row.current_charge = nil
    row.current_deployed = nil
    row.resource_charge = 3
    local medic = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 19,
        players = { row },
    })), 20)
    Harness.equal(medic.charge, 3)
    Harness.equal(medic.charge_source, "resource")
    Harness.equal(medic.deployed, false)
    Harness.equal(medic.deployment_source, "estimate")
end)

Harness.test("same-cycle current charge overrides event and resource", function()
    local tracker = Tracking.new()
    baseline(tracker, { Fixtures.player(20, 2, 3, "STOCK", 50, "current") })
    Tracking.enqueue(tracker, { name = "player_chargedeployed", userid = 20, time = 10 })
    local row = Fixtures.player(20, 2, 3, "STOCK", 42, "current")
    row.resource_charge = 77
    local medic = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { row },
    })), 20)
    Harness.equal(medic.charge, 42)
    Harness.equal(medic.charge_source, "current")
    Harness.equal(medic.deployed, false)
end)

Harness.test("spawn and inventory anchor zero while retaining family", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "KRITZ", 80, "current")
    baseline(tracker, { row })
    row.current_charge = nil
    row.resource_charge = nil
    row.current_family = nil
    row.current_deployed = nil
    Tracking.enqueue(tracker, { name = "player_spawn", userid = 20, time = 10 })
    local medic = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = { row },
    })), 20)
    Harness.equal(medic.family, "KRITZ")
    Harness.near(medic.charge, 6.25, 1e-9)
    Harness.equal(medic.charge_source, "estimate")
end)

Harness.test("post-inventory application uses the same retained-family zero anchor", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 80, "current")
    baseline(tracker, { row })
    row.current_charge = nil
    row.current_family = nil
    row.current_deployed = nil
    Tracking.enqueue(tracker, {
        name = "post_inventory_application", userid = 20, time = 10,
    })
    local medic = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { row },
    })), 20)
    Harness.equal(medic.family, "STOCK")
    Harness.near(medic.charge, 2.5, 1e-9)
end)

Harness.test("death moves a known Medic to the dead fallback", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 50, "current")
    baseline(tracker, { row })
    row.current_alive = false
    row.alive = false
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { row },
    }))
    Harness.is_nil(find(view, 20))
    Harness.equal(#view.dead_candidates, 1)
    Harness.equal(view.dead_candidates[1].userid, 20)
    Harness.equal(view.dead_candidates[1].family, "STOCK")
    Harness.equal(view.dead_candidates[1].died_at, 11)

    row.alive = true
    row.current_alive = true
    row.class = 1
    row.current_class = 1
    view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = { row },
    }))
    Harness.is_nil(find(view, 20))
    Harness.equal(#view.dead_candidates, 0)
end)

Harness.test("repeated dead observations preserve the first death time", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "KRITZ", 50, "current")
    baseline(tracker, { row })
    row.alive = false
    row.current_alive = false
    local first = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { row },
    }))
    local second = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 15,
        players = { row },
    }))
    Harness.equal(first.dead_candidates[1].died_at, 11)
    Harness.equal(second.dead_candidates[1].died_at, 11)
end)

Harness.test("respawn clears dead fallback and creates a living candidate", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 50, "current")
    baseline(tracker, { row })
    row.alive = false
    row.current_alive = false
    Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { row },
    }))
    row.alive = true
    row.current_alive = true
    row.current_charge = 0
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = { row },
    }))
    Harness.equal(#view.dead_candidates, 0)
    Harness.equal(find(view, 20).charge, 0)
end)

Harness.test("team change clears an incompatible dead fallback", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 50, "current")
    baseline(tracker, { row })
    Tracking.enqueue(tracker, {
        name = "player_death", userid = 20, time = 11,
    })
    local dead = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = {},
        roster_available = false,
    }))
    Harness.equal(#dead.dead_candidates, 1)
    Tracking.enqueue(tracker, {
        name = "player_team", userid = 20, team = 2, time = 12,
    })
    local moved = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = {},
        roster_available = false,
    }))
    Harness.equal(#moved.dead_candidates, 0)
end)

Harness.test("loss of readability estimates indefinitely from original anchor", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 50, "current")
    baseline(tracker, { row })
    row.current_family = nil
    row.current_charge = nil
    row.current_deployed = nil
    row.resource_charge = nil
    local first = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = { row },
    })), 20)
    local later = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 30,
        players = { row },
    })), 20)
    Harness.equal(first.charge, 55)
    Harness.equal(later.charge, 100)
    Harness.equal(later.family, "STOCK")
    Harness.equal(later.charge_source, "estimate")
end)

Harness.test("current reacquisition immediately replaces a distant estimate", function()
    local tracker = Tracking.new()
    local row = Fixtures.player(20, 2, 3, "STOCK", 50, "current")
    baseline(tracker, { row })
    row.current_charge = nil
    row.current_family = nil
    row.current_deployed = nil
    local estimated = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 12,
        players = { row },
    })), 20)
    Harness.equal(estimated.charge, 55)
    row.current_charge = 10
    row.current_family = "STOCK"
    row.current_deployed = false
    local current = find(Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 13,
        players = { row },
    })), 20)
    Harness.equal(current.charge, 10)
    Harness.equal(current.charge_source, "current")
end)

Harness.test("entity index reuse never transfers user-ID event state", function()
    local tracker = Tracking.new()
    baseline(tracker, { Fixtures.player(20, 2, 3, "STOCK", 50, "current") })
    Tracking.enqueue(tracker, { name = "player_chargedeployed", userid = 20, time = 10 })
    local replacement = Fixtures.player(30, 2, 3, "STOCK", 5, "current")
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = { replacement },
    }))
    Harness.equal(find(view, 30).charge, 5)
    Harness.is_nil(find(view, 20))
end)

Harness.test("authoritative roster omission prunes obsolete records", function()
    local tracker = Tracking.new()
    baseline(tracker, { Fixtures.player(20, 2, 3, "STOCK", 50, "current") })
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 11,
        players = {},
        roster_available = true,
    }))
    Harness.equal(#view.candidates, 0)
    Harness.is_nil(next(tracker.records))
end)

Harness.test("map reset clears old retained records", function()
    local tracker = Tracking.new()
    baseline(tracker, { Fixtures.player(20, 2, 3, "STOCK", 50, "current") })
    local view = Tracking.reconcile(tracker, Fixtures.snapshot({
        now = 20,
        map = "pl_upward",
        players = {},
        roster_available = false,
    }))
    Harness.equal(#view.candidates, 0)
end)

Harness.test("event queue is ordered bounded and emptied", function()
    local tracker = Tracking.new()
    for userid = 1, 70 do
        Tracking.enqueue(tracker, {
            name = "player_spawn",
            userid = userid,
            time = userid,
        })
    end
    Harness.equal(#tracker.events, 64)
    Harness.equal(tracker.events[1].userid, 7)
    Harness.equal(tracker.events[64].userid, 70)
    Tracking.reconcile(tracker, Fixtures.snapshot({ roster_available = false }))
    Harness.equal(#tracker.events, 0)
end)

Harness.test("repeated unchanged full roster does not grow records", function()
    local tracker = Tracking.new()
    local rows = {
        Fixtures.player(20, 2, 2, "STOCK", 50, "current"),
        Fixtures.player(30, 3, 3, "KRITZ", 60, "current"),
    }
    for now = 1, 100 do
        Tracking.reconcile(tracker, Fixtures.snapshot({ now = now, players = rows }))
    end
    local count = 0
    for _ in pairs(tracker.records) do count = count + 1 end
    Harness.equal(count, 2)
end)
