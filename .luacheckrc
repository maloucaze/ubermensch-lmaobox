stds.lua_compatibility = {
    read_globals = {
        unpack = {},
        table = {
            fields = {
                "unpack",
            },
        },
    },
}
std = "min+lua_compatibility"

-- Long contract descriptions are deliberate in LDoc blocks. Luacheck remains
-- focused on semantic defects such as accidental globals and unused values.
max_line_length = false

-- Fake methods retain their production-shaped colon signatures even when a
-- particular fake does not need its receiver.
files["tests/**/*.lua"] = {
    ignore = {
        "212",
    },
}
