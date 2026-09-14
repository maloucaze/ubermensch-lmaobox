local Harness = require("support.harness")
local Adapter = require("ubermensch.adapter")
local Constants = require("ubermensch.constants")
local Controller = require("ubermensch.controller")
local Fakes = require("support.fakes")
local Position = require("ubermensch.position")
local Renderer = require("ubermensch.renderer")

local function setup()
    local ally_weapon_options = {
        index = 102, item = 29, nonlocal_charge = 0.75,
        deployed = false, holstered = true,
    }
    local enemy_weapon_options = {
        index = 103, item = 35, nonlocal_charge = 0.5,
        deployed = false, holstered = false,
    }
    local local_player = Fakes.player({ index = 1, team = 2, class = 1, alive = true })
    local ally = Fakes.player({
        index = 2, team = 2, class = 5, alive = true,
        loadout_weapon = Fakes.weapon(ally_weapon_options),
    })
    local enemy = Fakes.player({
        index = 3, team = 3, class = 5, alive = true,
        loadout_weapon = Fakes.weapon(enemy_weapon_options),
        active_weapon = nil,
    })
    ally_weapon_options.owner = ally
    enemy_weapon_options.owner = enemy
    local host = Fakes.host({
        players = { local_player, ally, enemy },
        local_player = local_player,
        userids = { [1] = 10, [2] = 20, [3] = 30 },
        resource = Fakes.resource({
            [1] = { connected = true, valid = true, alive = true, team = 2, userid = 10, class = 1, charge = 0 },
            [2] = { connected = true, valid = true, alive = true, team = 2, userid = 20, class = 5, charge = 75 },
            [3] = { connected = true, valid = true, alive = true, team = 3, userid = 30, class = 5, charge = 50 },
        }),
    })
    local saves = 0
    local persistence = {
        save = function(_, position)
            if position.dirty then saves = saves + 1 end
            position.dirty = false
            return true
        end,
    }
    local renderer = assert(Renderer.new(host))
    local controller = Controller.new({
        adapter = Adapter.new(host),
        renderer = renderer,
        persistence = persistence,
        position = Position.new(),
    })
    return controller, host, ally_weapon_options, enemy_weapon_options,
        function() return saves end
end

local function count_calls(calls, kind)
    local count = 0
    for i = 1, #calls do
        if calls[i][1] == kind then count = count + 1 end
    end
    return count
end

Harness.test("preferred network-update-end capture reaches the next Draw", function()
    local controller, host = setup()
    Harness.falsy(controller:on_frame_stage(3))
    Harness.is_nil(controller.latest_prepared)
    Harness.truthy(controller:on_frame_stage(Constants.FRAME_NET_UPDATE_END))
    Harness.equal(controller.latest_prepared.lines[1], "RED 75% (STOCK)")
    Harness.equal(controller.latest_prepared.lines[2], "BLU 50% (KRITZ)")
    local acquisition = host.state.acquisition_calls
    local rendered, blocker = controller:on_draw()
    Harness.truthy(rendered)
    Harness.is_nil(blocker)
    Harness.equal(host.state.acquisition_calls, acquisition)
    Harness.equal(count_calls(host.state.draw_calls, "rect"), 1)
    Harness.equal(count_calls(host.state.draw_calls, "text"), 3)
end)

Harness.test("render-start captures only when network-update end was absent", function()
    local controller = setup()
    local captured, source = controller:on_frame_stage(
        Constants.FRAME_RENDER_START
    )
    Harness.truthy(captured)
    Harness.equal(source, "fallback")
    Harness.truthy(controller.latest_snapshot ~= nil)

    local generation = controller.tracker.generation
    captured, source = controller:on_frame_stage(
        Constants.FRAME_NET_UPDATE_END
    )
    Harness.truthy(captured)
    Harness.equal(source, "preferred")
    Harness.equal(controller.tracker.generation, generation + 1)

    generation = controller.tracker.generation
    captured, source = controller:on_frame_stage(
        Constants.FRAME_RENDER_START
    )
    Harness.falsy(captured)
    Harness.is_nil(source)
    Harness.equal(controller.tracker.generation, generation)

    captured, source = controller:on_frame_stage(
        Constants.FRAME_RENDER_START
    )
    Harness.truthy(captured)
    Harness.equal(source, "fallback")
    Harness.equal(controller.tracker.generation, generation + 1)
end)

Harness.test("live frame-stage value overrides the documented fallback", function()
    local controller = setup()
    controller.frame_net_update_end = 14
    controller.frame_render_start = 15
    Harness.falsy(controller:on_frame_stage(4))
    Harness.is_nil(controller.latest_snapshot)
    Harness.truthy(controller:on_frame_stage(14))
    Harness.truthy(controller.latest_snapshot ~= nil)
end)

Harness.test("numeric-like native frame stages are normalized at the boundary", function()
    local controller = setup()
    Harness.truthy(controller:on_frame_stage("4"))
    Harness.truthy(controller.latest_snapshot ~= nil)

    local second = setup()
    local proxy = setmetatable({}, {
        __tostring = function() return "4" end,
    })
    Harness.truthy(second:on_frame_stage(proxy))
    Harness.truthy(second.latest_snapshot ~= nil)
end)

Harness.test("Draw reports each nonthrowing startup blocker", function()
    local controller, host = setup()
    local rendered, blocker = controller:on_draw()
    Harness.falsy(rendered)
    Harness.equal(blocker, "network snapshot unavailable")

    controller:on_frame_stage(4)
    host.state.console = true
    rendered, blocker = controller:on_draw()
    Harness.falsy(rendered)
    Harness.equal(blocker, "Source console visible")

    host.state.console = false
    controller.latest_prepared = nil
    rendered, blocker = controller:on_draw()
    Harness.falsy(rendered)
    Harness.equal(blocker, "local team unavailable")

    controller:on_frame_stage(4)
    host.draw.GetScreenSize = function() return nil end
    rendered, blocker = controller:on_draw()
    Harness.falsy(rendered)
    Harness.equal(blocker, "screen size unavailable")
end)

Harness.test("mandatory draw failures reach the guarded callback boundary", function()
    local controller, host = setup()
    controller:on_frame_stage(4)
    host.draw.Text = function() error("paint failed") end
    local ok, failure = pcall(function()
        controller:on_draw()
    end)
    Harness.falsy(ok)
    Harness.contains(tostring(failure), "draw.Text failed:")
end)

Harness.test("fractional measurements never cross the native draw boundary", function()
    local controller, host = setup()
    host.draw.GetTextSize = function(text)
        return #text * 7 + 0.4, 13.6
    end
    controller:on_frame_stage(4)
    local rendered = controller:on_draw()
    Harness.truthy(rendered)
    for i = 1, #host.state.draw_calls do
        local call = host.state.draw_calls[i]
        if call[1] == "rect" or call[1] == "text" then
            for argument = 2, #call do
                local value = call[argument]
                if type(value) == "number" then
                    Harness.equal(value, math.floor(value))
                end
            end
        end
    end
end)

Harness.test("new current charge appears on the immediately following Draw model", function()
    local controller, _, _, enemy = setup()
    controller:on_frame_stage(4)
    Harness.equal(controller.latest_prepared.lines[2], "BLU 50% (KRITZ)")
    enemy.nonlocal_charge = 0.91
    controller:on_frame_stage(4)
    Harness.equal(controller.latest_prepared.lines[2], "BLU 91% (KRITZ)")
end)

Harness.test("omitted local Medic reaches the next Draw through GetLocalPlayer", function()
    local weapon_options = {
        index = 101,
        item = 35,
        local_charge = 0.42,
        deployed = false,
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
        resource = Fakes.resource({
            [1] = {
                connected = true,
                valid = true,
                alive = true,
                team = 2,
                userid = 10,
                class = 5,
                charge = 42,
            },
        }),
    })
    local controller = Controller.new({
        adapter = Adapter.new(host),
        renderer = assert(Renderer.new(host)),
        persistence = { save = function() return true end },
        position = Position.new(),
    })

    Harness.truthy(controller:on_frame_stage(Constants.FRAME_NET_UPDATE_END))
    Harness.equal(controller.latest_prepared.lines[1], "RED 42% (KRITZ)")
    local acquisition_calls = host.state.acquisition_calls
    Harness.truthy(controller:on_draw())
    Harness.equal(host.state.acquisition_calls, acquisition_calls)
    Harness.equal(count_calls(host.state.draw_calls, "text"), 3)
end)

Harness.test("partial current loss estimates only missing fields and warns", function()
    local controller, host, ally, enemy = setup()
    controller:on_frame_stage(4)
    host.state.now = 12
    enemy.charge_error = true
    host.state.resource = Fakes.resource({
        [1] = { connected = true, valid = true, alive = true, team = 2, userid = 10, class = 1, charge = 0 },
        [2] = { connected = true, valid = true, alive = true, team = 2, userid = 20, class = 5, charge = 75 },
        [3] = { connected = true, valid = true, alive = true, team = 3, userid = 30, class = 5, charge = 50.5 },
    })
    ally.nonlocal_charge = 0.80
    controller:on_frame_stage(4)
    Harness.equal(controller.latest_prepared.lines[1], "RED 80% (STOCK)")
    Harness.equal(controller.latest_prepared.lines[2], "BLU ~56% (KRITZ)")
    Harness.truthy(controller.latest_prepared.warning)
end)

Harness.test("current charge keeps updating when family and deployment reads fail", function()
    local controller, _, _, enemy = setup()
    controller:on_frame_stage(4)
    enemy.family_error = true
    enemy.deployment_error = true
    enemy.nonlocal_charge = 0.66
    controller:on_frame_stage(4)
    Harness.equal(controller.latest_prepared.lines[2], "BLU 66% (KRITZ)")
    Harness.truthy(controller.latest_prepared.warning)
end)

Harness.test("current deployment change reaches the next prepared Draw state", function()
    local controller, _, _, enemy = setup()
    controller:on_frame_stage(4)
    enemy.deployed = true
    controller:on_frame_stage(4)
    Harness.equal(
        controller.latest_prepared.colors[2],
        Constants.COLORS.blu_deployed
    )
end)

Harness.test("dormant resource data warns and full reacquisition clears warning", function()
    local controller, host, _, enemy = setup()
    controller:on_frame_stage(4)
    host.state.players[3].options.dormant = true
    controller:on_frame_stage(4)
    Harness.truthy(controller.latest_prepared.warning)
    Harness.equal(controller.latest_prepared.lines[2], "BLU ~50% (KRITZ)")
    host.state.players[3].options.dormant = false
    enemy.nonlocal_charge = 0.55
    controller:on_frame_stage(4)
    Harness.falsy(controller.latest_prepared.warning)
    Harness.equal(controller.latest_prepared.lines[2], "BLU 55% (KRITZ)")
end)

Harness.test("warning frame adds four rectangles and no text", function()
    local controller, host = setup()
    controller:on_frame_stage(4)
    controller.latest_prepared.warning = true
    controller:on_draw()
    Harness.equal(count_calls(host.state.draw_calls, "rect"), 5)
    Harness.equal(count_calls(host.state.draw_calls, "text"), 3)
end)

Harness.test("repeated Draw reuses one font and fixed per-frame resources", function()
    local controller, host = setup()
    controller:on_frame_stage(4)
    controller:on_draw()
    controller:on_draw()
    controller:on_draw()
    Harness.equal(host.state.font_creations, 1)
    Harness.equal(count_calls(host.state.draw_calls, "rect"), 3)
    Harness.equal(count_calls(host.state.draw_calls, "text"), 9)
    Harness.equal(host.state.font_arguments[1], "Verdana")
    Harness.equal(host.state.font_arguments[2], 13)
    Harness.equal(host.state.font_arguments[3], 400)
    Harness.equal(host.state.font_arguments[4], 0x010)
end)

Harness.test("event callback queues without reconciling", function()
    local controller = setup()
    controller:on_frame_stage(4)
    local generation = controller.tracker.generation
    controller:on_event(Fakes.event("player_chargedeployed", { userid = 30 }))
    Harness.equal(controller.tracker.generation, generation)
    Harness.equal(#controller.tracker.events, 1)
end)

Harness.test("drag saves only on completion and unload is idempotent", function()
    local controller, host, _, _, saves = setup()
    controller:on_frame_stage(4)
    controller:on_draw()
    host.state.menu_open = true
    host.state.mouse = { x = 45, y = 385 }
    host.state.pressed = true
    host.state.down = true
    controller:on_draw()
    Harness.equal(saves(), 0)
    host.state.pressed = false
    host.state.mouse = { x = 200, y = 200 }
    controller:on_draw()
    Harness.equal(saves(), 0)
    host.state.down = false
    host.state.released = true
    controller:on_draw()
    Harness.equal(saves(), 1)
    controller.position.dirty = true
    controller:on_unload()
    controller:on_unload()
    Harness.equal(saves(), 2)
    local generation = controller.tracker.generation
    controller:on_frame_stage(4)
    Harness.equal(controller.tracker.generation, generation)
end)

Harness.test("visibility hides without discarding latest values", function()
    local controller, host = setup()
    controller:on_frame_stage(4)
    host.state.console = true
    controller:on_draw()
    Harness.equal(count_calls(host.state.draw_calls, "text"), 0)
    host.state.console = false
    controller:on_draw()
    Harness.equal(count_calls(host.state.draw_calls, "text"), 3)
end)
