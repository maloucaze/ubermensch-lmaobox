local Harness = require("support.harness")
local Comparison = require("ubermensch.comparison")
local Numbers = require("ubermensch.numbers")

local vectors = {
    { "STOCK", 50, "STOCK", 40, 20, 24, 4, 10, "EQL" },
    { "STOCK", 80, "STOCK", 50, 8, 20, 12, 30, "ADV" },
    { "STOCK", 50, "STOCK", 80, 20, 8, -12, -30, "DIS" },
    { "KRITZ", 50, "KRITZ", 40, 16, 19.2, 3.2, 10, "EQL" },
    { "KRITZ", 100, "KRITZ", 100, 0, 0, 0, 0, "EQL" },
    { "STOCK", 90, "KRITZ", 65, 4, 11.2, 7.2, 25, "EQL" },
    { "STOCK", 100, "KRITZ", 65, 0, 11.2, 11.2, 35, "ADV" },
    { "STOCK", 50, "KRITZ", 90, 20, 3.2, -16.8, -40, "DIS" },
}

for i = 1, #vectors do
    local vector = vectors[i]
    Harness.test("calculation vector " .. i, function()
        local result = Comparison.both(
            { family = vector[1], charge = vector[2] },
            { family = vector[3], charge = vector[4] }
        )
        Harness.near(Comparison.time_to_ready(vector[1], vector[2]), vector[5], 1e-9)
        Harness.near(Comparison.time_to_ready(vector[3], vector[4]), vector[6], 1e-9)
        Harness.near(result.time_difference, vector[7], 1e-9)
        Harness.near(result.charge_difference, vector[8], 1e-9)
        Harness.equal(result.status, vector[9])
    end)
end

Harness.test("classification boundaries are inclusive", function()
    Harness.equal(Comparison.classify(-10), "EQL")
    Harness.equal(Comparison.classify(10), "EQL")
    Harness.equal(Comparison.classify(-10.000001), "DIS")
    Harness.equal(Comparison.classify(10.000001), "ADV")
end)

Harness.test("reciprocal cross-family comparison", function()
    local forward = Comparison.both(
        { family = "STOCK", charge = 60 },
        { family = "KRITZ", charge = 50 }
    )
    local reverse = Comparison.both(
        { family = "KRITZ", charge = 50 },
        { family = "STOCK", charge = 60 }
    )
    Harness.near(forward.time_difference, -reverse.time_difference, 1e-9)
    Harness.near(forward.charge_difference, -reverse.charge_difference, 1e-9)
end)

Harness.test("charge endpoints and malformed inputs", function()
    Harness.near(Comparison.time_to_ready("STOCK", 0), 40, 1e-9)
    Harness.near(Comparison.time_to_ready("KRITZ", 100), 0, 1e-9)
    Harness.is_nil(Comparison.time_to_ready("STOCK", -1))
    Harness.is_nil(Comparison.time_to_ready("STOCK", 101))
    Harness.is_nil(Comparison.time_to_ready("QUICK-FIX", 50))
    Harness.is_nil(Comparison.classify(0 / 0))
end)

Harness.test("numeric validation and deterministic rounding", function()
    Harness.equal(Numbers.round_half_away(2.5), 3)
    Harness.equal(Numbers.round_half_away(-2.5), -3)
    Harness.equal(Numbers.round_half_away(-0.01), 0)
    Harness.equal(Numbers.round_half_away(1.25, 1), 1.3)
    Harness.equal(Numbers.round_half_away(-1.25, 1), -1.3)
    Harness.equal(Numbers.resource_percent(0), 0)
    Harness.equal(Numbers.resource_percent(100), 100)
    Harness.is_nil(Numbers.resource_percent(73.5))
    Harness.is_nil(Numbers.percent(math.huge))
end)
