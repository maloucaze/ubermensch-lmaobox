local Harness = require("support.harness")
local Estimation = require("ubermensch.estimation")

local function estimate(family, charge, deployed, elapsed, multiplier)
    return Estimation.from_anchor(
        { charge = charge, time = 0, deployed = deployed },
        family,
        elapsed,
        { { time = 0, multiplier = multiplier or 1 } }
    )
end

local vectors = {
    { "STOCK", 50, false, 4, 1, 60, false },
    { "KRITZ", 50, false, 4, 1, 62.5, false },
    { "STOCK", 50, false, 2, 3, 65, false },
    { "STOCK", 99, false, 2, 1, 100, false },
    { "STOCK", 100, true, 2, 1, 75, true },
    { "KRITZ", 60, true, 4.8, 1, 0, false },
    { "STOCK", 100, true, 10, 1, 5, false },
    { "KRITZ", 100, true, 10, 1, 6.25, false },
    { "QF", 50, false, 4, 1, 61, false },
    { "QF", 100, true, 10, 1, 5.5, false },
}

for i = 1, #vectors do
    local vector = vectors[i]
    Harness.test("estimation vector " .. i, function()
        local charge, active = estimate(
            vector[1], vector[2], vector[3], vector[4], vector[5]
        )
        Harness.near(charge, vector[6], 1e-9)
        Harness.equal(active, vector[7])
    end)
end

Harness.test("phase transitions integrate as segments", function()
    local charge = Estimation.from_anchor(
        { charge = 0, time = 0, deployed = false },
        "STOCK",
        4,
        {
            { time = 0, multiplier = 3 },
            { time = 2, multiplier = 1 },
        }
    )
    Harness.near(charge, 20, 1e-9)
end)

Harness.test("deployment rebuilding integrates phase after drain", function()
    local charge, active = Estimation.from_anchor(
        { charge = 25, time = 0, deployed = true },
        "STOCK",
        4,
        {
            { time = 0, multiplier = 1 },
            { time = 3, multiplier = 3 },
        }
    )
    Harness.near(charge, 10, 1e-9)
    Harness.falsy(active)
end)

Harness.test("estimates clamp and remain ready", function()
    local charge1 = estimate("STOCK", 100, false, 100, 3)
    local charge2 = estimate("KRITZ", 100, false, 1000, 1)
    Harness.equal(charge1, 100)
    Harness.equal(charge2, 100)
end)

Harness.test("invalid anchors and elapsed time fail closed", function()
    local charge = Estimation.from_anchor(
        { charge = 50, time = 2, deployed = false },
        "STOCK",
        1,
        {}
    )
    Harness.is_nil(charge)
    charge = Estimation.from_anchor(
        { charge = 0 / 0, time = 0, deployed = false },
        "STOCK",
        1,
        {}
    )
    Harness.is_nil(charge)
end)

Harness.test("display-only and unknown families are never estimated", function()
    Harness.is_nil(estimate("VACC", 50, false, 4, 1))
    Harness.is_nil(estimate("UNKNOWN", 50, false, 4, 1))
end)

Harness.test("repeated queries use the immutable original anchor", function()
    local anchor = { charge = 50, time = 0, deployed = false }
    local first = Estimation.from_anchor(anchor, "STOCK", 2, { { time = 0, multiplier = 1 } })
    local second = Estimation.from_anchor(anchor, "STOCK", 4, { { time = 0, multiplier = 1 } })
    Harness.equal(first, 55)
    Harness.equal(second, 60)
    Harness.equal(anchor.charge, 50)
    Harness.equal(anchor.time, 0)
end)
