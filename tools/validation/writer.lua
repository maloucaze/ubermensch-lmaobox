--- Bounded buffered JSONL output and fixed-size log rotation.
-- @module validation.writer

local Json = require("validation.json")
local Safe = require("ubermensch.safe")
local ValidationConstants = require("validation.constants")

local Writer = {}
Writer.__index = Writer

--- Calls an ordinary file-handle method under protected execution.
-- @param handle Open file handle.
-- @param method Method name.
-- @param ... Arguments passed to the method.
-- @return boolean Whether the operation completed.
-- @return any First return or error.
local function file_call(handle, method, ...)
    if handle == nil or type(handle[method]) ~= "function" then
        return false, "missing file method " .. method
    end
    return pcall(handle[method], handle, ...)
end

--- Creates a collision-resistant ASCII session stem.
-- @param host Validation host containing standard Lua APIs.
-- @param now Current monotonic time.
-- @return string Filename stem.
local function session_stem(host, now)
    local os_api = host.os_api or host.os
    local stamp
    if os_api ~= nil and type(os_api.date) == "function" then
        local ok, value = pcall(os_api.date, "%Y%m%d_%H%M%S")
        if ok and type(value) == "string" then
            stamp = value
        end
    end
    stamp = stamp or "undated"
    return string.format(
        "%s_%s_%09d",
        ValidationConstants.FILE_PREFIX,
        stamp,
        math.floor(now * 1000) % 1000000000
    )
end

--- Resolves writable directory candidates in preference order.
-- @param host LMAOBox host and standard Lua APIs.
-- @return table Candidate directory paths.
local function candidate_directories(host)
    local directories = {}
    local seen = {}
    local ok, _, path = Safe.library(
        host.filesystem,
        "CreateDirectory",
        ValidationConstants.DIRECTORY
    )
    if ok and type(path) == "string" and path ~= "" then
        directories[#directories + 1] = path
        seen[path] = true
    end
    -- CreateDirectory can report an existing directory without returning its
    -- absolute path. Standard Lua file access remains able to resolve this
    -- game-directory-relative candidate in the supported host.
    if not seen[ValidationConstants.DIRECTORY] then
        directories[#directories + 1] = ValidationConstants.DIRECTORY
        seen[ValidationConstants.DIRECTORY] = true
    end
    local os_api = host.os_api or host.os
    if os_api ~= nil and type(os_api.getenv) == "function" then
        local env_ok, local_app_data = pcall(os_api.getenv, "LOCALAPPDATA")
        if env_ok and type(local_app_data) == "string"
            and local_app_data ~= ""
        then
            local fallback = local_app_data .. "\\lua"
            if not seen[fallback] then
                directories[#directories + 1] = fallback
            end
        end
    end
    return directories
end

--- Determines whether a prospective first log part already exists.
-- @param file_api Standard Lua-compatible file API.
-- @param path Candidate part path.
-- @return boolean Whether a readable file occupies the path.
local function file_exists(file_api, path)
    local ok, handle = pcall(file_api.open, path, "r")
    if not ok or handle == nil then
        return false
    end
    file_call(handle, "close")
    return true
end

--- Finds a bounded, non-existing session stem within one directory.
-- @param file_api Standard Lua-compatible file API.
-- @param directory Candidate output directory.
-- @param base_stem Timestamp-derived base stem.
-- @return string|nil Available stem, or nil after exhausting suffixes.
local function available_stem(file_api, directory, base_stem)
    for suffix = 0, 999 do
        local stem = suffix == 0
            and base_stem
            or string.format("%s_%03d", base_stem, suffix)
        local first_path = directory
            .. "\\"
            .. stem
            .. "_part01.jsonl"
        if not file_exists(file_api, first_path) then
            return stem
        end
    end
    return nil
end

--- Closes the active handle and disables output after a permanent fault.
-- @param reason Concise failure description.
function Writer:disable(reason)
    if self.disabled then
        return
    end
    self.disabled = true
    if self.handle ~= nil then
        file_call(self.handle, "close")
        self.handle = nil
    end
    self.print_function(
        ValidationConstants.PREFIX .. " recorder disabled: " .. tostring(reason)
    )
end

--- Opens one numbered part in the already selected directory.
-- @param self Writer instance.
-- @param part One-based part number.
-- @return boolean Whether a writable handle was opened.
local function open_part(self, part)
    local filename = string.format("%s_part%02d.jsonl", self.stem, part)
    local path = self.directory .. "\\" .. filename
    -- Binary mode keeps byte accounting identical on Windows and prevents Lua
    -- from expanding JSONL newlines to CRLF after the part limit was checked.
    local ok, handle = pcall(self.file_api.open, path, "wb")
    if not ok or handle == nil then
        return false
    end
    self.handle = handle
    self.part = part
    self.path = path
    self.paths[#self.paths + 1] = path
    self.bytes_written = 0
    return true
end

--- Encodes one explicitly sequenced JSONL record without buffering it.
-- @param self Writer instance.
-- @param sequence Session-wide record sequence.
-- @param kind Stable record kind.
-- @param data Record payload.
-- @param now Monotonic record time.
-- @return string|nil JSON line, or nil after an encoding failure.
local function encode_line(self, sequence, kind, data, now)
    local ok, encoded = pcall(Json.encode, {
        data = data or {},
        seq = sequence,
        t = now,
        type = kind,
        v = ValidationConstants.FORMAT_VERSION,
    })
    if not ok then
        self:disable("JSON encoding failed: " .. tostring(encoded))
        return nil
    end
    return encoded .. "\n"
end

--- Appends one prepared entry to the in-memory write queue.
-- @param self Writer instance.
-- @param line Encoded JSONL line.
-- @param rotate_to Optional part number to open immediately before the line.
local function queue_line(self, line, rotate_to)
    self.buffer[#self.buffer + 1] = {
        line = line,
        rotate_to = rotate_to,
    }
    self.buffer_bytes = self.buffer_bytes + #line
end

--- Accounts for a record rejected by the bounded memory queue.
-- A sequence is still consumed so the resulting gap exposes the loss.
-- @param self Writer instance.
local function record_drop(self)
    self.record_sequence = self.record_sequence + 1
    self.dropped_records = self.dropped_records + 1
    self.pending_drops = self.pending_drops + 1
end

--- Writes one accumulated same-part batch and clears its reusable array.
-- @param self Writer instance.
-- @param count Number of populated batch entries.
-- @return boolean Whether the write completed.
local function write_batch(self, count)
    if count == 0 then
        return true
    end
    local batch = self.flush_batch
    local payload = table.concat(batch, "", 1, count)
    local ok, failure = file_call(self.handle, "write", payload)
    if not ok then
        self:disable(failure)
        return false
    end
    self.bytes_written = self.bytes_written + #payload
    for index = 1, count do
        batch[index] = nil
    end
    return true
end

--- Adds one JSON record to bounded memory for a later non-Draw flush.
-- Sequence gaps and final drop counters make any rejected record explicit.
-- @param kind Stable record kind.
-- @param data Record payload.
-- @param now Monotonic record time.
-- @return boolean Whether the record entered the buffer.
function Writer:append(kind, data, now)
    if self.disabled then
        return false
    end
    local sequence = self.record_sequence + 1
    local line = encode_line(self, sequence, kind, data, now)
    if line == nil then
        return false
    end

    local rotate_to
    local header
    local required_bytes = #line
    if self.projected_part_bytes > 0
        and self.projected_part_bytes + #line > self.max_file_bytes
    then
        rotate_to = self.projected_part + 1
        header = encode_line(self, sequence, "segment_start", {
            part = rotate_to,
            previous_record_sequence = self.last_queued_sequence,
            session = self.session,
        }, now)
        if header == nil then
            return false
        end
        sequence = sequence + 1
        line = encode_line(self, sequence, kind, data, now)
        if line == nil then
            return false
        end
        required_bytes = #header + #line
    end

    if self.buffer_bytes + required_bytes > self.max_buffer_bytes then
        record_drop(self)
        return false
    end

    if rotate_to ~= nil then
        queue_line(self, header, rotate_to)
        self.projected_part = rotate_to
        self.projected_part_bytes = #header
    end
    queue_line(self, line)
    self.record_sequence = sequence
    self.last_queued_sequence = sequence
    self.projected_part_bytes = self.projected_part_bytes + #line
    return true
end

--- Flushes buffered lines and rotates before exceeding the fixed part limit.
-- Callers keep this operation out of Draw; the writer itself has no callback
-- knowledge and performs no background or network work.
-- @param now Current monotonic time.
-- @return boolean Whether all buffered data was written.
function Writer:flush(now)
    if self.disabled or #self.buffer == 0 then
        return not self.disabled
    end
    local batch_count = 0
    for index = 1, #self.buffer do
        local entry = self.buffer[index]
        local line = entry.line
        if entry.rotate_to ~= nil then
            if not write_batch(self, batch_count) then
                return false
            end
            batch_count = 0
            file_call(self.handle, "flush")
            file_call(self.handle, "close")
            self.handle = nil
            if not open_part(self, entry.rotate_to) then
                self:disable("cannot open rotated log part")
                return false
            end
            self.print_function(
                ValidationConstants.PREFIX .. " rotated log: " .. self.path
            )
        end
        batch_count = batch_count + 1
        self.flush_batch[batch_count] = line
    end
    if not write_batch(self, batch_count) then
        return false
    end
    local ok, failure = file_call(self.handle, "flush")
    if not ok then
        self:disable(failure)
        return false
    end
    for index = 1, #self.buffer do
        self.buffer[index] = nil
    end
    self.buffer_bytes = 0
    self.projected_part = self.part
    self.projected_part_bytes = self.bytes_written
    self.last_flush = now
    return true
end

--- Closes the current file after the caller has flushed final records.
function Writer:close()
    if self.handle ~= nil then
        file_call(self.handle, "close")
        self.handle = nil
    end
end

--- Opens the first validation log and initializes bounded writer state.
-- @param host LMAOBox host and standard Lua APIs.
-- @param now Current monotonic time.
-- @param limits Fixed maximum buffer and file sizes.
-- @return table Writer instance, possibly disabled when no path is writable.
function Writer.new(host, now, limits)
    local base_stem = session_stem(host, now)
    local self = setmetatable({
        print_function = host.print_function or host.print or print,
        file_api = host.file_api or host.io,
        stem = base_stem,
        session = base_stem,
        paths = {},
        buffer = {},
        flush_batch = {},
        buffer_bytes = 0,
        bytes_written = 0,
        part = 0,
        projected_part = 0,
        projected_part_bytes = 0,
        disabled = false,
        record_sequence = 0,
        last_queued_sequence = 0,
        dropped_records = 0,
        pending_drops = 0,
        last_flush = now,
        max_buffer_bytes = limits.max_buffer_bytes,
        max_file_bytes = limits.max_file_bytes,
    }, Writer)
    if self.file_api == nil or type(self.file_api.open) ~= "function" then
        self.disabled = true
        self.print_function(
            ValidationConstants.PREFIX .. " recording unavailable: io.open missing"
        )
        return self
    end
    local directories = candidate_directories(host)
    for index = 1, #directories do
        self.directory = directories[index]
        local stem = available_stem(
            self.file_api,
            self.directory,
            base_stem
        )
        if stem ~= nil then
            self.stem = stem
            self.session = stem
        end
        if stem ~= nil and open_part(self, 1) then
            self.projected_part = self.part
            self.projected_part_bytes = self.bytes_written
            break
        end
    end
    if self.handle == nil then
        self.disabled = true
        self.print_function(
            ValidationConstants.PREFIX .. " recording unavailable: no writable path"
        )
    end
    return self
end

return Writer
