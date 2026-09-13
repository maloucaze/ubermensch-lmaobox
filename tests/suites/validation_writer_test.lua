local Fakes = require("support.fakes")
local Harness = require("support.harness")
local Json = require("validation.json")
local Writer = require("validation.writer")

Harness.test("validation JSON is deterministic and escapes control text", function()
    local encoded = Json.encode({
        z = 2,
        a = "line\nquote\"",
        values = { 1, true },
    })
    Harness.equal(
        encoded,
        '{"a":"line\\nquote\\\"","values":[1,true],"z":2}'
    )
end)

Harness.test("writer retries a relative TF2 directory and avoids collisions", function()
    local host, memory = Fakes.validation_host()
    host.filesystem.CreateDirectory = function()
        return false
    end

    local first = Writer.new(host, host.state.now, {
        max_file_bytes = 700,
        max_buffer_bytes = 800,
    })
    first:append("first", {}, host.state.now)
    first:flush(host.state.now)
    first:close()

    local second = Writer.new(host, host.state.now, {
        max_file_bytes = 700,
        max_buffer_bytes = 800,
    })
    Harness.truthy(not second.disabled)
    Harness.truthy(first.path ~= second.path)
    Harness.contains(first.path, "ubermensch-validation\\")
    Harness.contains(second.path, "_001_part01.jsonl")
    second:close()
    Harness.truthy(#memory.opens >= 4)
end)

Harness.test("writer parts rotate and buffered memory remains bounded", function()
    local host, memory = Fakes.validation_host()
    local writer = Writer.new(host, host.state.now, {
        max_file_bytes = 300,
        max_buffer_bytes = 800,
    })
    for index = 1, 20 do
        writer:append("synthetic", {
            index = index,
            payload = string.rep("x", 100),
        }, host.state.now)
    end
    Harness.truthy(writer.dropped_records > 0)
    writer:flush(host.state.now)
    writer:close()
    Harness.truthy(#writer.paths >= 2)
    Harness.truthy(#memory.opens >= 2)
end)
