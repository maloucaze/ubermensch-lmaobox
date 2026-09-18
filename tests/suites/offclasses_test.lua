local Harness = require("support.harness")
local Constants = require("ubermensch.constants")
local Offclasses = require("ubermensch.offclasses")

local function tracking(overrides)
    local result = {
        roster_available = true,
        local_team = Constants.TEAM.RED,
        last_local_team = Constants.TEAM.RED,
        is_casual = false,
        is_competitive = true,
        is_tournament = false,
        is_highlander = false,
        configured_player_slots = 12,
        team_player_counts = {
            [Constants.TEAM.RED] = 6,
            [Constants.TEAM.BLU] = 6,
        },
        offclass_counts = {
            [Constants.TEAM.RED] = {
                [Constants.SNIPER_CLASS] = { total = 0, alive = 0 },
                [Constants.SPY_CLASS] = { total = 0, alive = 0 },
            },
            [Constants.TEAM.BLU] = {
                [Constants.SNIPER_CLASS] = { total = 0, alive = 0 },
                [Constants.SPY_CLASS] = { total = 0, alive = 0 },
            },
        },
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

Harness.test("configured slots identify only supported competitive formats", function()
    Harness.equal(Offclasses.format(tracking()), "6v6")
    Harness.equal(Offclasses.format(tracking({
        configured_player_slots = 8,
    })), "4v4")
    Harness.is_nil(Offclasses.format(tracking({
        configured_player_slots = 18,
    })))
end)

Harness.test("casual noncompetitive and explicit Highlander modes are hidden", function()
    Harness.is_nil(Offclasses.format(tracking({ is_casual = true })))
    Harness.is_nil(Offclasses.format(tracking({
        is_competitive = false,
        is_tournament = false,
    })))
    Harness.is_nil(Offclasses.format(tracking({ is_highlander = true })))
    Harness.is_nil(Offclasses.format(tracking({ roster_available = false })))
end)

Harness.test("malformed slot fallback uses complete team rosters conservatively", function()
    local absent = tracking({
        team_player_counts = { [2] = 5, [3] = 6 },
    })
    absent.configured_player_slots = nil
    Harness.equal(Offclasses.format(absent), "6v6")
    Harness.equal(Offclasses.format(tracking({
        configured_player_slots = -1,
        team_player_counts = { [2] = 5, [3] = 6 },
    })), "6v6")
    Harness.is_nil(Offclasses.format(tracking({
        configured_player_slots = 10,
        team_player_counts = { [2] = 5, [3] = 5 },
    })))
    Harness.equal(Offclasses.format(tracking({
        configured_player_slots = -1,
        team_player_counts = { [2] = 4, [3] = 3 },
    })), "4v4")
    Harness.equal(Offclasses.format(tracking({
        configured_player_slots = "12",
        team_player_counts = { [2] = 6, [3] = 6 },
    })), "6v6")
    Harness.is_nil(Offclasses.format(tracking({
        configured_player_slots = -1,
        team_player_counts = { [2] = 3, [3] = 3 },
    })))
    Harness.is_nil(Offclasses.format(tracking({
        configured_player_slots = -1,
        team_player_counts = { [2] = 9, [3] = 9 },
    })))
end)

Harness.test("supported configured slots do not require a full connected roster", function()
    Harness.equal(Offclasses.format(tracking({
        configured_player_slots = 12,
        team_player_counts = { [2] = 1, [3] = 1 },
    })), "6v6")
    Harness.equal(Offclasses.format(tracking({
        configured_player_slots = 8,
        team_player_counts = { [2] = 1, [3] = 1 },
    })), "4v4")
end)

Harness.test("enemy off-classes are ordered counted and life-aware", function()
    local input = tracking()
    input.offclass_counts[Constants.TEAM.BLU][Constants.SNIPER_CLASS] = {
        total = 2,
        alive = 1,
    }
    input.offclass_counts[Constants.TEAM.BLU][Constants.SPY_CLASS] = {
        total = 1,
        alive = 0,
    }
    local result = Offclasses.resolve(input)
    Harness.equal(result.format, "6v6")
    Harness.equal(#result.classes, 2)
    Harness.equal(result.classes[1].label, "SNIPER")
    Harness.equal(result.classes[1].count, 2)
    Harness.truthy(result.classes[1].alive)
    Harness.equal(result.classes[2].label, "SPY")
    Harness.equal(result.classes[2].count, 1)
    Harness.falsy(result.classes[2].alive)
end)

Harness.test("off-class detection follows the enemy of either local team", function()
    local input = tracking({
        local_team = Constants.TEAM.BLU,
        last_local_team = Constants.TEAM.BLU,
    })
    input.offclass_counts[Constants.TEAM.RED][Constants.SPY_CLASS] = {
        total = 1,
        alive = 1,
    }
    local result = Offclasses.resolve(input)
    Harness.equal(#result.classes, 1)
    Harness.equal(result.classes[1].label, "SPY")
    Harness.truthy(result.classes[1].alive)
end)

Harness.test("no definite detected off-class produces no display model", function()
    Harness.is_nil(Offclasses.resolve(tracking()))
    Harness.is_nil(Offclasses.resolve(tracking({ roster_available = false })))
end)
