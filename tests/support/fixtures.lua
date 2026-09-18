local Fixtures = {}

function Fixtures.side(team, family, charge, source, deployed, deployment_source)
    return {
        team = team,
        family = family,
        family_source = source or "current",
        charge = charge,
        charge_source = source or "current",
        deployed = deployed == true,
        deployment_source = deployment_source or source or "current",
        alive = true,
    }
end

function Fixtures.snapshot(overrides)
    local result = {
        now = 10,
        map = "cp_badlands",
        round_state = 4,
        is_mvm = false,
        phase = "running",
        roster_available = true,
        players = {},
        local_userid = 10,
        local_team = 2,
        local_class = 1,
        local_alive = true,
        is_casual = false,
        is_competitive = false,
        is_tournament = false,
        is_highlander = false,
        configured_player_slots = nil,
    }
    for key, value in pairs(overrides or {}) do
        result[key] = value
    end
    return result
end

function Fixtures.player(userid, index, team, family, charge, source)
    source = source or "current"
    local row = {
        userid = userid,
        entity_index = index,
        resource_present = true,
        connected = true,
        valid = true,
        alive = true,
        team = team,
        class = 5,
        current_present = source == "current",
        current_team = source == "current" and team or nil,
        current_class = source == "current" and 5 or nil,
        current_alive = source == "current" and true or nil,
    }
    if source == "current" then
        row.current_family = family
        row.current_charge = charge
        row.current_deployed = false
    else
        row.resource_charge = charge
    end
    return row
end

return Fixtures
