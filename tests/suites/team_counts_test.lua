local Harness = require("support.harness")
local Constants = require("ubermensch.constants")
local TeamCounts = require("ubermensch.team_counts")

Harness.test("team counts resolve in local-team-first order", function()
    local counts = {
        [Constants.TEAM.RED] = 5,
        [Constants.TEAM.BLU] = 11,
    }
    local red = TeamCounts.resolve(counts, Constants.TEAM.RED, true)
    Harness.truthy(red.available)
    Harness.equal(red.local_count, 5)
    Harness.equal(red.enemy_count, 11)

    local blue = TeamCounts.resolve(counts, Constants.TEAM.BLU, true)
    Harness.truthy(blue.available)
    Harness.equal(blue.local_count, 11)
    Harness.equal(blue.enemy_count, 5)
end)

Harness.test("team counts accept every nonnegative integer pair", function()
    for local_count = 0, 12 do
        for enemy_count = 0, 12 do
            local result = TeamCounts.resolve({
                [Constants.TEAM.RED] = local_count,
                [Constants.TEAM.BLU] = enemy_count,
            }, Constants.TEAM.RED, true)
            Harness.truthy(result.available)
            Harness.equal(result.local_count, local_count)
            Harness.equal(result.enemy_count, enemy_count)
        end
    end
end)

Harness.test("team counts reject malformed values", function()
    local invalid = { -1, 1.5, 0 / 0, math.huge, "1", false }
    for i = 1, #invalid do
        local result = TeamCounts.resolve({ [2] = invalid[i], [3] = 1 }, 2, true)
        Harness.falsy(result.available)
        result = TeamCounts.resolve({ [2] = 1, [3] = invalid[i] }, 2, true)
        Harness.falsy(result.available)
    end
end)

Harness.test("team counts are unavailable without roster authority", function()
    local result = TeamCounts.resolve({ [2] = 5, [3] = 11 }, 2, false)
    Harness.falsy(result.available)
    result = TeamCounts.resolve(nil, 2, true)
    Harness.falsy(result.available)
    result = TeamCounts.resolve({ [2] = 5, [3] = 11 }, 1, true)
    Harness.falsy(result.available)
end)

