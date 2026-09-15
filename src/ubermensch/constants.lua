--- Fixed domain, runtime, and presentation values for Ubermensch.
-- @module ubermensch.constants

local Constants = {}

Constants.VERSION = "2.2.1"
Constants.PREFIX = "[Ubermensch]"

Constants.TEAM = {
    RED = 2,
    BLU = 3,
}
Constants.TEAM_NAME = {
    [2] = "RED",
    [3] = "BLU",
}
Constants.ENEMY_TEAM = {
    [2] = 3,
    [3] = 2,
}
Constants.MEDIC_CLASS = 5

Constants.ITEM_FAMILY = {
    [29] = "STOCK",
    [211] = "STOCK",
    [663] = "STOCK",
    [796] = "STOCK",
    [805] = "STOCK",
    [885] = "STOCK",
    [894] = "STOCK",
    [903] = "STOCK",
    [912] = "STOCK",
    [961] = "STOCK",
    [970] = "STOCK",
    [35] = "KRITZ",
    [15008] = "STOCK",
    [15010] = "STOCK",
    [15025] = "STOCK",
    [15039] = "STOCK",
    [15050] = "STOCK",
    [15078] = "STOCK",
    [15097] = "STOCK",
    [15120] = "STOCK",
    [15121] = "STOCK",
    [15122] = "STOCK",
    [15145] = "STOCK",
    [15146] = "STOCK",
}
Constants.KNOWN_UNSUPPORTED = {
    [411] = "QUICK-FIX",
    [998] = "VACCINATOR",
}

Constants.CHARGE_RATE = {
    STOCK = 2.5,
    KRITZ = 3.125,
}
Constants.SETUP_MULTIPLIER = 3
Constants.DEPLOY_DRAIN_RATE = 12.5
Constants.ADVANTAGE_SECONDS = 10
Constants.ACTIVE_TIE_PERCENT = 0.1
Constants.READY_TIE_SECONDS = 0.05

Constants.FRAME_NET_UPDATE_END = 4
Constants.FRAME_RENDER_START = 5
Constants.SECONDARY_SLOT = 1
Constants.MOUSE_LEFT = 107
Constants.MAX_PLAYERS = 32
Constants.EVENT_QUEUE_LIMIT = 64
Constants.PHASE_HISTORY_LIMIT = 64
Constants.STARTUP_DIAGNOSTIC_LIMIT = 8

Constants.VISIBLE_ROUND_STATE = {
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
}
Constants.SETUP_ROUND_STATE = {
    [1] = true,
    [2] = true,
    [3] = true,
}

Constants.EVENTS = {
    player_spawn = true,
    player_death = true,
    player_changeclass = true,
    player_team = true,
    post_inventory_application = true,
    player_chargedeployed = true,
}

Constants.COLORS = {
    background = { 15, 15, 18, 170 },
    text = { 255, 255, 255, 255 },
    advantage = { 80, 220, 120, 255 },
    disadvantage = { 235, 80, 80, 255 },
    ready = { 255, 235, 60, 255 },
    red_deployed = { 255, 80, 80, 255 },
    blu_deployed = { 80, 160, 255, 255 },
    warning = { 170, 140, 0, 255 },
    unavailable = { 170, 170, 170, 255 },
}

-- Team-count presentation remains independent from Uber status colors.
Constants.TEAM_COUNT_COLORS = {
    text = { 255, 255, 255, 255 },
    separator = { 170, 170, 170, 255 },
}

Constants.FONT = {
    name = "Lucida Console",
    size = 14,
    weight = 600,
    flags = 0x010,
}
Constants.LAYOUT = {
    horizontal_padding = 6,
    vertical_padding = 4,
    line_gap = 1,
    separator_gap = 3,
    separator_thickness = 1,
    default_x = 0.02,
    default_y = 0.35,
}

Constants.CALLBACK = {
    frame = "ubermensch.frame",
    event = "ubermensch.event",
    draw = "ubermensch.draw",
    unload = "ubermensch.unload",
}

Constants.POSITION_FILENAME = "ubermensch_position_v1.txt"
Constants.POSITION_DIRECTORY = "ubermensch-lmaobox"
Constants.POSITION_HEADER = "UBERMENSCH_POSITION_V1"

return Constants
