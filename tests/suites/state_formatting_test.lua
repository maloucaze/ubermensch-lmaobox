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
        warning = false,
    }
    local prepared = Formatting.prepare(model)
    Harness.same_table(prepared.lines, {
        "RED 75% (KRITZ)",
        "BLU 50% (STOCK)",
        "ADV | +25% | +12.0s",
    })
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
    Harness.equal(prepared.lines[1], "BLU 50% (STOCK)")
    Harness.equal(prepared.lines[2], "RED 75% (KRITZ)")
end)

Harness.test("missing side formatting omits time", function()
    local model = State.resolve(tracking({
        Fixtures.side(2, "STOCK", 75, "current", false),
    }), {})
    local prepared = Formatting.prepare(model)
    Harness.same_table(prepared.lines, {
        "RED 75% (STOCK)",
        "BLU 0% (NO MEDIC)",
        "ADV | +75%",
    })
    Harness.falsy(prepared.warning)
end)

Harness.test("approximate formatting and border", function()
    local local_side = Fixtures.side(2, "STOCK", 88, "estimate", false, "estimate")
    local enemy = Fixtures.side(3, "KRITZ", 73, "current", false)
    local prepared = Formatting.prepare({
        local_side = local_side,
        enemy_side = enemy,
        comparison = { status = "EQUAL", charge_difference = 15, time_difference = 3.75 },
        warning = true,
    })
    Harness.same_table(prepared.lines, {
        "RED ~88% (STOCK)",
        "BLU 73% (KRITZ)",
        "EQUAL | ~+15% | ~+3.8s",
    })
    Harness.truthy(prepared.warning)
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
    Harness.equal(prepared.lines[3], "ADV | ~+30% | ~+12.0s")
end)

Harness.test("genuinely unknown fields produce dash", function()
    local model = State.resolve(tracking({
        Fixtures.side(2, nil, nil, "unknown", false, "unknown"),
        Fixtures.side(3, nil, nil, "unknown", false, "unknown"),
    }), {})
    local prepared = Formatting.prepare(model)
    Harness.same_table(prepared.lines, {
        "RED ?% (UNKNOWN)",
        "BLU ?% (UNKNOWN)",
        "-",
    })
    Harness.truthy(prepared.warning)
end)

Harness.test("two confirmed missing sides compare equal", function()
    local prepared = Formatting.prepare(State.resolve(tracking({}), {}))
    Harness.equal(prepared.lines[3], "EQUAL | 0%")
    Harness.falsy(prepared.warning)
end)

Harness.test("self Medic ignores other allied candidates", function()
    local local_medic = Fixtures.side(2, "STOCK", 20, "current", false)
    local_medic.is_local = true
    local other = Fixtures.side(2, "STOCK", 100, "current", false)
    local enemy = Fixtures.side(3, "STOCK", 50, "current", false)
    local model = State.resolve(tracking({ local_medic, other, enemy }, {
        local_class = 5,
        local_alive = true,
    }), {})
    Harness.equal(model.local_side.charge, 20)
    Harness.truthy(model.self_mode)
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
    Harness.equal(Formatting.comparison_line(model), "ADV | 0%")
end)

Harness.test("last local team preserves ordering during identity loss", function()
    local lost = tracking({}, {
        last_local_team = 3,
        roster_available = false,
    })
    lost.local_team = nil
    local model = State.resolve(lost, {})
    local prepared = Formatting.prepare(model)
    Harness.equal(prepared.lines[1], "BLU ?% (UNKNOWN)")
    Harness.equal(prepared.lines[2], "RED ?% (UNKNOWN)")
    Harness.equal(prepared.lines[3], "-")
end)

Harness.test("failed roster never proves no Medic", function()
    local model = State.resolve(tracking({}, { roster_available = false }), {})
    Harness.equal(Formatting.side_line(model.local_side), "RED ?% (UNKNOWN)")
    Harness.equal(Formatting.comparison_line(model), "-")
    Harness.truthy(model.warning)
end)

Harness.test("colors obey deployment readiness and status precedence", function()
    Harness.same_table(Formatting.side_color(Fixtures.side(2, "STOCK", 100, "current", false)), Constants.COLORS.ready)
    Harness.same_table(Formatting.side_color(Fixtures.side(2, "STOCK", 100, "estimate", true)), Constants.COLORS.red_deployed)
    Harness.same_table(Formatting.side_color(Fixtures.side(3, "STOCK", 100, "current", true)), Constants.COLORS.blu_deployed)
    Harness.same_table(Formatting.side_color(Fixtures.side(3, "STOCK", 100, "estimate", false)), Constants.COLORS.ready)
    Harness.same_table(Formatting.comparison_color({ status = "ADV" }), Constants.COLORS.advantage)
    Harness.same_table(Formatting.comparison_color({ status = "DIS" }), Constants.COLORS.disadvantage)
    Harness.same_table(Formatting.comparison_color({ status = "EQUAL" }), Constants.COLORS.text)
    Harness.same_table(Formatting.comparison_color(nil), Constants.COLORS.text)
end)

Harness.test("all fixed RGBA values match the specification", function()
    Harness.same_table(Constants.COLORS.advantage, { 80, 220, 120, 255 })
    Harness.same_table(Constants.COLORS.disadvantage, { 235, 80, 80, 255 })
    Harness.same_table(Constants.COLORS.text, { 255, 255, 255, 255 })
    Harness.same_table(Constants.COLORS.ready, { 255, 235, 60, 255 })
    Harness.same_table(Constants.COLORS.red_deployed, { 255, 80, 80, 255 })
    Harness.same_table(Constants.COLORS.blu_deployed, { 80, 160, 255, 255 })
    Harness.same_table(Constants.COLORS.warning, { 170, 140, 0, 255 })
    Harness.same_table(Constants.COLORS.background, { 15, 15, 18, 170 })
end)

Harness.test("formatting is ASCII and never emits interval states", function()
    local line = Formatting.comparison_line({
        local_side = Fixtures.side(2, "STOCK", 50, "current", false),
        enemy_side = Fixtures.side(3, "STOCK", 50, "current", false),
        comparison = { status = "EQUAL", charge_difference = -0.01, time_difference = -0.01 },
    })
    Harness.equal(line, "EQUAL | 0% | 0.0s")
    Harness.falsy(string.find(line, "UNCERTAIN", 1, true))
    Harness.falsy(string.find(line, "[", 1, true))
    for i = 1, #line do
        Harness.truthy(string.byte(line, i) >= 32 and string.byte(line, i) <= 126)
    end
end)
