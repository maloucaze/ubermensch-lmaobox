--- Fixed match-validation recorder limits and event knowledge.
-- @module validation.constants

local Constants = {}

Constants.FORMAT_VERSION = 1
Constants.RECORDER_VERSION = "1.3.0"
Constants.PREFIX = "[Ubermensch Validation]"
Constants.DIRECTORY = "ubermensch-validation"
Constants.FILE_PREFIX = "ubermensch_validation"
Constants.FLUSH_INTERVAL = 5
Constants.HEARTBEAT_INTERVAL = 5
Constants.CHECKPOINT_INTERVAL = 30
Constants.DETAIL_INTERVAL = 0.1
Constants.MAX_BUFFER_BYTES = 512 * 1024
Constants.MAX_FILE_BYTES = 64 * 1024 * 1024
Constants.CHARGE_LOG_STEP = 0.5
Constants.KEY_F8 = 99

Constants.MATCH_EVENTS = {
    game_newmap = true,
    player_activate = true,
    player_connect = true,
    player_connect_client = true,
    player_disconnect = true,
    server_spawn = true,
    teamplay_game_over = true,
    teamplay_restart_round = true,
    teamplay_round_active = true,
    teamplay_round_stalemate = true,
    teamplay_round_start = true,
    teamplay_round_win = true,
    teamplay_setup_finished = true,
    tf_game_over = true,
}

return Constants
