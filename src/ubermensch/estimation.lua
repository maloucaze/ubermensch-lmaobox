--- Pure charge estimation from immutable trustworthy anchors.
-- @module ubermensch.estimation

local Constants = require("ubermensch.constants")
local Numbers = require("ubermensch.numbers")
local Weapons = require("ubermensch.weapons")

local Estimation = {}

--- Returns the build multiplier active at a monotonic instant.
-- Phase history entries are ordered transitions shaped as `{time, multiplier}`.
-- @param history Ordered, bounded phase-transition history.
-- @param at_time Monotonic instant to inspect.
-- @return number Positive phase multiplier, defaulting to normal build speed.
function Estimation.multiplier_at(history, at_time)
    local multiplier = 1
    for i = 1, #history do
        local transition = history[i]
        if transition.time > at_time then
            break
        end
        multiplier = transition.multiplier
    end
    return multiplier
end

--- Integrates phase-adjusted build time over a monotonic interval.
-- This preserves setup/running transitions without mutating or re-anchoring a
-- Medic's trustworthy observation.
-- @param history Ordered phase transitions.
-- @param start_time Inclusive monotonic interval start.
-- @param end_time Monotonic interval end.
-- @return number|nil Normal-speed-equivalent seconds, or nil for invalid time.
function Estimation.build_seconds(history, start_time, end_time)
    if not Numbers.is_finite(start_time)
        or not Numbers.is_finite(end_time)
        or end_time < start_time
    then
        return nil
    end

    local cursor = start_time
    local multiplier = Estimation.multiplier_at(history, start_time)
    local total = 0
    for i = 1, #history do
        local transition = history[i]
        if transition.time > start_time and transition.time < end_time then
            total = total + (transition.time - cursor) * multiplier
            cursor = transition.time
            multiplier = transition.multiplier
        end
    end
    return total + (end_time - cursor) * multiplier
end

--- Estimates charge and deployment state from one immutable trusted anchor.
-- Deployment drains at a fixed eight-second full-charge rate. If the drain
-- ends before `now`, ideal rebuilding begins at zero and respects phase changes.
-- @param anchor Table containing charge, time, and deployed fields.
-- @param family Supported family label.
-- @param now Current monotonic time.
-- @param phase_history Ordered phase transitions.
-- @return number|nil Estimated percentage.
-- @return boolean|nil Estimated deployment state; nil when estimation is impossible.
function Estimation.from_anchor(anchor, family, now, phase_history)
    if type(anchor) ~= "table"
        or not Weapons.is_supported(family)
        or Numbers.percent(anchor.charge) == nil
        or not Numbers.is_finite(anchor.time)
        or not Numbers.is_finite(now)
        or now < anchor.time
    then
        return nil, nil
    end

    local rate = Constants.CHARGE_RATE[family]
    local elapsed = now - anchor.time
    if anchor.deployed == true then
        local drain_seconds = anchor.charge / Constants.DEPLOY_DRAIN_RATE
        if elapsed < drain_seconds then
            return Numbers.clamp(
                anchor.charge - elapsed * Constants.DEPLOY_DRAIN_RATE,
                0,
                100
            ), true
        end
        local rebuild_start = anchor.time + drain_seconds
        local build_seconds = Estimation.build_seconds(
            phase_history,
            rebuild_start,
            now
        )
        if build_seconds == nil then
            return nil, nil
        end
        return Numbers.clamp(build_seconds * rate, 0, 100), false
    end

    local build_seconds = Estimation.build_seconds(
        phase_history,
        anchor.time,
        now
    )
    if build_seconds == nil then
        return nil, nil
    end
    return Numbers.clamp(anchor.charge + build_seconds * rate, 0, 100), false
end

return Estimation
