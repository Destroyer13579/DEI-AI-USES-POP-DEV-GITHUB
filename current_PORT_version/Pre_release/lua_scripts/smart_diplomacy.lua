-- smart diplomacy - distance war blocking + cascading peace + coalition system
-- stops random factions across the map from declaring war on you
-- only neighbors can actually start wars now
-- if a client state's master achieves peace, it cascades down to client states 
-- AI factions form coalitions against rapidly expanding factions and dogpile them

-- part of the AI Uses Population and More SUBMOD! Made by Destroyer
-- Coalition system designed by Destroyer;assisted, re-organized and logged by Claude AI (lifesaver lol)

local scripting = require "lua_scripts.EpisodicScripting"

-- ============================================================================
-- CONFIG
-- ============================================================================

-- distance war blocking
local WAR_DISTANCE_THRESHOLD = 100
local RECALC_FREQUENCY = 1
local LOG_ENABLED = false

-- cascading peace
local CASCADE_PEACE_ENABLED = true
local CASCADE_FROM_ALLIES = false

-- coalition system
local COALITION_ENABLED = true
local COALITION_CHECK_DELTA = 1
local COALITION_GROWTH_MILD = 0.35
local COALITION_GROWTH_SEVERE = 0.65
-- threat meter
local THREAT_DECAY = 0.15
local THREAT_GROWTH_WEIGHT = 15
local THREAT_SIZE_WEIGHT = 10
local THREAT_MILD_THRESHOLD = 50
local THREAT_SEVERE_THRESHOLD = 80
local THREAT_POST_TRIGGER = 0.4
local THREAT_GROWTH_RATIO_CAP = 5.0
local THREAT_SIZE_RATIO_CAP = 5.0
local COALITION_MIN_TURN = 10
local COALITION_MIN_REGIONS = 7
local COALITION_COOLDOWN = 10
local COALITION_FORM_CHANCE_MIN = 0.65   -- minimum random chance for 2nd+ coalition
local COALITION_FORM_CHANCE_MAX = 0.99   -- maximum random chance for 2nd+ coalition
local COALITION_INCLUDE_HUMAN = true
local COALITION_MIN_MEMBERS = 2
local COALITION_MAX_MEMBERS = 5
local COALITION_MAX_ACTIVE_VS_PLAYER = 1   -- only 1 coalition against the player at a time
local COALITION_MAX_ACTIVE_VS_AI = 2       -- up to 2 AI-vs-AI coalitions
local COALITION_AI_PEACE_LOCK = 5
local COALITION_PLAYER_PEACE_LOCK = 11
local COALITION_DISSOLVE_RATIO = 0.5

-- ============================================================================
-- STATE
-- ============================================================================

local blocked_factions = {}
local human_factions = {}
local last_calc = {}

local coalition_snapshots = {}
local coalition_snapshot_turn = 0
local coalition_cooldowns = {}
local coalition_formation_counts = {}    -- tracks how many coalitions have targeted each faction
local faction_threat_scores = {}
local coalition_war_overrides = {}
local coalition_checked_this_turn = false
local active_coalitions = {}
local coalition_notify_player = false  -- set true when a coalition forms vs player, fires on player turn
local coalition_notify_members = ""    -- stores member faction names for UI text injection
local pending_player_coalitions = {}   -- queued coalitions vs player, formed at player turn start
local coalition_ai_notify_queue = {}   -- queued AI coalition notifications [{members=str, threat=key}]
local coalition_ai_notify_text = ""    -- built text for AI coalition popup
local coalition_dissolved_text = ""    -- built text for dissolution popup
local coalition_dissolved_fired = false -- ensures dissolution popup only fires once
local coalition_new_formation = false  -- true when coalition JUST formed (wars may not be in treaty_details yet)

-- ============================================================================
-- LOGGING
-- ============================================================================

local function Log(text)
    if not LOG_ENABLED then return end
    local f = io.open("Smart_Diplomacy_Log.txt", "a")
    if f then
        f:write("[" .. os.date("%d, %m %Y %X") .. "] " .. text .. "\n")
        f:flush()
        f:close()
    end
end

-- ============================================================================
-- UTILITIES
-- ============================================================================

local function Dist(x1, y1, x2, y2)
    local dx = x2 - x1
    local dy = y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function GetHumans()
    if #human_factions > 0 then return human_factions end
    pcall(function()
        local flist = scripting.game_interface:model():world():faction_list()
        for i = 0, flist:num_items() - 1 do
            local f = flist:item_at(i)
            if f:is_human() then
                table.insert(human_factions, f:name())
                Log("found human: " .. f:name())
            end
        end
    end)
    return human_factions
end

local function GetFactionKey(faction_ref)
    if type(faction_ref) == "string" then return faction_ref end
    local ok, name = pcall(function() return faction_ref:name() end)
    if ok then return name end
    return nil
end

local function IsSlaveFaction(faction_key)
    if not faction_key then return true end
    if string.find(faction_key, "slave") then return true end
    if string.find(faction_key, "rebel") then return true end
    return false
end

local function IsHumanFaction(faction_key)
    for _, hkey in ipairs(human_factions) do
        if faction_key == hkey then return true end
    end
    return false
end

local function AreAtWar(faction_key_a, faction_key_b)
    local at_war = false
    pcall(function()
        local fac = scripting.game_interface:model():world():faction_by_key(faction_key_a)
        if not fac then return end
        local treaties = fac:treaty_details()
        if not treaties then return end
        for other_faction, treaty_list in pairs(treaties) do
            local other_key = GetFactionKey(other_faction)
            if other_key == faction_key_b then
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_at_war" then
                        at_war = true
                        return
                    end
                end
            end
        end
    end)
    return at_war
end

local function IsFactionAlive(faction_key)
    local alive = false
    pcall(function()
        local fac = scripting.game_interface:model():world():faction_by_key(faction_key)
        if fac and fac:has_home_region() then alive = true end
    end)
    return alive
end

local function IsInAnyCoalition(faction_key)
    for _, coal in ipairs(active_coalitions) do
        if coal.threat_key == faction_key then return true end
        for _, member in ipairs(coal.members) do
            if member == faction_key then return true end
        end
    end
    return false
end

-- count how many active coalitions target a human player
local function CountPlayerCoalitions()
    local count = 0
    for _, coal in ipairs(active_coalitions) do
        if IsHumanFaction(coal.threat_key) then
            count = count + 1
        end
    end
    return count
end

-- count how many active coalitions target AI factions
local function CountAICoalitions()
    local count = 0
    for _, coal in ipairs(active_coalitions) do
        if not IsHumanFaction(coal.threat_key) then
            count = count + 1
        end
    end
    return count
end

-- get distance from a faction to the nearest human settlement
local function GetFactionDistToHuman(faction_key)
    local min_dist = 99999
    pcall(function()
        local fac = scripting.game_interface:model():world():faction_by_key(faction_key)
        if not fac then return end
        local fac_regions = fac:region_list()
        if fac_regions:num_items() == 0 then return end

        for _, hkey in ipairs(human_factions) do
            local hfac = scripting.game_interface:model():world():faction_by_key(hkey)
            if hfac then
                local hregs = hfac:region_list()
                for i = 0, fac_regions:num_items() - 1 do
                    local fs = fac_regions:item_at(i):settlement()
                    local fx, fy = fs:logical_position_x(), fs:logical_position_y()
                    for j = 0, hregs:num_items() - 1 do
                        local hs = hregs:item_at(j):settlement()
                        local d = Dist(fx, fy, hs:logical_position_x(), hs:logical_position_y())
                        if d < min_dist then min_dist = d end
                    end
                end
            end
        end
    end)
    return min_dist
end

-- get distance between two factions (closest settlements)
local function GetFactionToFactionDist(key_a, key_b)
    local min_dist = 99999
    pcall(function()
        local fac_a = scripting.game_interface:model():world():faction_by_key(key_a)
        local fac_b = scripting.game_interface:model():world():faction_by_key(key_b)
        if not fac_a or not fac_b then return end
        local regs_a = fac_a:region_list()
        local regs_b = fac_b:region_list()
        if regs_a:num_items() == 0 or regs_b:num_items() == 0 then return end

        for i = 0, regs_a:num_items() - 1 do
            local sa = regs_a:item_at(i):settlement()
            local ax, ay = sa:logical_position_x(), sa:logical_position_y()
            for j = 0, regs_b:num_items() - 1 do
                local sb = regs_b:item_at(j):settlement()
                local d = Dist(ax, ay, sb:logical_position_x(), sb:logical_position_y())
                if d < min_dist then min_dist = d end
            end
        end
    end)
    return min_dist
end

-- ============================================================================
-- TREATY HELPERS
-- ============================================================================

local function GetWarsForFaction(faction_key)
    local wars = {}
    pcall(function()
        local fac = scripting.game_interface:model():world():faction_by_key(faction_key)
        if not fac then return end
        local treaties = fac:treaty_details()
        if not treaties then return end
        for other_faction, treaty_list in pairs(treaties) do
            local other_key = GetFactionKey(other_faction)
            if other_key then
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_at_war" then
                        wars[other_key] = true
                    end
                end
            end
        end
    end)
    return wars
end

-- ============================================================================
-- CASCADING PEACE
-- ============================================================================

local function CheckCascadePeace(ai_faction)
    if not CASCADE_PEACE_ENABLED then return end
    local ai_key = ai_faction:name()

    -- =====================================================================
    -- PASS 1: This faction is an OVERLORD — cascade peace DOWN to all clients/vassals
    -- If this faction is at peace with enemy X, but a client is still at war with X, force peace.
    -- Works for both human and AI clients.
    -- =====================================================================
    local clients = {}
    pcall(function()
        local ai_treaties = ai_faction:treaty_details()
        if not ai_treaties then return end
        local my_regions = ai_faction:region_list():num_items()
        for other_faction, treaty_list in pairs(ai_treaties) do
            local other_key = GetFactionKey(other_faction)
            if other_key and type(treaty_list) == "table" then
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_client_state"
                    or treaty == "current_treaty_client_of_player"
                    or treaty == "current_treaty_vassal" then
                        -- Only count as client if they have fewer regions and are not human
                        local other_fac = scripting.game_interface:model():world():faction_by_key(other_key)
                        if other_fac and not IsHumanFaction(other_key) and other_fac:region_list():num_items() < my_regions then
                            clients[other_key] = true
                        end
                        break
                    end
                    if CASCADE_FROM_ALLIES then
                        if treaty == "current_treaty_military_alliance"
                        or treaty == "current_treaty_defensive_alliance" then
                            clients[other_key] = true
                            break
                        end
                    end
                end
            end
        end
    end)

    if next(clients) then
        local overlord_wars = GetWarsForFaction(ai_key)
        for client_key, _ in pairs(clients) do
            -- Never cascade peace on behalf of a human client — they control their own diplomacy
            if IsHumanFaction(client_key) then
                Log("CASCADE PEACE: Skipping human client " .. client_key .. " (player controls own diplomacy)")
            else
                local client_wars = GetWarsForFaction(client_key)
                for enemy_key, _ in pairs(client_wars) do
                    if not overlord_wars[enemy_key] and enemy_key ~= ai_key then
                        -- Never force peace ON the human player — don't end their wars without consent
                        if IsHumanFaction(enemy_key) then
                            Log("CASCADE PEACE: Skipping " .. client_key .. " <-> " .. enemy_key .. " (will not force peace on human player)")
                        else
                            -- Block cascade if enemy is a coalition member targeting this client
                            local is_coalition_member = false
                            for _, coal in ipairs(active_coalitions) do
                                if coal.threat_key == client_key then
                                    for _, member_key in ipairs(coal.members) do
                                        if member_key == enemy_key then
                                            is_coalition_member = true
                                            break
                                        end
                                    end
                                end
                                if is_coalition_member then break end
                            end

                            if not is_coalition_member then
                                pcall(function()
                                    cm:force_make_peace(client_key, enemy_key)
                                end)
                                Log("CASCADE PEACE: " .. client_key .. " <-> " .. enemy_key
                                    .. " (overlord " .. ai_key .. " at peace)")
                            else
                                Log("CASCADE PEACE: BLOCKED " .. client_key .. " <-> " .. enemy_key
                                    .. " (active coalition member vs " .. client_key .. ")")
                            end
                        end
                    end
                end
            end
        end
    end

    -- =====================================================================
    -- PASS 2: This faction is a CLIENT — find overlord and inherit their peace
    -- If the overlord (human or AI) is at peace with enemy X, but this faction
    -- is still at war with X, force peace. Covers human overlord -> AI client.
    -- Uses region count: overlord always has more regions than client.
    -- =====================================================================
    local overlord_key = nil
    pcall(function()
        local my_regions = ai_faction:region_list():num_items()
        local ai_treaties = ai_faction:treaty_details()
        if not ai_treaties then return end
        for other_faction, treaty_list in pairs(ai_treaties) do
            local other_key = GetFactionKey(other_faction)
            if other_key and other_key ~= ai_key and type(treaty_list) == "table" then
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_client_state"
                    or treaty == "current_treaty_client_of_player"
                    or treaty == "current_treaty_vassal" then
                        -- Only count as overlord if they have MORE regions (we are the client)
                        local other_fac = scripting.game_interface:model():world():faction_by_key(other_key)
                        if other_fac and other_fac:region_list():num_items() > my_regions then
                            overlord_key = other_key
                        end
                        break
                    end
                end
            end
            if overlord_key then return end
        end
    end)

    if overlord_key then
        local ai_wars = GetWarsForFaction(ai_key)
        local overlord_wars = GetWarsForFaction(overlord_key)
        for enemy_key, _ in pairs(ai_wars) do
            if not overlord_wars[enemy_key] and enemy_key ~= overlord_key then
                -- Block cascade if enemy is a coalition member targeting this faction
                local is_coalition_member = false
                for _, coal in ipairs(active_coalitions) do
                    if coal.threat_key == ai_key then
                        for _, member_key in ipairs(coal.members) do
                            if member_key == enemy_key then
                                is_coalition_member = true
                                break
                            end
                        end
                    end
                    if is_coalition_member then break end
                end

                if not is_coalition_member then
                    pcall(function()
                        cm:force_make_peace(ai_key, enemy_key)
                    end)
                    Log("CASCADE PEACE: " .. ai_key .. " <-> " .. enemy_key
                        .. " (overlord " .. overlord_key .. " at peace)")
                else
                    Log("CASCADE PEACE: BLOCKED " .. ai_key .. " <-> " .. enemy_key
                        .. " (active coalition member vs " .. ai_key .. ")")
                end
            end
        end
    end
end

-- ============================================================================
-- CLIENT STATE GROWTH CHECK
-- If a client state grows to within 1 region of their overlord, they break free.
-- Too powerful to remain a subject. Treaty is dissolved via war/peace cycle.
-- ============================================================================

local function CheckClientStateGrowth(ai_faction)
    local ai_key = ai_faction:name()
    local my_regions = 0
    pcall(function() my_regions = ai_faction:region_list():num_items() end)
    if my_regions == 0 then return end

    pcall(function()
        local treaties = ai_faction:treaty_details()
        if not treaties then return end
        for other_faction, treaty_list in pairs(treaties) do
            local other_key = GetFactionKey(other_faction)
            if other_key and type(treaty_list) == "table" then
                local is_client_treaty = false
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_client_state"
                    or treaty == "current_treaty_client_of_player"
                    or treaty == "current_treaty_vassal" then
                        is_client_treaty = true
                        break
                    end
                end

                if is_client_treaty then
                    local other_fac = scripting.game_interface:model():world():faction_by_key(other_key)
                    if other_fac then
                        local other_regions = other_fac:region_list():num_items()

                        -- Determine who is client and who is overlord
                        local client_key, overlord_key, client_regions, overlord_regions
                        if my_regions < other_regions then
                            -- I am the client, they are the overlord
                            client_key = ai_key
                            overlord_key = other_key
                            client_regions = my_regions
                            overlord_regions = other_regions
                        elseif other_regions < my_regions then
                            -- I am the overlord, they are the client
                            -- Skip if the client is human — don't break player's treaties
                            if IsHumanFaction(other_key) then
                                return
                            end
                            client_key = other_key
                            overlord_key = ai_key
                            client_regions = other_regions
                            overlord_regions = my_regions
                        end

                        -- If client has grown to within 1 region of overlord, break free
                        if client_key and overlord_key and client_regions >= (overlord_regions - 1) then
                            Log("CLIENT STATE BREAK: " .. client_key .. " (" .. client_regions .. " regions) outgrew overlord "
                                .. overlord_key .. " (" .. overlord_regions .. " regions) — breaking free!")
                            -- War/peace cycle to dissolve all treaties between them
                            pcall(function()
                                scripting.game_interface:force_diplomacy(client_key, overlord_key, "war", true, true)
                                scripting.game_interface:force_diplomacy(overlord_key, client_key, "war", true, true)
                            end)
                            pcall(function()
                                cm:force_declare_war(client_key, overlord_key)
                            end)
                            pcall(function()
                                scripting.game_interface:force_diplomacy(client_key, overlord_key, "peace", true, true)
                                scripting.game_interface:force_diplomacy(overlord_key, client_key, "peace", true, true)
                            end)
                            pcall(function()
                                cm:force_make_peace(client_key, overlord_key)
                            end)
                            Log("CLIENT STATE BREAK: " .. client_key .. " is now independent from " .. overlord_key)
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================================
-- COALITION - NEIGHBOR DETECTION
-- ============================================================================

local function GetNeighborFactions(faction_key)
    local neighbors = {}
    pcall(function()
        local fac = scripting.game_interface:model():world():faction_by_key(faction_key)
        if not fac then return end
        local regions = fac:region_list()
        for i = 0, regions:num_items() - 1 do
            local region = regions:item_at(i)
            local adj_list = region:adjacent_region_list()
            for j = 0, adj_list:num_items() - 1 do
                local adj_region = adj_list:item_at(j)
                local adj_owner = adj_region:owning_faction():name()
                if adj_owner ~= faction_key and not IsSlaveFaction(adj_owner) then
                    neighbors[adj_owner] = true
                end
            end
        end
    end)
    return neighbors
end

local function GetExtendedNeighbors(faction_key)
    local inner = GetNeighborFactions(faction_key)
    local extended = {}
    for k, _ in pairs(inner) do
        extended[k] = true
    end
    for neighbor_key, _ in pairs(inner) do
        local second_ring = GetNeighborFactions(neighbor_key)
        for k, _ in pairs(second_ring) do
            if k ~= faction_key then
                extended[k] = true
            end
        end
    end
    return extended
end

-- ============================================================================
-- COALITION - FORMATION
-- ============================================================================

-- Returns a table of faction keys that are client states/vassals of the given faction
-- Uses region count to determine direction: clients always have fewer regions than overlord
local function GetClientStates(faction_key)
    local clients = {}
    pcall(function()
        local fac = scripting.game_interface:model():world():faction_by_key(faction_key)
        if not fac then return end
        local my_regions = fac:region_list():num_items()
        local treaties = fac:treaty_details()
        if not treaties then return end
        for other_faction, treaty_list in pairs(treaties) do
            local other_key = GetFactionKey(other_faction)
            if other_key and type(treaty_list) == "table" then
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_client_state"
                    or treaty == "current_treaty_client_of_player"
                    or treaty == "current_treaty_vassal" then
                        -- Only count as client if they have fewer regions (we are the overlord)
                        -- Never include human player — they control their own wars
                        local other_fac = scripting.game_interface:model():world():faction_by_key(other_key)
                        if other_fac and not IsHumanFaction(other_key) then
                            local other_regions = other_fac:region_list():num_items()
                            if other_regions < my_regions then
                                table.insert(clients, other_key)
                                Log("COALITION: " .. other_key .. " is client of " .. faction_key .. " (" .. other_regions .. " vs " .. my_regions .. " regions)")
                            end
                        end
                        break
                    end
                end
            end
        end
    end)
    return clients
end

-- build a valid coalition: members must be within distance threshold of player,
-- not at war with each other, close to each other geographically
local function BuildCoalitionMembers(threat_key, candidate_pool, target_min, target_max)
    local valid = {}
    local is_human_threat = IsHumanFaction(threat_key)

    for candidate_key, _ in pairs(candidate_pool) do
        local dominated = false
        if candidate_key == threat_key then dominated = true end
        if not dominated and IsSlaveFaction(candidate_key) then dominated = true end
        if not dominated and IsInAnyCoalition(candidate_key) then dominated = true end
        if not dominated and IsHumanFaction(candidate_key) then dominated = true end

        -- reject factions that are allied/vassal/client state of the threat
        -- NOTE: treaty_details() is DIRECTIONAL — "current_treaty_client_of_player" means
        -- the calling faction is the OVERLORD. We must check from both sides.

        -- Check 1: candidate's treaties (catches alliances, and candidate being overlord of threat)
        if not dominated then
            local ok1, err1 = pcall(function()
                local candidate_fac = scripting.game_interface:model():world():faction_by_key(candidate_key)
                if not candidate_fac then return end
                local treaties = candidate_fac:treaty_details()
                if not treaties then return end
                for other_faction, treaty_list in pairs(treaties) do
                    local other_key = GetFactionKey(other_faction)
                    if other_key == threat_key and type(treaty_list) == "table" then
                        for _, treaty in ipairs(treaty_list) do
                            if treaty == "current_treaty_military_alliance"
                            or treaty == "current_treaty_defensive_alliance"
                            or treaty == "current_treaty_client_state"
                            or treaty == "current_treaty_client_of_player"
                            or treaty == "current_treaty_vassal" then
                                dominated = true
                                Log("COALITION: " .. candidate_key .. " rejected - allied/overlord of target " .. threat_key .. " (" .. treaty .. ")")
                                break
                            end
                        end
                    end
                    if dominated then break end
                end
            end)
            if not ok1 then Log("COALITION: treaty check 1 error for " .. candidate_key .. ": " .. tostring(err1)) end
        end

        -- Check 2: threat's treaties (catches candidate being a client/vassal OF the threat)
        if not dominated then
            local ok2, err2 = pcall(function()
                local threat_fac = scripting.game_interface:model():world():faction_by_key(threat_key)
                if not threat_fac then return end
                local treaties = threat_fac:treaty_details()
                if not treaties then return end
                for other_faction, treaty_list in pairs(treaties) do
                    local other_key = GetFactionKey(other_faction)
                    if other_key == candidate_key and type(treaty_list) == "table" then
                        for _, treaty in ipairs(treaty_list) do
                            if treaty == "current_treaty_client_state"
                            or treaty == "current_treaty_client_of_player"
                            or treaty == "current_treaty_vassal" then
                                dominated = true
                                Log("COALITION: " .. candidate_key .. " rejected - client/vassal OF target " .. threat_key .. " (" .. treaty .. ")")
                                break
                            end
                        end
                    end
                    if dominated then break end
                end
            end)
            if not ok2 then Log("COALITION: treaty check 2 error for " .. candidate_key .. " vs " .. threat_key .. ": " .. tostring(err2)) end
        end

        if not dominated then
            local has_home = false
            pcall(function()
                local fac = scripting.game_interface:model():world():faction_by_key(candidate_key)
                if fac and fac:has_home_region() then has_home = true end
            end)
            if not has_home then dominated = true end
        end

        -- ONLY factions within distance threshold of the player can join coalitions vs player
        if not dominated and is_human_threat then
            local dist_to_human = GetFactionDistToHuman(candidate_key)
            if dist_to_human > WAR_DISTANCE_THRESHOLD then
                dominated = true
                Log("COALITION: " .. candidate_key .. " rejected - too far from player (dist=" .. math.floor(dist_to_human) .. ")")
            end
        end

        if not dominated then
            table.insert(valid, candidate_key)
        end
    end

    if #valid < target_min then return nil end

    -- sort candidates by distance to the threat faction (closest first)
    -- this naturally clusters the coalition geographically
    local candidate_dists = {}
    for _, ckey in ipairs(valid) do
        candidate_dists[ckey] = GetFactionToFactionDist(ckey, threat_key)
    end
    table.sort(valid, function(a, b) return (candidate_dists[a] or 99999) < (candidate_dists[b] or 99999) end)

    -- greedily build compatible group: no internal wars, and each new member
    -- must be within 2x distance threshold of at least one existing member
    local members = {}
    local PROXIMITY_LIMIT = WAR_DISTANCE_THRESHOLD * 2

    for _, candidate in ipairs(valid) do
        local compatible = true

        -- check no wars with existing members
        for _, existing in ipairs(members) do
            if AreAtWar(candidate, existing) then
                compatible = false
                break
            end
        end

        -- check proximity to at least one existing member (skip for first member)
        if compatible and #members > 0 then
            local close_to_any = false
            for _, existing in ipairs(members) do
                local d = GetFactionToFactionDist(candidate, existing)
                if d <= PROXIMITY_LIMIT then
                    close_to_any = true
                    break
                end
            end
            if not close_to_any then
                compatible = false
                Log("COALITION: " .. candidate .. " rejected - not close enough to other members")
            end
        end

        if compatible then
            table.insert(members, candidate)
            if #members >= target_max then break end
        end
    end

    if #members < target_min then return nil end
    return members
end

-- set bitter enemies stance for all coalition members against the threat
--local function SetBitterEnemies(members, threat_key)
    --for _, member_key in ipairs(members) do
     --   pcall(function()
        --    scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction(
         --       member_key, threat_key, "CAI_STRATEGIC_STANCE_BITTER_ENEMIES")
       -- end)
       -- Log("COALITION: Set BITTER ENEMIES: " .. member_key .. " -> " .. threat_key)
   -- end
--end

local function FormCoalition(threat_key, members, turn)
    local is_ai_target = not IsHumanFaction(threat_key)
    local peace_lock = 0
    if is_ai_target then
        peace_lock = turn + COALITION_AI_PEACE_LOCK
    else
        peace_lock = turn + COALITION_PLAYER_PEACE_LOCK
    end

    local coalition = {
        threat_key = threat_key,
        members = members,
        formed_turn = turn,
        peace_lock_until = peace_lock,
        is_ai_target = is_ai_target
    }

    table.insert(active_coalitions, coalition)

    local member_str = table.concat(members, ", ")
    Log("COALITION FORMED: " .. #members .. " factions [" .. member_str .. "] vs " .. threat_key
        .. " (ai_target=" .. tostring(is_ai_target) .. ", peace_lock=" .. peace_lock .. ")")

    -- SIMULTANEOUS WAR DECLARATIONS
    for _, member_key in ipairs(members) do
        pcall(function()
            scripting.game_interface:force_diplomacy(member_key, threat_key, "war", true, true)
        end)
        pcall(function()
            cm:force_declare_war(member_key, threat_key)
        end)
        Log("COALITION WAR: " .. member_key .. " declares war on " .. threat_key)

        if IsHumanFaction(threat_key) then
            coalition_war_overrides[member_key] = true
        end
    end

    -- Client states of the threat fight alongside their overlord
    local threat_clients = GetClientStates(threat_key)
    for _, client_key in ipairs(threat_clients) do
        for _, member_key in ipairs(members) do
            pcall(function()
                scripting.game_interface:force_diplomacy(member_key, client_key, "war", true, true)
            end)
            pcall(function()
                cm:force_declare_war(member_key, client_key)
            end)
            Log("COALITION WAR: " .. member_key .. " declares war on " .. client_key .. " (client state of " .. threat_key .. ")")
        end
    end

    -- SET BITTER ENEMIES stance for all members vs threat
   -- SetBitterEnemies(members, threat_key)

    -- Lock peace for both sides (AI and player coalitions)
    for _, member_key in ipairs(members) do
        pcall(function()
            scripting.game_interface:force_diplomacy(member_key, threat_key, "peace", false, false)
            scripting.game_interface:force_diplomacy(threat_key, member_key, "peace", false, false)
        end)
        -- Also lock peace between coalition members and threat's client states
        for _, client_key in ipairs(threat_clients) do
            pcall(function()
                scripting.game_interface:force_diplomacy(member_key, client_key, "peace", false, false)
                scripting.game_interface:force_diplomacy(client_key, member_key, "peace", false, false)
            end)
        end
    end
    local lock_turns = is_ai_target and COALITION_AI_PEACE_LOCK or COALITION_PLAYER_PEACE_LOCK
    Log("COALITION: Peace LOCKED for " .. lock_turns .. " turns (" .. (is_ai_target and "AI vs AI" or "AI vs Player") .. ")")

    -- enable alliances between coalition members
    for i, member_a in ipairs(members) do
        for j, member_b in ipairs(members) do
            if i ~= j then
                pcall(function()
                    scripting.game_interface:force_diplomacy(member_a, member_b, "defensive alliance", true, true)
                    scripting.game_interface:force_diplomacy(member_a, member_b, "military alliance", true, true)
                end)
            end
        end
    end

    -- ========== UI NOTIFICATION HOOK ==========
    if IsHumanFaction(threat_key) then
        coalition_notify_player = true
        coalition_notify_members = member_str
        coalition_new_formation = true
    else
        -- Queue AI coalition notification for player to see
        table.insert(coalition_ai_notify_queue, {members = member_str, threat = threat_key})
    end
    Log("*** COALITION ALERT: " .. #members .. " factions [" .. member_str .. "] have formed a coalition against " .. threat_key .. "! ***")
    -- ==========================================

    return coalition
end

local function CleanFactionName(key)
    local name = key
    -- Strip common prefixes
    name = name:gsub("^rom_", "")
    name = name:gsub("^dei_", "")
    -- Replace underscores with spaces
    name = name:gsub("_", " ")
    -- Capitalize first letter of each word
    name = name:gsub("(%a)([%w]*)", function(first, rest)
        return first:upper() .. rest
    end)
    return name
end

-- ============================================================================
-- COALITION - MAINTENANCE
-- ============================================================================

local function DissolveCoalition(coal_index, reason)
    local coal = active_coalitions[coal_index]
    if not coal then return end

    Log("COALITION DISSOLVING: [" .. table.concat(coal.members, ", ") .. "] vs " .. coal.threat_key .. " (" .. reason .. ")")

    for _, member_key in ipairs(coal.members) do
        pcall(function()
            scripting.game_interface:force_diplomacy(member_key, coal.threat_key, "peace", true, true)
            scripting.game_interface:force_diplomacy(coal.threat_key, member_key, "peace", true, true)
        end)
        pcall(function()
            cm:force_make_peace(member_key, coal.threat_key)
        end)
        Log("COALITION PEACE: " .. member_key .. " <-> " .. coal.threat_key)
        coalition_war_overrides[member_key] = nil
    end

    -- Peace cascades to threat's client states — they fought alongside their overlord
    local threat_clients = GetClientStates(coal.threat_key)
    for _, client_key in ipairs(threat_clients) do
        for _, member_key in ipairs(coal.members) do
            pcall(function()
                scripting.game_interface:force_diplomacy(member_key, client_key, "peace", true, true)
                scripting.game_interface:force_diplomacy(client_key, member_key, "peace", true, true)
            end)
            pcall(function()
                cm:force_make_peace(member_key, client_key)
            end)
            Log("COALITION PEACE: " .. member_key .. " <-> " .. client_key .. " (client state of " .. coal.threat_key .. ")")
        end
    end

    -- ========== UI NOTIFICATION HOOK ==========
    if IsHumanFaction(coal.threat_key) then
        -- Build dissolution popup text with member names
        local clean_names = {}
        for _, member_key in ipairs(coal.members) do
            table.insert(clean_names, CleanFactionName(member_key))
        end
        local display_names = table.concat(clean_names, ", ")

        coalition_dissolved_text = "You have beaten back the forces that combined to keep you at bay!\n\n"
            .. "The following factions have abandoned their coalition:\n"
            .. display_names .. "\n\n"
            .. "Their resolve has crumbled. Now, march your armies onward!"
        coalition_dissolved_fired = false

        coalition_notify_members = ""
        Log("COALITION UI: Queued dissolution popup and cleared dynamic text")
    end
    Log("*** COALITION DISSOLVED: Coalition against " .. coal.threat_key .. " has been dissolved! (" .. reason .. ") ***")
    -- ==========================================

    -- Start cooldown now (after dissolution, not formation)
    local current_turn = scripting.game_interface:model():turn_number()
    coalition_cooldowns[coal.threat_key] = current_turn
    Log("COALITION: Cooldown started for " .. coal.threat_key .. " (" .. COALITION_COOLDOWN .. " turns)")

    table.remove(active_coalitions, coal_index)
end

local function CheckCoalitionDissolution()
    for i = #active_coalitions, 1, -1 do
        local coal = active_coalitions[i]
        local threat_key = coal.threat_key

        local peace_count = 0
        for _, member_key in ipairs(coal.members) do
            if not IsFactionAlive(member_key) or not AreAtWar(threat_key, member_key) then
                peace_count = peace_count + 1
            end
        end

        local dissolve_threshold = math.ceil(#coal.members * COALITION_DISSOLVE_RATIO)

        if peace_count >= dissolve_threshold then
            DissolveCoalition(i, "peace with " .. peace_count .. "/" .. #coal.members .. " members (threshold: " .. dissolve_threshold .. ")")
        end
    end
end

local function CheckPeaceLocks(turn)
    for _, coal in ipairs(active_coalitions) do
        if coal.peace_lock_until > 0 and turn >= coal.peace_lock_until then
            for _, member_key in ipairs(coal.members) do
                pcall(function()
                    scripting.game_interface:force_diplomacy(member_key, coal.threat_key, "peace", true, true)
                    scripting.game_interface:force_diplomacy(coal.threat_key, member_key, "peace", true, true)
                end)
            end
            coal.peace_lock_until = 0
            Log("COALITION: Peace UNLOCKED for coalition vs " .. coal.threat_key)
        end
    end
end

-- ============================================================================
-- COALITION - SNAPSHOT & EVALUATION
-- ============================================================================

local function TakeCoalitionSnapshot()
    local turn = scripting.game_interface:model():turn_number()
    coalition_snapshots = {}
    pcall(function()
        local flist = scripting.game_interface:model():world():faction_list()
        for i = 0, flist:num_items() - 1 do
            local fac = flist:item_at(i)
            local fkey = fac:name()
            if not IsSlaveFaction(fkey) and fac:has_home_region() then
                local count = fac:region_list():num_items()
                if count > 0 then
                    coalition_snapshots[fkey] = count
                end
            end
        end
    end)
    coalition_snapshot_turn = turn
    Log("COALITION: Snapshot taken on turn " .. turn)
end

local function EvaluateCoalitions()
    if not COALITION_ENABLED then return end

    local turn = scripting.game_interface:model():turn_number()

    -- always check dissolution and peace locks
    CheckCoalitionDissolution()
    CheckPeaceLocks(turn)

    -- first ever call: just snapshot
    if coalition_snapshot_turn == 0 or not next(coalition_snapshots) then
        TakeCoalitionSnapshot()
        return
    end

    local turns_since = turn - coalition_snapshot_turn
    if turns_since < COALITION_CHECK_DELTA then return end

    if turn < COALITION_MIN_TURN then
        TakeCoalitionSnapshot()
        return
    end

    Log("COALITION: Evaluating threat (turn " .. coalition_snapshot_turn .. " -> " .. turn .. ")")

    -- Decay all existing threat scores
    for fkey, score in pairs(faction_threat_scores) do
        faction_threat_scores[fkey] = score * (1 - THREAT_DECAY)
        if faction_threat_scores[fkey] < 0.5 then
            faction_threat_scores[fkey] = nil
        end
    end

    -- Gather world averages (only 3+ region factions count toward averages)
    local total_size = 0
    local total_growth = 0
    local faction_count = 0
    local world_data = {}

    pcall(function()
        local flist = scripting.game_interface:model():world():faction_list()
        for i = 0, flist:num_items() - 1 do
            local fac = flist:item_at(i)
            local fkey = fac:name()
            if not IsSlaveFaction(fkey) and fac:has_home_region() then
                local current_count = fac:region_list():num_items()
                if current_count > 0 then
                    local baseline = coalition_snapshots[fkey] or current_count
                    local growth_regions = math.max(0, current_count - baseline)
                    world_data[fkey] = {size = current_count, growth = growth_regions, is_human = fac:is_human()}
                    if current_count >= 3 then
                        total_size = total_size + current_count
                        total_growth = total_growth + growth_regions
                        faction_count = faction_count + 1
                    end
                end
            end
        end
    end)

    if faction_count < 2 then
        TakeCoalitionSnapshot()
        return
    end

    local avg_size = total_size / faction_count
    local avg_growth = math.max(total_growth / faction_count, 0.3)

    Log("COALITION WORLD: " .. faction_count .. " factions (3+), avg_size=" .. string.format("%.1f", avg_size)
        .. " avg_growth=" .. string.format("%.2f", avg_growth))

    -- Calculate threat relative to world averages
    local threats = {}

    for fkey, wd in pairs(world_data) do
        local dominated = false

        if not COALITION_INCLUDE_HUMAN and wd.is_human then dominated = true end
        if not dominated and IsInAnyCoalition(fkey) then dominated = true end
        if not dominated and wd.size < COALITION_MIN_REGIONS then dominated = true end

        local cd = coalition_cooldowns[fkey] or 0
        if not dominated and cd > 0 and (turn - cd) < COALITION_COOLDOWN then
            dominated = true
        end

        if not dominated then
            local growth_component = 0
            local size_component = 0

            if wd.growth > 0 then
                if avg_growth > 0 then
                    local growth_ratio = math.min(wd.growth / avg_growth, THREAT_GROWTH_RATIO_CAP)
                    if growth_ratio > 1.0 then
                        growth_component = (growth_ratio - 1.0) * THREAT_GROWTH_WEIGHT
                    end
                else
                    growth_component = math.min(wd.growth, THREAT_GROWTH_RATIO_CAP) * THREAT_GROWTH_WEIGHT
                end
            end

            if avg_size > 0 then
                local size_ratio = math.min(wd.size / avg_size, THREAT_SIZE_RATIO_CAP)
                if size_ratio > 1.0 then
                    size_component = (size_ratio - 1.0) * THREAT_SIZE_WEIGHT
                end
            end

            local threat_gain = growth_component + size_component

            if threat_gain > 0 then
                local old_score = faction_threat_scores[fkey] or 0
                local new_score = old_score + threat_gain
                faction_threat_scores[fkey] = new_score

                Log("COALITION THREAT: " .. fkey
                    .. " size=" .. wd.size .. " (avg " .. string.format("%.1f", avg_size) .. ")"
                    .. " growth=+" .. wd.growth .. " (avg " .. string.format("%.2f", avg_growth) .. ")"
                    .. " | g=" .. string.format("%.1f", growth_component)
                    .. " s=" .. string.format("%.1f", size_component)
                    .. " | " .. math.floor(old_score) .. " -> " .. math.floor(new_score))

                if new_score >= THREAT_SEVERE_THRESHOLD then
                    local size_roll = math.random()
                    local t_min, t_max
                    if new_score >= THREAT_SEVERE_THRESHOLD * 1.5 then
                        t_min = 3
                        t_max = (size_roll < 0.4) and 4 or 5
                    elseif new_score >= THREAT_SEVERE_THRESHOLD * 1.2 then
                        t_min = 3
                        t_max = (size_roll < 0.7) and 4 or 5
                    else
                        t_min = 2
                        t_max = (size_roll < 0.5) and 3 or 4
                    end
                    table.insert(threats, {key = fkey, growth = new_score, level = 2, is_human = wd.is_human, target_min = t_min, target_max = t_max})
                    Log("COALITION: " .. fkey .. " SEVERE (threat=" .. math.floor(new_score) .. ") -> target " .. t_min .. "-" .. t_max .. " members")
                elseif new_score >= THREAT_MILD_THRESHOLD then
                    local size_roll = math.random()
                    local t_min = 2
                    local t_max
                    if new_score >= THREAT_MILD_THRESHOLD * 1.4 then
                        t_max = (size_roll < 0.6) and 3 or 4
                    else
                        t_max = (size_roll < 0.8) and 2 or 3
                    end
                    table.insert(threats, {key = fkey, growth = new_score, level = 1, is_human = wd.is_human, target_min = t_min, target_max = t_max})
                    Log("COALITION: " .. fkey .. " MILD (threat=" .. math.floor(new_score) .. ") -> target " .. t_min .. "-" .. t_max .. " members")
                end
            end
        end
    end

    table.sort(threats, function(a, b) return a.growth > b.growth end)

    local formed_this_cycle = false
    for _, threat in ipairs(threats) do
        if formed_this_cycle then
            Log("COALITION: Deferring " .. threat.key .. " (threat=" .. math.floor(threat.growth) .. ") to next turn - already formed one this cycle")
            break
        end

        -- check coalition limits based on target type
        local at_limit = false
        if threat.is_human then
            if CountPlayerCoalitions() >= COALITION_MAX_ACTIVE_VS_PLAYER then
                at_limit = true
                Log("COALITION: Already at max player coalitions (" .. COALITION_MAX_ACTIVE_VS_PLAYER .. ") - skipping " .. threat.key)
            end
        else
            if CountAICoalitions() >= COALITION_MAX_ACTIVE_VS_AI then
                at_limit = true
                Log("COALITION: Already at max AI coalitions (" .. COALITION_MAX_ACTIVE_VS_AI .. ") - skipping " .. threat.key)
            end
        end

        if not at_limit then
            local candidates
            if threat.level >= 2 then
                candidates = GetExtendedNeighbors(threat.key)
            else
                candidates = GetNeighborFactions(threat.key)
            end

            local members = BuildCoalitionMembers(threat.key, candidates, threat.target_min, threat.target_max)
            if members then
                -- Probability gate: 1st coalition is guaranteed, 2nd+ rolls random 45-85%
                local prior_count = coalition_formation_counts[threat.key] or 0
                local should_form = true

                if prior_count > 0 then
                    local form_chance = COALITION_FORM_CHANCE_MIN + (math.random() * (COALITION_FORM_CHANCE_MAX - COALITION_FORM_CHANCE_MIN))
                    local roll = math.random()

                    if roll > form_chance then
                        should_form = false
                        Log("COALITION: Formation vs " .. threat.key .. " FAILED probability gate (roll=" .. string.format("%.2f", roll)
                            .. " needed<" .. string.format("%.2f", form_chance) .. ", prior=" .. prior_count .. ")")
                        coalition_cooldowns[threat.key] = turn
                    else
                        Log("COALITION: Formation vs " .. threat.key .. " PASSED (roll=" .. string.format("%.2f", roll)
                            .. " needed<" .. string.format("%.2f", form_chance) .. ", prior=" .. prior_count .. ")")
                    end
                end

                if should_form then
                    local old_threat = faction_threat_scores[threat.key] or 0
                    faction_threat_scores[threat.key] = old_threat * THREAT_POST_TRIGGER
                    Log("COALITION THREAT: " .. threat.key .. " reduced after trigger: " .. math.floor(old_threat) .. " -> " .. math.floor(old_threat * THREAT_POST_TRIGGER))

                    coalition_formation_counts[threat.key] = prior_count + 1

                    if IsHumanFaction(threat.key) then
                        table.insert(pending_player_coalitions, {threat_key = threat.key, members = members, turn = turn})
                        Log("COALITION: Queued coalition vs " .. threat.key .. " [" .. table.concat(members, ", ") .. "] for player turn start")
                    else
                        FormCoalition(threat.key, members, turn)
                    end
                    formed_this_cycle = true
                end
            else
                Log("COALITION: Could not form vs " .. threat.key .. " (not enough valid members)")
                coalition_cooldowns[threat.key] = turn
            end
        end
    end

    TakeCoalitionSnapshot()
end

-- ============================================================================
-- COALITION - SAVE / LOAD
-- ============================================================================

local function SaveCoalitionData(context)
    if not COALITION_ENABLED then return end

    scripting.game_interface:save_named_value("_coalition_snapshot_turn", coalition_snapshot_turn, context)

    local snap_count = 0
    for k, v in pairs(coalition_snapshots) do
        scripting.game_interface:save_named_value("_coalition_snap_key_" .. snap_count, k, context)
        scripting.game_interface:save_named_value("_coalition_snap_val_" .. snap_count, v, context)
        snap_count = snap_count + 1
    end
    scripting.game_interface:save_named_value("_coalition_snap_count", snap_count, context)

    local cd_count = 0
    for k, v in pairs(coalition_cooldowns) do
        scripting.game_interface:save_named_value("_coalition_cd_key_" .. cd_count, k, context)
        scripting.game_interface:save_named_value("_coalition_cd_val_" .. cd_count, v, context)
        cd_count = cd_count + 1
    end
    scripting.game_interface:save_named_value("_coalition_cd_count", cd_count, context)

    local fc_count = 0
    for k, v in pairs(coalition_formation_counts) do
        scripting.game_interface:save_named_value("_coalition_fc_key_" .. fc_count, k, context)
        scripting.game_interface:save_named_value("_coalition_fc_val_" .. fc_count, v, context)
        fc_count = fc_count + 1
    end
    scripting.game_interface:save_named_value("_coalition_fc_count", fc_count, context)

    local ts_count = 0
    for k, v in pairs(faction_threat_scores) do
        scripting.game_interface:save_named_value("_coalition_ts_key_" .. ts_count, k, context)
        scripting.game_interface:save_named_value("_coalition_ts_val_" .. ts_count, math.floor(v * 100), context)
        ts_count = ts_count + 1
    end
    scripting.game_interface:save_named_value("_coalition_ts_count", ts_count, context)

    scripting.game_interface:save_named_value("_coalition_active_count", #active_coalitions, context)
    for i, coal in ipairs(active_coalitions) do
        local prefix = "_coalition_" .. i .. "_"
        scripting.game_interface:save_named_value(prefix .. "threat", coal.threat_key, context)
        scripting.game_interface:save_named_value(prefix .. "formed", coal.formed_turn, context)
        scripting.game_interface:save_named_value(prefix .. "peacelock", coal.peace_lock_until, context)
        scripting.game_interface:save_named_value(prefix .. "isai", coal.is_ai_target and 1 or 0, context)
        scripting.game_interface:save_named_value(prefix .. "membercount", #coal.members, context)
        for j, member in ipairs(coal.members) do
            scripting.game_interface:save_named_value(prefix .. "member_" .. j, member, context)
        end
    end

    Log("COALITION SAVE: " .. snap_count .. " snapshots, " .. cd_count .. " cooldowns, " .. fc_count .. " formation counts, " .. ts_count .. " threats, " .. #active_coalitions .. " coalitions")
end

local function LoadCoalitionData(context)
    if not COALITION_ENABLED then return end

    coalition_snapshot_turn = scripting.game_interface:load_named_value("_coalition_snapshot_turn", 0, context)

    coalition_snapshots = {}
    local snap_count = scripting.game_interface:load_named_value("_coalition_snap_count", 0, context)
    for i = 0, snap_count - 1 do
        local k = scripting.game_interface:load_named_value("_coalition_snap_key_" .. i, "", context)
        local v = scripting.game_interface:load_named_value("_coalition_snap_val_" .. i, 0, context)
        if k ~= "" then coalition_snapshots[k] = v end
    end

    coalition_cooldowns = {}
    local cd_count = scripting.game_interface:load_named_value("_coalition_cd_count", 0, context)
    for i = 0, cd_count - 1 do
        local k = scripting.game_interface:load_named_value("_coalition_cd_key_" .. i, "", context)
        local v = scripting.game_interface:load_named_value("_coalition_cd_val_" .. i, 0, context)
        if k ~= "" then coalition_cooldowns[k] = v end
    end

    coalition_formation_counts = {}
    local fc_count = scripting.game_interface:load_named_value("_coalition_fc_count", 0, context)
    for i = 0, fc_count - 1 do
        local k = scripting.game_interface:load_named_value("_coalition_fc_key_" .. i, "", context)
        local v = scripting.game_interface:load_named_value("_coalition_fc_val_" .. i, 0, context)
        if k ~= "" and v > 0 then coalition_formation_counts[k] = v end
    end

    faction_threat_scores = {}
    local ts_count = scripting.game_interface:load_named_value("_coalition_ts_count", 0, context)
    for i = 0, ts_count - 1 do
        local k = scripting.game_interface:load_named_value("_coalition_ts_key_" .. i, "", context)
        local v = scripting.game_interface:load_named_value("_coalition_ts_val_" .. i, 0, context)
        if k ~= "" and v > 0 then faction_threat_scores[k] = v / 100 end
    end

    active_coalitions = {}
    local coal_count = scripting.game_interface:load_named_value("_coalition_active_count", 0, context)
    for i = 1, coal_count do
        local prefix = "_coalition_" .. i .. "_"
        local threat = scripting.game_interface:load_named_value(prefix .. "threat", "", context)
        local formed = scripting.game_interface:load_named_value(prefix .. "formed", 0, context)
        local peacelock = scripting.game_interface:load_named_value(prefix .. "peacelock", 0, context)
        local isai_val = scripting.game_interface:load_named_value(prefix .. "isai", 0, context)
        local membercount = scripting.game_interface:load_named_value(prefix .. "membercount", 0, context)

        if threat ~= "" and membercount > 0 then
            local members = {}
            for j = 1, membercount do
                local m = scripting.game_interface:load_named_value(prefix .. "member_" .. j, "", context)
                if m ~= "" then table.insert(members, m) end
            end
            if #members > 0 then
                table.insert(active_coalitions, {
                    threat_key = threat,
                    members = members,
                    formed_turn = formed,
                    peace_lock_until = peacelock,
                    is_ai_target = (isai_val == 1)
                })
            end
        end
    end

    coalition_war_overrides = {}
    Log("COALITION LOAD: " .. snap_count .. " snapshots, " .. cd_count .. " cooldowns, " .. fc_count .. " formation counts, " .. ts_count .. " threats, " .. #active_coalitions .. " coalitions")
end

local function ReapplyCoalitionEffects()
    local turn = scripting.game_interface:model():turn_number()
    for _, coal in ipairs(active_coalitions) do
        Log("COALITION: Reapplying effects vs " .. coal.threat_key .. " after load")

        if IsHumanFaction(coal.threat_key) then
            for _, member_key in ipairs(coal.members) do
                coalition_war_overrides[member_key] = true
                pcall(function()
                    scripting.game_interface:force_diplomacy(member_key, coal.threat_key, "war", true, true)
                end)
            end
            -- Restore UI text injection data
            coalition_notify_members = table.concat(coal.members, ", ")
            Log("COALITION: Restored UI text data for player coalition")
        end

        -- reapply bitter enemies
       -- SetBitterEnemies(coal.members, coal.threat_key)

        if coal.peace_lock_until > 0 and turn < coal.peace_lock_until then
            for _, member_key in ipairs(coal.members) do
                pcall(function()
                    scripting.game_interface:force_diplomacy(member_key, coal.threat_key, "peace", false, false)
                    scripting.game_interface:force_diplomacy(coal.threat_key, member_key, "peace", false, false)
                end)
            end
        end

        for i, member_a in ipairs(coal.members) do
            for j, member_b in ipairs(coal.members) do
                if i ~= j then
                    pcall(function()
                        scripting.game_interface:force_diplomacy(member_a, member_b, "defensive alliance", true, true)
                        scripting.game_interface:force_diplomacy(member_a, member_b, "military alliance", true, true)
                    end)
                end
            end
        end
    end
end

-- ============================================================================
-- DISTANCE BLOCKING
-- ============================================================================

local function GetDistToHuman(ai_faction)
    local min_dist = 99999
    local ai_regions = ai_faction:region_list()

    if ai_regions:num_items() == 0 then
        local forces = ai_faction:military_force_list()
        if forces:num_items() == 0 then return min_dist end
        for i = 0, forces:num_items() - 1 do
            local force = forces:item_at(i)
            if force:is_army() and force:has_general() then
                local gen = force:general_character()
                local ax, ay = gen:logical_position_x(), gen:logical_position_y()
                for _, hkey in ipairs(human_factions) do
                    local hfac = scripting.game_interface:model():world():faction_by_key(hkey)
                    if hfac then
                        local hregs = hfac:region_list()
                        for j = 0, hregs:num_items() - 1 do
                            local s = hregs:item_at(j):settlement()
                            local d = Dist(ax, ay, s:logical_position_x(), s:logical_position_y())
                            if d < min_dist then min_dist = d end
                        end
                    end
                end
            end
        end
        return min_dist
    end

    for i = 0, ai_regions:num_items() - 1 do
        local as = ai_regions:item_at(i):settlement()
        local ax, ay = as:logical_position_x(), as:logical_position_y()
        for _, hkey in ipairs(human_factions) do
            local hfac = scripting.game_interface:model():world():faction_by_key(hkey)
            if hfac then
                local hregs = hfac:region_list()
                for j = 0, hregs:num_items() - 1 do
                    local hs = hregs:item_at(j):settlement()
                    local d = Dist(ax, ay, hs:logical_position_x(), hs:logical_position_y())
                    if d < min_dist then min_dist = d end
                end
            end
        end
    end
    return min_dist
end

local function BlockWar(ai_key)
    for _, hkey in ipairs(human_factions) do
        pcall(function()
            scripting.game_interface:force_diplomacy(ai_key, hkey, "war", false, false)
        end)
        Log("BLOCKED: " .. ai_key .. " -> " .. hkey)
    end
    blocked_factions[ai_key] = true
end

local function EnableWar(ai_key)
    for _, hkey in ipairs(human_factions) do
        pcall(function()
            scripting.game_interface:force_diplomacy(ai_key, hkey, "war", true, true)
        end)
        Log("ENABLED: " .. ai_key .. " -> " .. hkey)
    end
    blocked_factions[ai_key] = false
end

-- ============================================================================
-- MAIN PER-FACTION CHECK
-- ============================================================================

local last_turn = 0
local checks, blocked, allowed = 0, 0, 0
local coalition_reapplied_after_load = false

local function CheckFaction(ai_faction)
    local ai_key = ai_faction:name()
    local turn = scripting.game_interface:model():turn_number()

    if turn > last_turn then
        if last_turn > 0 then
            Log("TURN " .. last_turn .. " SUMMARY: " .. checks .. " checked | " .. blocked .. " blocked, " .. allowed .. " allowed | coalitions: " .. #active_coalitions)
        end
        last_turn = turn
        checks, blocked, allowed = 0, 0, 0
        coalition_checked_this_turn = false
    end

    if not coalition_checked_this_turn then
        coalition_checked_this_turn = true
        if not coalition_reapplied_after_load then
            coalition_reapplied_after_load = true
            ReapplyCoalitionEffects()
        end
        local ok_c, err_c = pcall(EvaluateCoalitions)
        if not ok_c then Log("COALITION ERROR: " .. tostring(err_c)) end
    end

    local prev = last_calc[ai_key] or 0
    if (turn - prev) < RECALC_FREQUENCY then return end
    last_calc[ai_key] = turn
    checks = checks + 1

    CheckCascadePeace(ai_faction)
    CheckClientStateGrowth(ai_faction)

    local dist = GetDistToHuman(ai_faction)
    local is_blocked = blocked_factions[ai_key] or false

    if dist > WAR_DISTANCE_THRESHOLD then
        if coalition_war_overrides[ai_key] then
            if is_blocked then
                EnableWar(ai_key)
                Log(ai_key .. " is FAR (dist=" .. math.floor(dist) .. ") but COALITION OVERRIDE active")
            end
            allowed = allowed + 1
        else
            blocked = blocked + 1
            if not is_blocked then
                BlockWar(ai_key)
                Log(ai_key .. " is FAR (dist=" .. math.floor(dist) .. ") - WAR BLOCKED")
            end
        end
    else
        allowed = allowed + 1
        if is_blocked then
            EnableWar(ai_key)
            Log(ai_key .. " is CLOSE (dist=" .. math.floor(dist) .. ") - WAR ENABLED")
        end
    end
end

-- ============================================================================
-- EVENTS
-- ============================================================================

local coalition_ui_pending = false  -- set after event fires, inject text on player turn

-- Navigate UI component tree using string-based Find
local function FindUIComponent(parent, ...)
    local args = {...}
    local current = parent
    for i = 1, #args do
        local ok, child = pcall(function() return UIComponent(current:Find(args[i])) end)
        if not ok or not child then
            Log("COALITION UI: Could not find '" .. args[i] .. "' at depth " .. i)
            return nil
        end
        current = child
    end
    return current
end

local cached_ui_root = nil  -- cached after first successful discovery

-- Try to capture UI root early via UICreated event (same method ConsulScriptum uses)
pcall(function()
    if events and events.UICreated then
        table.insert(events.UICreated, function(context)
            if context and context.component then
                cached_ui_root = UIComponent(context.component)
                Log("COALITION UI: Captured root via UICreated event!")
            end
        end)
        Log("COALITION UI: Registered UICreated listener for root capture")
    else
        Log("COALITION UI: 'events' table not available - will try other methods at runtime")
    end
end)

local function TryInjectCoalitionText()
    if coalition_notify_members == "" and coalition_ai_notify_text == "" and coalition_dissolved_text == "" then return end

    local ok_ui, err_ui = pcall(function()
        local ui_root = cached_ui_root

        -- Method 1: Already cached from UICreated (best case)
        if ui_root then
            -- Validate it still works
            local ok_v, _ = pcall(function() return ui_root:Id() end)
            if not ok_v then
                Log("COALITION UI: Cached root is stale, clearing")
                ui_root = nil
                cached_ui_root = nil
            end
        end

        -- Method 2: Walk up from a known component using Parent()
        -- (same technique ConsulScriptum uses in battle: layout:Parent() = root)
        if not ui_root then
            local ok_walk, result_walk = pcall(function()
                -- "events" is a known UI component visible when our popup is open
                -- We grab it and walk up to root via Parent()
                local events_comp = nil

                -- Try finding "events" component through the scripting interface
                if scripting and scripting.game_interface then
                    -- Some TW games expose ui_component on game_interface
                    local ok_gi, gi_result = pcall(function()
                        return UIComponent(scripting.game_interface:ui_component("events"))
                    end)
                    if ok_gi and gi_result then
                        events_comp = gi_result
                    end
                end

                if events_comp then
                    -- Walk up: events -> root (or events -> layout -> root)
                    local current = events_comp
                    for safety = 1, 10 do
                        local ok_p, parent = pcall(function() return UIComponent(current:Parent()) end)
                        if not ok_p or not parent then break end
                        local ok_id, pid = pcall(function() return parent:Id() end)
                        if not ok_id then break end
                        if pid == "root" or pid == "" then
                            return parent
                        end
                        current = parent
                    end
                    -- If we couldn't identify root by name, the topmost parent is root
                    return current
                end
                return nil
            end)
            if ok_walk and result_walk then
                ui_root = result_walk
                cached_ui_root = ui_root
                Log("COALITION UI: Got root via Parent() walk-up")
            end
        end

        -- Method 3: core:get_ui_root()
        if not ui_root then
            local ok3, result3 = pcall(function() return core:get_ui_root() end)
            if ok3 and result3 then
                ui_root = result3
                cached_ui_root = ui_root
                Log("COALITION UI: Got root via core:get_ui_root()")
            end
        end

        -- Method 4: effect.get_ui_root()
        if not ui_root then
            local ok4, result4 = pcall(function() return UIComponent(effect.get_ui_root()) end)
            if ok4 and result4 then
                ui_root = result4
                cached_ui_root = ui_root
                Log("COALITION UI: Got root via effect.get_ui_root()")
            end
        end

        -- Method 5: find_uicomponent global
        if not ui_root and find_uicomponent then
            local ok5, result5 = pcall(function() return find_uicomponent("root") end)
            if ok5 and result5 then
                ui_root = result5
                cached_ui_root = ui_root
                Log("COALITION UI: Got root via find_uicomponent('root')")
            end
        end

        -- Method 6: ConsulScriptum fallback
        if not ui_root then
            if consul and consul.ui and consul.ui._UIRoot then
                ui_root = consul.ui._UIRoot
                cached_ui_root = ui_root
                Log("COALITION UI: Got root via consul.ui._UIRoot (fallback)")
            end
        end

        if not ui_root then
            Log("COALITION UI: ALL methods failed - no UI root found")
            return
        end

        -- Navigate: events > event_standard > list_container > descr_textview > dy_descr_text
        local dy_descr = FindUIComponent(ui_root,
            "events", "event_standard", "list_container", "descr_textview", "dy_descr_text")

        if dy_descr then
            -- Check title to determine which coalition event this is
            local tx_title = FindUIComponent(ui_root, "events", "tx_title")
            local title_text = ""
            if tx_title then
                title_text = tx_title:GetStateText() or ""
            end

            local is_player_coalition = string.find(title_text, "AGAINST YOU")
            local is_ai_coalition = string.find(title_text, "AI COALITION")
            local is_dissolved = string.find(title_text, "DISSOLVED")

            if is_player_coalition and coalition_notify_members ~= "" then
                -- PLAYER COALITION: split members into at-war vs peace-achieved
                local at_war_names = {}
                local peace_names = {}
                local destroyed_names = {}
                local player_key = nil
                for _, coal in ipairs(active_coalitions) do
                    if IsHumanFaction(coal.threat_key) then
                        player_key = coal.threat_key
                        break
                    end
                end

                for name in coalition_notify_members:gmatch("([^,]+)") do
                    name = name:match("^%s*(.-)%s*$")
                    local clean = CleanFactionName(name)
                    if not IsFactionAlive(name) then
                        table.insert(destroyed_names, clean)
                    elseif coalition_new_formation then
                        -- New formation: wars may not be in treaty_details yet, treat all living members as at-war
                        table.insert(at_war_names, clean)
                    elseif player_key and not AreAtWar(player_key, name) then
                        table.insert(peace_names, clean)
                    else
                        table.insert(at_war_names, clean)
                    end
                end
                coalition_new_formation = false  -- clear after first text build

                local turns_left = 0
                local current_turn = scripting.game_interface:model():turn_number()
                for _, coal in ipairs(active_coalitions) do
                    if IsHumanFaction(coal.threat_key) then
                        if coal.peace_lock_until > 0 and current_turn < coal.peace_lock_until then
                            turns_left = coal.peace_lock_until - current_turn
                        end
                        break
                    end
                end

                -- Find dissolve threshold for progress display
                -- destroyed factions count toward progress (no longer a threat)
                local total_members = #at_war_names + #peace_names + #destroyed_names
                local dissolve_threshold = math.ceil(total_members * COALITION_DISSOLVE_RATIO)
                local progress = #peace_names + #destroyed_names

                local dynamic_text = ""
                if turns_left > 0 then
                    dynamic_text = "A coalition has formed against you!\n\n"
                        .. "Enemies: " .. table.concat(at_war_names, ", ") .. "\n"
                    if #destroyed_names > 0 then
                        dynamic_text = dynamic_text .. "Destroyed: " .. table.concat(destroyed_names, ", ") .. "\n"
                    end
                    if #peace_names > 0 then
                        dynamic_text = dynamic_text .. "Peace achieved: " .. table.concat(peace_names, ", ") .. "\n"
                    end
                    dynamic_text = dynamic_text .. "\n"
                        .. "Peace LOCKED for " .. turns_left .. " more turn" .. (turns_left > 1 and "s" or "") .. "!\n\n"
                    if progress > 0 then
                        dynamic_text = dynamic_text
                            .. "Progress: " .. progress .. "/" .. dissolve_threshold .. " needed to disband\n"
                    end
                    dynamic_text = dynamic_text
                        .. "Achieve peace with HALF to DISBAND the coalition!"
                else
                    dynamic_text = "The coalition against you persists!\n\n"
                    if #at_war_names > 0 then
                        dynamic_text = dynamic_text .. "Still at war: " .. table.concat(at_war_names, ", ") .. "\n"
                    end
                    if #destroyed_names > 0 then
                        dynamic_text = dynamic_text .. "Destroyed: " .. table.concat(destroyed_names, ", ") .. "\n"
                    end
                    if #peace_names > 0 then
                        dynamic_text = dynamic_text .. "Peace achieved: " .. table.concat(peace_names, ", ") .. "\n"
                    end
                    dynamic_text = dynamic_text .. "\n"
                        .. "Peace is now available!\n"
                    if progress > 0 then
                        dynamic_text = dynamic_text
                            .. "Progress: " .. progress .. "/" .. dissolve_threshold .. " needed to disband\n"
                    end
                    dynamic_text = dynamic_text
                        .. "Achieve peace with HALF to DISBAND the coalition!"
                end

                dy_descr:SetStateText(dynamic_text)
                local all_names = table.concat(at_war_names, ", ")
                if #peace_names > 0 then all_names = all_names .. " | peace: " .. table.concat(peace_names, ", ") end
                if #destroyed_names > 0 then all_names = all_names .. " | dead: " .. table.concat(destroyed_names, ", ") end
                Log("COALITION UI: Injected PLAYER text (" .. turns_left .. " turns left): " .. all_names)

            elseif is_ai_coalition and coalition_ai_notify_text ~= "" then
                -- AI COALITION: show the pre-built text
                dy_descr:SetStateText(coalition_ai_notify_text)
                Log("COALITION UI: Injected AI coalition text")

            elseif is_dissolved and coalition_dissolved_text ~= "" then
                -- DISSOLUTION: show the pre-built text, then clear it (one-time)
                dy_descr:SetStateText(coalition_dissolved_text)
                Log("COALITION UI: Injected dissolution text")

            else
                if title_text ~= "" then
                    Log("COALITION UI: Panel is not a coalition event (title: " .. title_text .. ") - skipping")
                end
            end
        else
            Log("COALITION UI: Could not navigate to dy_descr_text component")
        end
    end)
    if not ok_ui then
        Log("COALITION UI: injection failed: " .. tostring(err_ui))
    end
end

-- Listen for panel open events to catch the message event popup
local panel_listener_registered = false

local function OnFactionTurn(context)
    local fac = context:faction()

    -- Register panel listener once (needs scripting to be available)
    if not panel_listener_registered then
        panel_listener_registered = true

        -- Try to capture root from ANY UI click (ComponentLClickUp)
        if not cached_ui_root then
            pcall(function()
                scripting.AddEventCallBack("ComponentLClickUp", function(click_context)
                    if cached_ui_root then return end  -- already got it
                    pcall(function()
                        if click_context and click_context.component then
                            local current = UIComponent(click_context.component)
                            for safety = 1, 20 do
                                local ok_p, parent = pcall(function() return UIComponent(current:Parent()) end)
                                if not ok_p or not parent then
                                    cached_ui_root = current
                                    Log("COALITION UI: Captured root via ComponentLClickUp walk-up!")
                                    return
                                end
                                current = parent
                            end
                            -- If we walked 20 levels, topmost is probably root
                            cached_ui_root = current
                            Log("COALITION UI: Captured root via ComponentLClickUp (max depth)")
                        end
                    end)
                end)
                Log("COALITION UI: ComponentLClickUp listener registered for root capture")
            end)
        end

        local ok_panel, _ = pcall(function()
            scripting.AddEventCallBack("PanelOpenedCampaign", function(panel_context)
                -- Try to capture UI root from context if we don't have it yet
                if not cached_ui_root and panel_context then
                    pcall(function()
                        if panel_context.component then
                            -- Walk up from the context component to find root
                            local current = UIComponent(panel_context.component)
                            for safety = 1, 20 do
                                local ok_p, parent = pcall(function() return UIComponent(current:Parent()) end)
                                if not ok_p or not parent then
                                    -- current is the topmost = root
                                    cached_ui_root = current
                                    Log("COALITION UI: Captured root via PanelOpenedCampaign context walk-up!")
                                    break
                                end
                                -- Check if parent:Parent() would fail (meaning parent is root)
                                local ok_pp, _ = pcall(function() return UIComponent(parent:Parent()) end)
                                if not ok_pp then
                                    cached_ui_root = parent
                                    Log("COALITION UI: Captured root via PanelOpenedCampaign context walk-up!")
                                    break
                                end
                                current = parent
                            end
                        end
                    end)
                end

                -- Always re-inject if there are active coalition members to display
                if coalition_notify_members ~= "" or coalition_ai_notify_text ~= "" or coalition_dissolved_text ~= "" then
                    Log("COALITION UI: PanelOpenedCampaign fired, re-injecting text")
                    TryInjectCoalitionText()
                end
            end)
            Log("COALITION UI: PanelOpenedCampaign listener registered")
        end)
        if not ok_panel then
            Log("COALITION UI: Could not register PanelOpenedCampaign listener")
        end
    end

    -- On player turn: form any queued coalitions and show notification
    if fac:is_human() and #pending_player_coalitions > 0 then
        for _, pending in ipairs(pending_player_coalitions) do
            FormCoalition(pending.threat_key, pending.members, pending.turn)
            Log("COALITION: Formed queued coalition vs " .. pending.threat_key .. " at player turn start")
        end
        pending_player_coalitions = {}
    end

    -- On player turn: unlock peace if lock has expired (so player can act immediately)
    if fac:is_human() then
        local current_turn = scripting.game_interface:model():turn_number()
        for _, coal in ipairs(active_coalitions) do
            if coal.peace_lock_until > 0 and current_turn >= coal.peace_lock_until then
                for _, member_key in ipairs(coal.members) do
                    pcall(function()
                        scripting.game_interface:force_diplomacy(member_key, coal.threat_key, "peace", true, true)
                        scripting.game_interface:force_diplomacy(coal.threat_key, member_key, "peace", true, true)
                    end)
                end
                coal.peace_lock_until = 0
                Log("COALITION: Peace UNLOCKED on player turn for coalition vs " .. coal.threat_key)
            end
        end
    end

    -- On player turn: clear stale one-shot notification texts from previous turns
    if fac:is_human() then
        if coalition_dissolved_fired then
            coalition_dissolved_text = ""
        end
        if #coalition_ai_notify_queue == 0 then
            coalition_ai_notify_text = ""
        end
    end

    -- On player turn: fire popup after coalition is formed (new coalition)
    local popup_fired_this_turn = false
    if fac:is_human() and coalition_notify_player then
        coalition_notify_player = false
        coalition_ui_pending = true
        popup_fired_this_turn = true
        scripting.game_interface:show_message_event("custom_event_950", 0, 0)
        Log("COALITION: Fired custom_event_950 message event (new coalition, player turn start)")
    end

    -- On player turn: fire recurring popup if coalition still active (not a new formation turn)
    if fac:is_human() and not popup_fired_this_turn and coalition_notify_members ~= "" then
        local has_active_coalition = false
        for _, coal in ipairs(active_coalitions) do
            if IsHumanFaction(coal.threat_key) then
                has_active_coalition = true
                break
            end
        end
        if has_active_coalition then
            coalition_ui_pending = true
            scripting.game_interface:show_message_event("custom_event_950", 0, 0)
            Log("COALITION: Fired recurring custom_event_950 (coalition still active)")
        end
    end

    -- On player turn: fire AI coalition notification if any formed (one-time, not recurring)
    if fac:is_human() and #coalition_ai_notify_queue > 0 then
        -- Build combined text for all AI coalitions that formed this cycle
        local text_parts = {}
        for _, entry in ipairs(coalition_ai_notify_queue) do
            local clean_members = {}
            for name in entry.members:gmatch("([^,]+)") do
                name = name:match("^%s*(.-)%s*$")
                table.insert(clean_members, CleanFactionName(name))
            end
            local target_name = CleanFactionName(entry.threat)
            table.insert(text_parts,
                table.concat(clean_members, ", ") .. "\nTarget: " .. target_name)
        end

        coalition_ai_notify_text = "Rival nations have banded together in pursuit of a common enemy!\n\n"
            .. table.concat(text_parts, "\n\n")
            .. "\n\nKeep an eye on these conflicts — they may shift the balance of power!"

        coalition_ai_notify_queue = {}
        scripting.game_interface:show_message_event("custom_event_951", 0, 0)
        coalition_ui_pending = true
        Log("COALITION: Fired custom_event_951 for AI coalition notification")
    end

    -- On player turn: fire dissolution notification if coalition was dissolved
    if fac:is_human() and coalition_dissolved_text ~= "" and not coalition_dissolved_fired then
        coalition_dissolved_fired = true
        scripting.game_interface:show_message_event("custom_event_952", 0, 0)
        coalition_ui_pending = true
        Log("COALITION: Fired custom_event_952 for coalition dissolution notification")
    end

    -- On player turn: fallback UI text injection if panel event didn't stick
    if fac:is_human() and coalition_ui_pending then
        coalition_ui_pending = false
        Log("COALITION UI: Fallback - trying injection on player turn start")
        TryInjectCoalitionText()
        -- Don't clear coalition_notify_members here - needed for re-opening the notification
    end

    if fac:is_human() then return end
    if not fac:has_home_region() then return end

    if #human_factions == 0 then
        GetHumans()
        if #human_factions == 0 then return end
    end

    local ok, err = pcall(function() CheckFaction(fac) end)
    if not ok then Log("ERROR: " .. tostring(err)) end
end

local function OnSave(context)
    SaveCoalitionData(context)
    Log("game saved")
end

-- track whether we already loaded from save (WorldCreated fires on BOTH new campaign and load)
local loaded_from_save = false

local function OnLoad(context)
    human_factions = {}
    blocked_factions = {}
    last_calc = {}
    coalition_reapplied_after_load = false
    coalition_checked_this_turn = false
    LoadCoalitionData(context)
    loaded_from_save = true
    Log("game loaded - coalition data restored")
end

local function OnNewCampaign(context)
    -- WorldCreated fires on load too - if we already loaded, skip the wipe
    if loaded_from_save then
        loaded_from_save = false
        GetHumans()
        Log("WorldCreated after load - skipping reset, keeping loaded data")
        return
    end
    human_factions = {}
    blocked_factions = {}
    last_calc = {}
    coalition_snapshots = {}
    coalition_snapshot_turn = 0
    coalition_cooldowns = {}
    coalition_war_overrides = {}
    active_coalitions = {}
    coalition_reapplied_after_load = true
    coalition_checked_this_turn = false
    GetHumans()
    Log("campaign started - threshold: " .. WAR_DISTANCE_THRESHOLD
        .. " | coalition: " .. tostring(COALITION_ENABLED)
        .. " (delta=" .. COALITION_CHECK_DELTA
        .. " threat: decay=" .. (THREAT_DECAY*100) .. "% g_w=" .. THREAT_GROWTH_WEIGHT
        .. " s_w=" .. THREAT_SIZE_WEIGHT .. " mild=" .. THREAT_MILD_THRESHOLD
        .. " severe=" .. THREAT_SEVERE_THRESHOLD
        .. " min_turn=" .. COALITION_MIN_TURN
        .. " min=" .. COALITION_MIN_MEMBERS .. " max=" .. COALITION_MAX_MEMBERS .. ")")
end

-- ============================================================================
-- INIT
-- ============================================================================

Log("smart diplomacy loading...")
-- ============================================================================
-- GLOBAL API: Called by population.lua to check if peace is coalition-blocked
-- Returns true if peace between these two factions would violate an active coalition
-- ============================================================================
function IsCoalitionPeaceBlocked(faction_key_a, faction_key_b)
    for _, coal in ipairs(active_coalitions) do
        local threat = coal.threat_key
        local threat_clients = GetClientStates(threat)

        -- Build a set of all "threat side" factions (target + their clients)
        local threat_side = {[threat] = true}
        for _, ck in ipairs(threat_clients) do
            threat_side[ck] = true
        end

        -- Build a set of all coalition members
        local member_side = {}
        for _, mk in ipairs(coal.members) do
            member_side[mk] = true
        end

        -- Check if one faction is on the member side and the other on the threat side
        if (member_side[faction_key_a] and threat_side[faction_key_b])
        or (member_side[faction_key_b] and threat_side[faction_key_a]) then
            Log("COALITION LOCK: Peace blocked between " .. faction_key_a .. " and " .. faction_key_b .. " (active coalition vs " .. threat .. ")")
            return true
        end
    end
    return false
end

scripting.AddEventCallBack("WorldCreated", OnNewCampaign)
scripting.AddEventCallBack("LoadingGame", OnLoad)
scripting.AddEventCallBack("SavingGame", OnSave)
scripting.AddEventCallBack("FactionTurnStart", OnFactionTurn)
Log("smart diplomacy loaded (cascade_peace=" .. tostring(CASCADE_PEACE_ENABLED)
    .. " coalition=" .. tostring(COALITION_ENABLED) .. ")")
