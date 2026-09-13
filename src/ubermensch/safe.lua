--- Protected helpers for the untrusted LMAOBox host boundary.
-- @module ubermensch.safe

local Safe = {}
--- Reads a member without assuming native proxy objects are ordinary tables.
-- @param object Host object or library.
-- @param name Member name.
-- @return any|nil Member value when readable.
function Safe.member(object, name)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    if ok then
        return value
    end
    return nil
end

--- Calls a host library function with protected failure isolation.
-- Callable native proxies are accepted even when Lua does not report their
-- type as `function`.
-- @param library Host library object.
-- @param name Function name.
-- @param ... Arguments passed without an implicit receiver.
-- @return boolean Whether the call completed.
-- @return any First returned value or raised error.
-- @return any Second returned value when present.
function Safe.library(library, name, ...)
    local callable = Safe.member(library, name)
    if callable == nil then
        return false, "missing member"
    end
    return pcall(callable, ...)
end

--- Calls a host object method with protected failure isolation.
-- @param object Transient host object.
-- @param name Method name.
-- @param ... Method arguments.
-- @return boolean Whether the method completed.
-- @return any First returned value or raised error.
-- @return any Second returned value when present.
function Safe.method(object, name, ...)
    local callable = Safe.member(object, name)
    if callable == nil then
        return false, "missing member"
    end
    return pcall(callable, object, ...)
end

return Safe
