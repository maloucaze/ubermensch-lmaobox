--- Deterministic JSON encoding for validation log records.
-- @module validation.json

local Json = {}

local ESCAPE = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

--- Escapes one string as a JSON string without changing UTF-8 bytes.
-- @param value Lua string.
-- @return string Quoted JSON string.
local function encode_string(value)
    return '"' .. string.gsub(value, '[%z\1-\31\\"]', function(character)
        return ESCAPE[character]
            or string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

--- Recognizes a nonempty contiguous one-based Lua array.
-- Empty tables intentionally encode as objects because Lua has no intrinsic
-- empty-array distinction and all log readers accept either empty shape.
-- @param value Table to classify.
-- @return boolean Whether the table is a contiguous array.
-- @return number Array length when contiguous.
local function array_length(value)
    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false, 0
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    return count > 0 and maximum == count, maximum
end

local encode_value

--- Encodes a JSON array while detecting recursive table references.
-- @param value Contiguous Lua array.
-- @param length Array length.
-- @param active Set of tables in the current recursion path.
-- @return string JSON array.
local function encode_array(value, length, active)
    local parts = {}
    for index = 1, length do
        parts[index] = encode_value(value[index], active)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

--- Encodes an object with lexically sorted string keys for stable deltas.
-- @param value Lua table with string keys.
-- @param active Set of tables in the current recursion path.
-- @return string JSON object.
local function encode_object(value, active)
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" then
            error("JSON object key must be a string", 3)
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local parts = {}
    for index = 1, #keys do
        local key = keys[index]
        parts[index] = encode_string(key)
            .. ":"
            .. encode_value(value[key], active)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- Encodes one supported Lua value recursively.
-- Nil is represented as JSON null. Nonfinite numbers and unsupported values are
-- rejected so diagnostic corruption cannot be mistaken for valid evidence.
-- @param value Lua primitive or acyclic table.
-- @param active Set of tables in the current recursion path.
-- @return string JSON representation.
encode_value = function(value, active)
    local kind = type(value)
    if value == nil then
        return "null"
    end
    if kind == "boolean" then
        return value and "true" or "false"
    end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("cannot encode a nonfinite JSON number", 3)
        end
        local formatted = string.format("%.17g", value)
        return string.gsub(formatted, ",", ".")
    end
    if kind == "string" then
        return encode_string(value)
    end
    if kind ~= "table" then
        error("cannot encode JSON value of type " .. kind, 3)
    end
    if active[value] then
        error("cannot encode a recursive table", 3)
    end
    active[value] = true
    local is_array, length = array_length(value)
    local encoded = is_array
        and encode_array(value, length, active)
        or encode_object(value, active)
    active[value] = nil
    return encoded
end

--- Encodes an acyclic Lua value as deterministic compact JSON.
-- @param value Lua primitive or table containing JSON-compatible values.
-- @return string JSON representation with stable object-key order.
function Json.encode(value)
    return encode_value(value, {})
end

return Json
