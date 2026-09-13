local Harness = {
    tests = {},
    assertions = 0,
}

local function fail(message)
    error(message, 3)
end

function Harness.test(name, body)
    Harness.tests[#Harness.tests + 1] = { name = name, body = body }
end

function Harness.equal(actual, expected, message)
    Harness.assertions = Harness.assertions + 1
    if actual ~= expected then
        fail(string.format(
            "%s: expected %s, got %s",
            message or "values differ",
            tostring(expected),
            tostring(actual)
        ))
    end
end

function Harness.near(actual, expected, tolerance, message)
    Harness.assertions = Harness.assertions + 1
    if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
        fail(string.format(
            "%s: expected %.12g +/- %.12g, got %s",
            message or "values differ",
            expected,
            tolerance,
            tostring(actual)
        ))
    end
end

function Harness.truthy(value, message)
    Harness.assertions = Harness.assertions + 1
    if not value then
        fail(message or "expected truthy value")
    end
end

function Harness.falsy(value, message)
    Harness.assertions = Harness.assertions + 1
    if value then
        fail(message or "expected falsy value")
    end
end

function Harness.is_nil(value, message)
    Harness.assertions = Harness.assertions + 1
    if value ~= nil then
        fail((message or "expected nil") .. ", got " .. tostring(value))
    end
end

function Harness.contains(text, fragment, message)
    Harness.assertions = Harness.assertions + 1
    if type(text) ~= "string" or not string.find(text, fragment, 1, true) then
        fail(message or ("expected text containing " .. tostring(fragment)))
    end
end

function Harness.same_table(actual, expected, message)
    Harness.assertions = Harness.assertions + 1
    if type(actual) ~= "table" or #actual ~= #expected then
        fail(message or "table lengths differ")
    end
    for i = 1, #expected do
        if actual[i] ~= expected[i] then
            fail(string.format(
                "%s at index %d: expected %s, got %s",
                message or "tables differ",
                i,
                tostring(expected[i]),
                tostring(actual[i])
            ))
        end
    end
end

function Harness.run()
    local failures = {}
    for i = 1, #Harness.tests do
        local test = Harness.tests[i]
        local ok, failure = pcall(test.body)
        if not ok then
            failures[#failures + 1] = test.name .. ": " .. tostring(failure)
        end
    end
    if #failures > 0 then
        for i = 1, #failures do
            io.stderr:write("FAIL ", failures[i], "\n")
        end
        io.stderr:write(string.format(
            "%d/%d tests failed (%d assertions)\n",
            #failures,
            #Harness.tests,
            Harness.assertions
        ))
        os.exit(1)
    end
    print(string.format(
        "PASS %d tests (%d assertions)",
        #Harness.tests,
        Harness.assertions
    ))
end

return Harness
