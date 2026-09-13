--- Optional position persistence with preferred and game-directory fallbacks.
-- @module ubermensch.persistence

local Constants = require("ubermensch.constants")
local Position = require("ubermensch.position")
local Safe = require("ubermensch.safe")

local Persistence = {}
Persistence.__index = Persistence

--- Adds a usable path once while preserving preference order.
-- @param paths Ordered path array.
-- @param seen Set of paths already added.
-- @param path Candidate path.
local function add_path(paths, seen, path)
    if type(path) == "string" and path ~= "" and not seen[path] then
        paths[#paths + 1] = path
        seen[path] = true
    end
end

--- Resolves preferred and fallback persistence paths without writing files.
-- @param host Host libraries required to derive paths.
-- @return table Ordered candidate paths.
local function candidate_paths(host)
    local paths = {}
    local seen = {}
    local os_api = host.os or host.os_api
    if os_api ~= nil and type(os_api.getenv) == "function" then
        local ok, local_app_data = pcall(function()
            return os_api.getenv("LOCALAPPDATA")
        end)
        if ok and type(local_app_data) == "string" and local_app_data ~= "" then
            add_path(
                paths,
                seen,
                local_app_data .. "\\lua\\" .. Constants.POSITION_FILENAME
            )
        end
    end

    local create_ok, _, created_directory = Safe.library(
        host.filesystem,
        "CreateDirectory",
        Constants.POSITION_DIRECTORY
    )
    if create_ok and type(created_directory) == "string"
        and created_directory ~= ""
    then
        add_path(
            paths,
            seen,
            created_directory .. "\\" .. Constants.POSITION_FILENAME
        )
    end

    local ok, game_directory = Safe.library(host.engine, "GetGameDir")
    if ok and type(game_directory) == "string" and game_directory ~= "" then
        local directory = game_directory .. "\\" .. Constants.POSITION_DIRECTORY
        add_path(paths, seen, directory .. "\\" .. Constants.POSITION_FILENAME)
    end
    return paths
end

--- Creates persistence state and loads the first strictly valid position.
-- Failure is intentionally optional: the caller retains the default position
-- and can continue rendering even if all file APIs are unavailable.
-- @param host Host io, os, engine, and optional filesystem libraries.
-- @param position Mutable position state receiving loaded coordinates.
-- @param warn Function invoked at most once if a save later has no usable path.
-- @return table Persistence object.
function Persistence.new(host, position, warn)
    local file_api = host.io or host.file_api
    local self = setmetatable({
        host = host,
        file_api = file_api,
        paths = candidate_paths(host),
        selected_path = nil,
        warned = false,
        warn = warn,
    }, Persistence)

    if file_api ~= nil and type(file_api.open) == "function" then
        for i = 1, #self.paths do
            local ok, handle = pcall(file_api.open, self.paths[i], "r")
            if ok and handle ~= nil then
                local read_ok, content = pcall(function()
                    return handle:read("*a")
                end)
                pcall(function()
                    handle:close()
                end)
                local x, y
                if read_ok then x, y = Position.parse(content) end
                if x ~= nil then
                    position.x = x
                    position.y = y
                    self.selected_path = self.paths[i]
                    break
                end
            end
        end
    end
    return self
end

--- Emits the single optional-persistence warning for this load.
-- @param self Persistence object.
local function warn_once(self)
    if not self.warned then
        self.warned = true
        self.warn(Constants.PREFIX .. " position persistence unavailable")
    end
end

--- Saves a dirty position, trying every candidate until one succeeds.
-- The dirty flag is cleared only after a complete write and close operation.
-- @param self Persistence object.
-- @param position Position state to serialize and possibly mark clean.
-- @return boolean Whether the position was persisted.
function Persistence.save(self, position)
    if not position.dirty then
        return true
    end
    local content = Position.serialize(position.x, position.y)
    if content == nil
        or self.file_api == nil
        or type(self.file_api.open) ~= "function"
    then
        warn_once(self)
        return false
    end

    local ordered = {}
    if self.selected_path ~= nil then
        ordered[#ordered + 1] = self.selected_path
    end
    for i = 1, #self.paths do
        if self.paths[i] ~= self.selected_path then
            ordered[#ordered + 1] = self.paths[i]
        end
    end

    for i = 1, #ordered do
        local ok, handle = pcall(self.file_api.open, ordered[i], "w")
        if ok and handle ~= nil then
            local write_ok = pcall(function()
                handle:write(content)
            end)
            local close_ok = pcall(function()
                handle:close()
            end)
            if write_ok and close_ok then
                self.selected_path = ordered[i]
                position.dirty = false
                return true
            end
        end
    end
    warn_once(self)
    return false
end

return Persistence
