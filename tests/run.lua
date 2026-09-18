package.path = table.concat({
    "src/?.lua",
    "src/?/init.lua",
    "tests/?.lua",
    "tests/?/init.lua",
    "tools/?.lua",
    "tools/?/init.lua",
    package.path,
}, ";")

local suites = {
    "calculations_test",
    "team_counts_test",
    "offclasses_test",
    "estimation_test",
    "weapon_test",
    "selection_test",
    "state_formatting_test",
    "tracking_test",
    "adapter_test",
    "position_persistence_test",
    "controller_test",
    "application_test",
    "validation_writer_test",
    "validation_recorder_test",
    "performance_bundle_test",
}

for i = 1, #suites do
    require("suites." .. suites[i])
end

require("support.harness").run()
