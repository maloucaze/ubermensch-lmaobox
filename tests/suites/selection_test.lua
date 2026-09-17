local Harness = require("support.harness")
local Selection = require("ubermensch.selection")

local function candidate(index, family, charge, source, deployed, overrides)
    local result = {
        userid = 100 + index,
        entity_index = index,
        team = 2,
        alive = true,
        family = family,
        charge = charge,
        charge_source = source,
        deployed = deployed == true,
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

Harness.test("active candidate outranks ready inactive candidate", function()
    local active = candidate(1, "STOCK", 20, "estimate", true)
    local ready = candidate(2, "STOCK", 100, "current", false)
    Harness.equal(Selection.for_team({ ready, active }, 2).entity_index, 1)
end)

Harness.test("active candidates maximize remaining charge", function()
    local low = candidate(1, "STOCK", 25, "current", true)
    local high = candidate(2, "STOCK", 70, "estimate", true)
    Harness.equal(Selection.for_team({ low, high }, 2).entity_index, 2)
end)

Harness.test("normal candidates minimize family-specific time", function()
    local stock = candidate(1, "STOCK", 70, "current", false)
    local kritz = candidate(2, "KRITZ", 65, "current", false)
    Harness.equal(Selection.for_team({ stock, kritz }, 2).entity_index, 2)
end)

Harness.test("Quick-Fix participates in active and readiness selection", function()
    local active = candidate(1, "QF", 20, "current", true)
    local ready = candidate(2, "STOCK", 100, "current", false)
    Harness.equal(Selection.for_team({ ready, active }, 2), active)

    active.deployed = false
    active.charge = 100
    ready.charge = 95
    Harness.equal(Selection.for_team({ ready, active }, 2), active)
end)

Harness.test("equal readiness uses Stock then Kritz then Quick-Fix", function()
    local stock = candidate(1, "STOCK", 100, "estimate", false)
    local kritz = candidate(2, "KRITZ", 100, "current", false)
    local quickfix = candidate(3, "QF", 100, "current", false)
    Harness.equal(Selection.for_team({ quickfix, kritz, stock }, 2), stock)
    Harness.equal(Selection.for_team({ quickfix, kritz }, 2), kritz)
end)

Harness.test("family preference does not override readiness outside tolerance", function()
    local stock = candidate(1, "STOCK", 90, "current", false)
    local quickfix = candidate(2, "QF", 100, "current", false)
    Harness.equal(Selection.for_team({ stock, quickfix }, 2), quickfix)
end)

Harness.test("numeric advantage outside tolerance beats freshness", function()
    local current = candidate(1, "STOCK", 50, "current", false)
    local estimate = candidate(2, "STOCK", 51, "estimate", false)
    Harness.equal(Selection.for_team({ current, estimate }, 2).entity_index, 2)
end)

Harness.test("freshness orders current resource estimate inside tolerance", function()
    local estimated = candidate(3, "STOCK", 50, "estimate", false)
    local resource = candidate(2, "STOCK", 50, "resource", false)
    local current = candidate(1, "STOCK", 50, "current", false)
    Harness.equal(Selection.for_team({ estimated, resource }, 2).entity_index, 2)
    Harness.equal(Selection.for_team({ resource, current }, 2).entity_index, 1)
end)

Harness.test("active 0.1 point tie retains prior then lowest index", function()
    local first = candidate(8, "STOCK", 50, "current", true)
    local prior = candidate(9, "STOCK", 50.1, "current", true)
    Harness.equal(
        Selection.for_team({ first, prior }, 2, prior.userid).entity_index,
        9
    )
    Harness.equal(Selection.for_team({ first, prior }, 2).entity_index, 8)
end)

Harness.test("family order does not replace active-charge tie rules", function()
    local stock = candidate(1, "STOCK", 50, "estimate", true)
    local quickfix = candidate(2, "QF", 50, "current", true)
    Harness.equal(Selection.for_team({ stock, quickfix }, 2), quickfix)
end)

Harness.test("normal 0.05 second tie retains prior", function()
    local first = candidate(4, "STOCK", 50, "current", false)
    local prior = candidate(5, "STOCK", 50.125, "current", false)
    Harness.equal(
        Selection.for_team({ first, prior }, 2, prior.userid).entity_index,
        5
    )
end)

Harness.test("dead and wrong-team candidates are ignored", function()
    local dead = candidate(1, "STOCK", 100, "current", false, { alive = false })
    local wrong = candidate(3, "STOCK", 100, "current", false, { team = 3 })
    Harness.is_nil(Selection.for_team({ dead, wrong }, 2))
end)

Harness.test("numeric supported candidate outranks unidentified fallback", function()
    local fallback = candidate(1, nil, nil, "unknown", false)
    local numeric = candidate(2, "STOCK", 0, "estimate", false)
    Harness.equal(Selection.for_team({ fallback, numeric }, 2).entity_index, 2)
    Harness.equal(Selection.for_team({ fallback }, 2).entity_index, 1)
end)

Harness.test("Vaccinator is a display fallback below every supported family", function()
    local vacc = candidate(1, "VACC", 100, "current", false)
    local stock_unknown = candidate(2, "STOCK", nil, "unknown", false)
    local quickfix = candidate(3, "QF", 0, "estimate", false)
    Harness.equal(Selection.for_team({ vacc, stock_unknown }, 2), stock_unknown)
    Harness.equal(Selection.for_team({ vacc, quickfix }, 2), quickfix)
    Harness.equal(Selection.for_team({ vacc }, 2), vacc)
end)

Harness.test("Vaccinator fallback prefers charge and outranks unknown equipment", function()
    local low = candidate(1, "VACC", 25, "current", false)
    local high = candidate(2, "VACC", 75, "resource", false)
    local unknown = candidate(3, nil, 100, "current", false, {
        unsupported = true,
    })
    Harness.equal(Selection.for_team({ low, high, unknown }, 2), high)
    Harness.equal(Selection.for_team({ low, unknown }, 2), low)
    Harness.equal(Selection.for_team({ unknown }, 2), unknown)
end)

Harness.test("ally and enemy selection are independent", function()
    local ally = candidate(1, "STOCK", 80, "current", false)
    local enemy = candidate(2, "KRITZ", 90, "current", false, { team = 3 })
    Harness.equal(Selection.for_team({ ally, enemy }, 2).entity_index, 1)
    Harness.equal(Selection.for_team({ ally, enemy }, 3).entity_index, 2)
end)

Harness.test("dead fallback retains prior then chooses newest death", function()
    local old = candidate(1, "STOCK", nil, "dead", false, {
        alive = false, dead = true, died_at = 20,
    })
    local newest = candidate(2, "KRITZ", nil, "dead", false, {
        alive = false, dead = true, died_at = 30,
    })
    Harness.equal(
        Selection.dead_for_team({ old, newest }, 2, old.userid),
        old
    )
    Harness.equal(Selection.dead_for_team({ old, newest }, 2), newest)
end)

Harness.test("dead fallback ties use the lowest entity index", function()
    local high = candidate(8, "STOCK", nil, "dead", false, {
        alive = false, dead = true, died_at = 30,
    })
    local low = candidate(3, "KRITZ", nil, "dead", false, {
        alive = false, dead = true, died_at = 30,
    })
    Harness.equal(Selection.dead_for_team({ high, low }, 2), low)
end)
