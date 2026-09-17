local Harness = require("support.harness")
local Fixtures = require("support.fixtures")
local Constants = require("ubermensch.constants")
local Formatting = require("ubermensch.formatting")
local State = require("ubermensch.state")

local function tracking(candidates, overrides)
    local result = {
        candidates = candidates,
        roster_available = true,
        local_team = 2,
        last_local_team = 2,
        local_class = 1,
        local_alive = true,
        alive_counts = { [2] = 1, [3] = 1 },
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

Harness.test("exact baseline formatting", function()
    local model = {
        local_side = Fixtures.side(2, "KRITZ", 75, "current", false),
        enemy_side = Fixtures.side(3, "STOCK", 50, "current", false),
        comparison = { status = "ADV", charge_difference = 25, time_difference = 12 },
        team_counts = {
            available = true,
            local_count = 8,
            enemy_count = 3,
        },
        warning = false,
    }
    local prepared = Formatting.prepare(model)
    Harness.same_table(prepared.lines, {
        "RED |  75% |   8s | KRITZ",
        "BLU |  50% |  20s | STOCK",
        "ADV | +25% | +12s",
        "8 vs. 3",
    })
end)

Harness.test("equal columns align exactly with whole numbers", function()
    local local_side = Fixtures.side(2, "STOCK", 50, "current", false)
    local enemy_side = Fixtures.side(3, "STOCK", 50, "current", false)
    local prepared = Formatting.prepare({
        local_side = local_side,
        enemy_side = enemy_side,
        comparison = {
            status = "EQL",
            charge_difference = 0,
            time_difference = 0,
        },
        team_counts = {
            available = true,
            local_count = 12,
            enemy_count = 12,
        },
        warning = false,
    })
    Harness.same_table(prepared.lines, {
        "RED | 50% | 20s | STOCK",
        "BLU | 50% | 20s | STOCK",
        "EQL |  0% |  0s",
        "12 vs. 12",
    })
end)

Harness.test("team counts format factual and unavailable roster states", function()
    local model = {
        local_side = Fixtures.side(2, "STOCK", 50, "current", false),
        enemy_side = Fixtures.side(3, "STOCK", 50, "current", false),
        comparison = {
            status = "EQL",
            charge_difference = 0,
            time_difference = 0,
        },
        team_counts = {
            available = true,
            local_count = 1,
            enemy_count = 2,
        },
        warning = false,
    }
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[4], "1 vs. 2")
    Harness.same_table(
        prepared.colors[4],
        Constants.TEAM_COUNT_COLORS.text
    )

    model.team_counts = { available = false }
    Formatting.prepare(model, prepared)
    Harness.equal(prepared.lines[4], "- vs. -")
    Harness.same_table(
        prepared.colors[4],
        Constants.TEAM_COUNT_COLORS.text
    )
end)

Harness.test("BLU local side is listed first", function()
    local blue = Fixtures.side(3, "STOCK", 50, "current", false)
    local red = Fixtures.side(2, "KRITZ", 75, "current", false)
    local prepared = Formatting.prepare({
        local_side = blue,
        enemy_side = red,
        comparison = { status = "DIS", charge_difference = -25, time_difference = -12 },
        warning = false,
    })
    Harness.equal(prepared.lines[1], "BLU |  50% |  20s | STOCK")
    Harness.equal(prepared.lines[2], "RED |  75% |   8s | KRITZ")
end)

Harness.test("missing side formatting omits time", function()
    local model = State.resolve(tracking({
        Fixtures.side(2, "STOCK", 75, "current", false),
    }), {})
    local prepared = Formatting.prepare(model)
    Harness.same_table(prepared.lines, {
        "RED |  75% | 10s | STOCK",
        "BLU | NO MED",
        "ADV | +75% |   -",
        "1 vs. 1",
    })
    Harness.falsy(prepared.warning)
    Harness.truthy(model.team_counts.available)
end)

Harness.test("approximate formatting and border", function()
    local local_side = Fixtures.side(2, "STOCK", 88, "estimate", false, "estimate")
    local enemy = Fixtures.side(3, "KRITZ", 73, "current", false)
    local prepared = Formatting.prepare({
        local_side = local_side,
        enemy_side = enemy,
        comparison = { status = "EQL", charge_difference = 15, time_difference = 3.75 },
        warning = true,
    })
    Harness.same_table(prepared.lines, {
        "RED |  ~88% |  ~5s | STOCK",
        "BLU |   73% |   9s | KRITZ",
        "EQL | ~+15% | ~+4s",
        "- vs. -",
    })
    Harness.truthy(prepared.warning)
end)

Harness.test("resource readiness is marked approximate", function()
    local side = Fixtures.side(2, "STOCK", 50, "resource", false)
    Harness.equal(
        Formatting.side_line(side),
        "RED | ~50% | ~20s | STOCK"
    )
end)

Harness.test("deployment does not change readiness text", function()
    local side = Fixtures.side(2, "STOCK", 50, "current", true)
    Harness.equal(Formatting.side_line(side), "RED | 50% | 20s | STOCK")
end)

Harness.test("retained family marks otherwise current differences approximate", function()
    local local_side = Fixtures.side(2, "STOCK", 80, "current", false)
    local_side.family_source = "retained"
    local enemy = Fixtures.side(3, "STOCK", 50, "current", false)
    local prepared = Formatting.prepare({
        local_side = local_side,
        enemy_side = enemy,
        comparison = { status = "ADV", charge_difference = 30, time_difference = 12 },
        warning = true,
    })
    Harness.equal(prepared.lines[1], "RED |   80% |   ~8s | STOCK")
    Harness.equal(prepared.lines[3], "ADV | ~+30% | ~+12s")
end)

Harness.test("genuinely unknown fields produce dash", function()
    local model = State.resolve(tracking({
        Fixtures.side(2, nil, nil, "unknown", false, "unknown"),
        Fixtures.side(3, nil, nil, "unknown", false, "unknown"),
    }), {})
    local prepared = Formatting.prepare(model)
    Harness.same_table(prepared.lines, {
        "RED | ?% | - | UNKNOWN",
        "BLU | ?% | - | UNKNOWN",
        "-",
        "1 vs. 1",
    })
    Harness.truthy(prepared.warning)
end)

Harness.test("two confirmed missing sides compare equal", function()
    local prepared = Formatting.prepare(State.resolve(tracking({}), {}))
    Harness.same_table(prepared.lines, {
        "RED | NO MED",
        "BLU | NO MED",
        "EQL | 0% | -",
        "1 vs. 1",
    })
    Harness.falsy(prepared.warning)
end)

Harness.test("dead Medic is compact gray and does not warn", function()
    local dead = {
        userid = 20,
        entity_index = 2,
        team = 2,
        alive = false,
        dead = true,
        family = "STOCK",
        died_at = 11,
    }
    local model = State.resolve(tracking({}, {
        dead_candidates = { dead },
    }), {})
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[1], "RED | DEAD MED")
    Harness.equal(prepared.lines[2], "BLU | NO MED")
    Harness.equal(prepared.lines[3], "EQL | 0% | -")
    Harness.same_table(prepared.colors[1], Constants.COLORS.unavailable)
    Harness.same_table(prepared.colors[2], Constants.COLORS.unavailable)
    Harness.falsy(prepared.warning)
end)

Harness.test("living unknown Medic outranks a dead Medic", function()
    local alive = Fixtures.side(2, nil, nil, "unknown", false, "unknown")
    alive.userid = 21
    local dead = {
        userid = 20,
        entity_index = 2,
        team = 2,
        alive = false,
        dead = true,
        family = "STOCK",
        died_at = 11,
    }
    local model = State.resolve(tracking({ alive }, {
        dead_candidates = { dead },
    }), {})
    Harness.equal(model.local_side.userid, 21)
    Harness.falsy(model.local_side.dead)
end)

Harness.test("dead side compares as fixed zero without a time difference", function()
    local alive = Fixtures.side(2, "STOCK", 50, "current", false)
    local dead = {
        userid = 30,
        entity_index = 3,
        team = 3,
        alive = false,
        dead = true,
        family = "KRITZ",
        died_at = 11,
    }
    local model = State.resolve(tracking({ alive }, {
        dead_candidates = { dead },
    }), {})
    Harness.equal(model.comparison.status, "ADV")
    Harness.equal(model.comparison.charge_difference, 50)
    Harness.is_nil(model.comparison.time_difference)
    Harness.equal(Formatting.comparison_line(model), "ADV | +50% | -")
end)

Harness.test("team readiness uses whole-second half-away rounding", function()
    local side = Fixtures.side(2, "STOCK", 48.75, "current", false)
    Harness.equal(Formatting.side_line(side), "RED | 49% | 21s | STOCK")
end)

Harness.test("cached lines invalidate when only displayed readiness changes", function()
    local local_side = Fixtures.side(2, "STOCK", 48.7, "current", false)
    local model = {
        local_side = local_side,
        enemy_side = Fixtures.side(3, "STOCK", 50, "current", false),
        comparison = {
            status = "EQL",
            charge_difference = -1.3,
            time_difference = -0.52,
        },
        warning = false,
    }
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[1], "RED | 49% | 21s | STOCK")
    local_side.charge = 49.2
    Formatting.prepare(model, prepared)
    Harness.equal(prepared.lines[1], "RED | 49% | 20s | STOCK")
end)

Harness.test("a wider numeric token realigns every normal line", function()
    local local_side = Fixtures.side(2, "STOCK", 99, "current", false)
    local enemy_side = Fixtures.side(3, "STOCK", 99, "current", false)
    local model = {
        local_side = local_side,
        enemy_side = enemy_side,
        comparison = {
            status = "EQL",
            charge_difference = 0,
            time_difference = 0,
        },
        warning = false,
    }
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[2], "BLU | 99% | 0s | STOCK")
    local_side.charge = 100
    Formatting.prepare(model, prepared)
    Harness.equal(prepared.lines[2], "BLU |  99% | 0s | STOCK")
end)

Harness.test("partial side information cannot fabricate readiness", function()
    local charge_only = Fixtures.side(2, nil, 63, "current", false)
    local family_only = Fixtures.side(3, "STOCK", nil, "unknown", false)
    family_only.family_source = "retained"
    Harness.equal(
        Formatting.side_line(charge_only),
        "RED | 63% | - | UNKNOWN"
    )
    Harness.equal(
        Formatting.side_line(family_only),
        "BLU | ?% | - | STOCK"
    )
end)

Harness.test("self Medic ignores other allied candidates", function()
    local local_medic = Fixtures.side(2, "QF", 20, "current", false)
    local_medic.is_local = true
    local other = Fixtures.side(2, "STOCK", 100, "current", false)
    local enemy = Fixtures.side(3, "STOCK", 50, "current", false)
    local model = State.resolve(tracking({ local_medic, other, enemy }, {
        local_class = 5,
        local_alive = true,
    }), {})
    Harness.equal(model.local_side.charge, 20)
    Harness.equal(model.local_side.family, "QF")
    Harness.truthy(model.self_mode)
end)

Harness.test("Quick-Fix uses normal readiness comparison and formatting", function()
    local local_side = Fixtures.side(2, "QF", 45, "current", false)
    local enemy_side = Fixtures.side(3, "STOCK", 50, "current", false)
    local model = State.resolve(tracking({ local_side, enemy_side }), {})
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[1], "RED | 45% | 20s | QF")
    Harness.equal(prepared.lines[2], "BLU | 50% | 20s | STOCK")
    Harness.equal(prepared.lines[3], "EQL | -5% |  0s")
end)

Harness.test("Vaccinator is display-only with no readiness or comparison", function()
    local vacc = Fixtures.side(2, "VACC", 50, "current", true)
    vacc.deployment_source = "unknown"
    local enemy = Fixtures.side(3, "STOCK", 50, "current", false)
    local model = State.resolve(tracking({ vacc, enemy }), {})
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[1], "RED | 50% |   - | VACC")
    Harness.equal(prepared.lines[3], "-")
    Harness.falsy(prepared.warning)
    Harness.same_table(prepared.colors[1], Constants.COLORS.ready)
    Harness.same_table(
        Formatting.side_color(Fixtures.side(2, "VACC", 24, "current", true)),
        Constants.COLORS.text
    )
    Harness.same_table(
        Formatting.side_color(Fixtures.side(3, "VACC", 25, "current", true)),
        Constants.COLORS.ready
    )
end)

Harness.test("self Vaccinator cannot be replaced by allied Stock", function()
    local local_medic = Fixtures.side(2, "VACC", 25, "current", false)
    local_medic.is_local = true
    local allied_stock = Fixtures.side(2, "STOCK", 100, "current", false)
    local enemy = Fixtures.side(3, "QF", 50, "current", false)
    local model = State.resolve(tracking({ local_medic, allied_stock, enemy }, {
        local_class = 5,
        local_alive = true,
    }), {})
    Harness.equal(model.local_side.family, "VACC")
    Harness.is_nil(model.comparison)
end)

Harness.test("unknown living and dead Medics never become NO MED", function()
    local unknown = Fixtures.side(2, nil, 50, "current", false)
    unknown.unsupported = true
    local living = State.resolve(tracking({ unknown }), {})
    Harness.equal(Formatting.side_line(living.local_side), "RED | 50% | - | UNKNOWN")

    local dead = {
        userid = 20,
        entity_index = 2,
        team = 2,
        alive = false,
        dead = true,
        unsupported = true,
        died_at = 11,
    }
    local deceased = State.resolve(tracking({}, {
        dead_candidates = { dead },
    }), {})
    Harness.equal(Formatting.side_line(deceased.local_side), "RED | DEAD MED")
end)

Harness.test("dead local Medic uses team mode", function()
    local local_medic = Fixtures.side(2, "STOCK", 20, "current", false)
    local_medic.is_local = true
    local other = Fixtures.side(2, "STOCK", 90, "current", false)
    local enemy = Fixtures.side(3, "STOCK", 50, "current", false)
    local model = State.resolve(tracking({ local_medic, other, enemy }, {
        local_class = 5,
        local_alive = false,
    }), {})
    Harness.equal(model.local_side.charge, 90)
    Harness.falsy(model.self_mode)
end)

Harness.test("every non-Medic class uses team comparison mode", function()
    for class = 1, 9 do
        if class ~= 5 then
            local ally = Fixtures.side(2, "STOCK", 90, "current", false)
            local enemy = Fixtures.side(3, "STOCK", 50, "current", false)
            local model = State.resolve(tracking({ ally, enemy }, {
                local_class = class,
                local_alive = true,
            }), {})
            Harness.falsy(model.self_mode)
            Harness.equal(model.local_side.charge, 90)
        end
    end
end)

Harness.test("supported zero still wins known-side missing precedence", function()
    local model = State.resolve(tracking({
        Fixtures.side(2, "STOCK", 0, "current", false),
    }), {})
    Harness.equal(model.comparison.status, "ADV")
    Harness.equal(Formatting.comparison_line(model), "ADV | 0% | -")
end)

Harness.test("last local team preserves ordering during identity loss", function()
    local lost = tracking({}, {
        last_local_team = 3,
        roster_available = false,
    })
    lost.local_team = nil
    local model = State.resolve(lost, {})
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[1], "BLU | ?% | - | UNKNOWN")
    Harness.equal(prepared.lines[2], "RED | ?% | - | UNKNOWN")
    Harness.equal(prepared.lines[3], "-")
end)

Harness.test("failed roster never proves no Medic", function()
    local model = State.resolve(tracking({}, { roster_available = false }), {})
    Harness.equal(
        Formatting.side_line(model.local_side),
        "RED | ?% | - | UNKNOWN"
    )
    Harness.equal(Formatting.comparison_line(model), "-")
    Harness.truthy(model.warning)
    Harness.falsy(model.team_counts.available)
    Harness.equal(Formatting.prepare(model).lines[4], "- vs. -")
end)

Harness.test("colors obey deployment readiness and status precedence", function()
    Harness.same_table(Formatting.side_color(Fixtures.side(2, "STOCK", 100, "current", false)), Constants.COLORS.ready)
    Harness.same_table(Formatting.side_color(Fixtures.side(2, "STOCK", 100, "estimate", true)), Constants.COLORS.red_deployed)
    Harness.same_table(Formatting.side_color(Fixtures.side(3, "STOCK", 100, "current", true)), Constants.COLORS.blu_deployed)
    Harness.same_table(Formatting.side_color(Fixtures.side(3, "STOCK", 100, "estimate", false)), Constants.COLORS.ready)
    Harness.same_table(Formatting.comparison_color({ status = "ADV" }), Constants.COLORS.advantage)
    Harness.same_table(Formatting.comparison_color({ status = "DIS" }), Constants.COLORS.disadvantage)
    Harness.same_table(Formatting.comparison_color({ status = "EQL" }), Constants.COLORS.text)
    Harness.same_table(Formatting.comparison_color(nil), Constants.COLORS.text)
    Harness.same_table(Formatting.team_counts_color(), Constants.TEAM_COUNT_COLORS.text)
end)

Harness.test("all fixed RGBA values match the specification", function()
    Harness.same_table(Constants.COLORS.advantage, { 80, 220, 120, 255 })
    Harness.same_table(Constants.COLORS.disadvantage, { 235, 80, 80, 255 })
    Harness.same_table(Constants.COLORS.text, { 255, 255, 255, 255 })
    Harness.same_table(Constants.COLORS.ready, { 255, 235, 60, 255 })
    Harness.same_table(Constants.COLORS.red_deployed, { 255, 80, 80, 255 })
    Harness.same_table(Constants.COLORS.blu_deployed, { 80, 160, 255, 255 })
    Harness.same_table(Constants.COLORS.warning, { 170, 140, 0, 255 })
    Harness.same_table(Constants.COLORS.unavailable, { 170, 170, 170, 255 })
    Harness.same_table(Constants.COLORS.background, { 15, 15, 18, 170 })
    Harness.same_table(Constants.TEAM_COUNT_COLORS.text, { 255, 255, 255, 255 })
    Harness.same_table(Constants.TEAM_COUNT_COLORS.separator, { 170, 170, 170, 255 })
end)

Harness.test("formatting is ASCII and never emits interval states", function()
    local line = Formatting.comparison_line({
        local_side = Fixtures.side(2, "STOCK", 50, "current", false),
        enemy_side = Fixtures.side(3, "STOCK", 50, "current", false),
        comparison = { status = "EQL", charge_difference = -0.01, time_difference = -0.01 },
    })
    Harness.equal(line, "EQL | 0% | 0s")
    Harness.falsy(string.find(line, "UNCERTAIN", 1, true))
    Harness.falsy(string.find(line, "[", 1, true))
    for i = 1, #line do
        Harness.truthy(string.byte(line, i) >= 32 and string.byte(line, i) <= 126)
    end
end)
