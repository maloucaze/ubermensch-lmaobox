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

Harness.test("writer rotation preserves physical sequence and byte limits", function()
    local host, memory = Fakes.validation_host()
    local writer = Writer.new(host, host.state.now, {
        max_file_bytes = 450,
        max_buffer_bytes = 20000,
    })
    for index = 1, 20 do
        Harness.truthy(writer:append("synthetic", {
            index = index,
            payload = string.rep("x", 100),
        }, host.state.now))
    end
    Harness.equal(writer.dropped_records, 0)
    writer:flush(host.state.now)
    writer:close()
    Harness.truthy(#writer.paths >= 2)

    local expected_sequence = 1
    local previous_sequence = nil
    for part = 1, #writer.paths do
        local content = memory.files[writer.paths[part]]
        Harness.truthy(#content <= 450)
        if part > 1 then
            local first_line = string.match(content, "([^\n]+)")
            Harness.contains(
                first_line,
                '"previous_record_sequence":' .. tostring(previous_sequence)
            )
            Harness.contains(first_line, '"type":"segment_start"')
        end
        for sequence in string.gmatch(content, '"seq":(%d+)') do
            sequence = tonumber(sequence)
            Harness.equal(sequence, expected_sequence)
            expected_sequence = expected_sequence + 1
            previous_sequence = sequence
        end
    end
    Harness.truthy(expected_sequence > 21)

    local writable_opens = 0
    for index = 1, #memory.opens do
        local mode = memory.opens[index].mode
        if mode == "w" or mode == "wb" then
            writable_opens = writable_opens + 1
            Harness.equal(mode, "wb")
        end
    end
    Harness.equal(writable_opens, #writer.paths)
end)

Harness.test("writer drops records instead of exceeding bounded memory", function()
    local host = Fakes.validation_host()
    local writer = Writer.new(host, host.state.now, {
        max_file_bytes = 100000,
        max_buffer_bytes = 800,
    })
    for index = 1, 20 do
        writer:append("synthetic", {
            index = index,
            payload = string.rep("x", 100),
        }, host.state.now)
    end
    Harness.truthy(writer.dropped_records > 0)
    Harness.truthy(writer.buffer_bytes <= 800)
    Harness.equal(writer.record_sequence, 20)
    writer:flush(host.state.now)
    writer:close()
end)
