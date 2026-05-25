-- ============================================================
-- SMART ECONOMY v2.0
-- AI Uses Population and More
-- ============================================================
-- SYSTEMS:
-- 1. DISCOVERY: Port factions discover other port factions via
--    shroud reveals. Large empires discover faster and farther.
-- 2. LAND TRADE: Scored & prioritized trade between land neighbors.
-- 3. SEA TRADE: Scored & prioritized trade between discovered
--    port pairs — large factions trade across the world.
-- 4. TRADE BREAKAGE: Dissolves stale/hostile trade agreements.
--
-- All trade pairs are SCORED by economic need, empire size,
-- port infrastructure, diplomatic relations, and war context.
-- Caps scale dynamically with game state.
-- ============================================================

local scripting = require "lua_scripts.EpisodicScripting"

-- ============================================================
-- CONFIG
-- ============================================================

local CFG = {
    -- Discovery clock
    BASE_FACTIONS_PER_TICK       = 5,
    BASE_DISCOVERIES_PER_FACTION = 3,

    -- Large faction discovery bonuses
    LARGE_FACTION_REGIONS        = 3,   -- threshold to count as "large"
    MAJOR_FACTION_REGIONS        = 7,  -- threshold for "major power"
    LARGE_DISCOVERY_BONUS        = 2,   -- extra discoveries per tick for large
    MAJOR_DISCOVERY_BONUS        = 4,   -- extra discoveries per tick for major
    LARGE_FACTION_EXTRA_TICKS    = 2,   -- large factions processed extra times per cycle

    -- Player discovery
    PLAYER_DISCOVERIES_PER_TICK  = 1,   -- port factions revealed to player per tick
    PLAYER_DISCOVERY_INTERVAL    = 10,   -- run player discovery every N turns
    MIN_TURN_PLAYER_DISCOVERY    = 6,   -- player discovery starts earlier than AI

    -- Minimum turns before systems activate
    MIN_TURN_DISCOVERY           = 6,
    MIN_TURN_LAND_TRADE          = 2,
    MIN_TURN_SEA_TRADE           = 5,
    MIN_TURN_BREAKAGE            = 15,

    -- Intervals
    LAND_TRADE_INTERVAL          = 3,
    SEA_TRADE_INTERVAL           = 4,
    BREAKAGE_INTERVAL            = 5,

    -- Base caps (dynamically scaled)
    BASE_LAND_TRADES_PER_CYCLE   = 10,
    BASE_SEA_TRADES_PER_CYCLE    = 3,

    -- Dynamic cap scaling: trades += (alive_factions / divisor)
    LAND_CAP_FACTION_DIVISOR     = 4,
    SEA_CAP_FACTION_DIVISOR      = 8,

    -- Turn-based cap growth: extra trades per N turns elapsed
    CAP_TURN_GROWTH_INTERVAL     = 15,
    LAND_CAP_TURN_BONUS          = 3,
    SEA_CAP_TURN_BONUS           = 2,

    -- Sea trade wait after discovery before eligible
    SEA_TRADE_WAIT_TURNS         = 3,

    -- --------------------------------------------------------
    -- SCORING WEIGHTS (trade pair prioritization)
    -- --------------------------------------------------------
    SCORE_PORT_BONUS             = 30,  -- HEAVY bonus if either has port
    SCORE_BOTH_PORTS_BONUS       = 20,  -- additional if BOTH have ports
    SCORE_EMPIRE_SIZE_WEIGHT     = 2,   -- per region owned (both factions combined)
    SCORE_EMPIRE_LARGE_BONUS     = 15,  -- bonus if either faction >= LARGE threshold
    SCORE_EMPIRE_MAJOR_BONUS     = 25,  -- bonus if either faction >= MAJOR threshold
    SCORE_LOW_TREASURY_BONUS     = 20,  -- if either faction treasury < threshold
    SCORE_LOW_TREASURY_THRESHOLD = 3000,
    SCORE_BROKE_BONUS            = 10,  -- additional if treasury < 0
    SCORE_FEW_TRADES_BONUS       = 15,  -- if either faction has 0 existing trades
    SCORE_SOME_TRADES_BONUS      = 5,   -- if either faction has 1-2 existing trades
    SCORE_ALLY_BONUS             = 20,  -- military allies
    SCORE_NAP_BONUS              = 8,   -- non-aggression pact
    SCORE_WAR_ALLY_BONUS         = 25,  -- faction at war + partner is their ally
    SCORE_CLIENT_BONUS           = 15,  -- client/vassal relationship
    SCORE_SEA_EMPIRE_MULTIPLIER  = 1.5, -- extra per-region weight for sea routes

    -- Trade breakage
    MAX_BREAKAGES_PER_CYCLE      = 3,

    -- Port cache
    PORT_CACHE_REFRESH           = 10,

    -- Faction data cache refresh
    FACTION_DATA_REFRESH         = 3,

    -- Logging
    LOG_ENABLED                  = false,
    LOG_FILE                     = "smart_economy_log.txt",
}

-- ============================================================
-- LOGGING
-- ============================================================

local function Log(text)
    if not CFG.LOG_ENABLED then return end
    local f = io.open(CFG.LOG_FILE, "a")
    if f then
        f:write("[" .. os.date("%d, %m %Y %X") .. "] " .. text .. "\n")
        f:flush()
        f:close()
    end
end

-- ============================================================
-- STATE
-- ============================================================

local port_cache          = {}    -- faction_key -> { port_regions = {} }
local port_cache_turn     = 0
local port_faction_list   = {}    -- ordered list of AI faction keys with ports
local clock_index         = 0
local land_trade_turn     = 0
local sea_trade_turn      = 0
local breakage_turn       = 0
local player_discovery_turn = 0
local discovered_pairs    = {}    -- "fkey_a|fkey_b" -> turn discovered

-- Faction data cache: economic/diplomatic snapshot for scoring
local faction_data        = {}    -- fkey -> { regions, treasury, trade_count, ... }
local faction_data_turn   = 0

-- ============================================================
-- UTILITY
-- ============================================================

local function IsSlaveFaction(fkey)
    return fkey == "" or fkey == "rebels" or string.find(fkey, "slave") ~= nil
end

local function Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local function PairKey(a, b)
    if a < b then return a .. "|" .. b
    else return b .. "|" .. a end
end

-- ============================================================
-- PORT DETECTION
-- ============================================================

local function RegionHasPort(region)
    local has_port = false
    pcall(function()
        local slots = region:slot_list()
        for i = 0, slots:num_items() - 1 do
            local slot = slots:item_at(i)
            if slot:has_building() then
                local stype = slot:type()
                if stype == "port" or stype == "port_navalbuff" then
                    has_port = true
                    return
                end
                pcall(function()
                    local chain = slot:building():chain()
                    if chain and string.find(chain, "port") then
                        has_port = true
                    end
                end)
                if has_port then return end
            end
        end
    end)
    return has_port
end

local function RefreshPortCache()
    local turn = scripting.game_interface:model():turn_number()
    if port_cache_turn > 0 and (turn - port_cache_turn) < CFG.PORT_CACHE_REFRESH then
        return
    end

    port_cache = {}
    port_faction_list = {}

    pcall(function()
        local flist = scripting.game_interface:model():world():faction_list()
        for i = 0, flist:num_items() - 1 do
            local fac = flist:item_at(i)
            local fkey = fac:name()

            if not IsSlaveFaction(fkey) and fac:has_home_region() and not fac:is_human() then
                local port_regions = {}
                local regions = fac:region_list()

                for r = 0, regions:num_items() - 1 do
                    local region = regions:item_at(r)
                    if RegionHasPort(region) then
                        table.insert(port_regions, region:name())
                    end
                end

                if #port_regions > 0 then
                    port_cache[fkey] = { port_regions = port_regions }
                    table.insert(port_faction_list, fkey)
                end
            end
        end
    end)

    Shuffle(port_faction_list)
    port_cache_turn = turn
    Log("PORT CACHE: " .. #port_faction_list .. " AI factions with built ports (turn " .. turn .. ")")
end

-- ============================================================
-- FACTION DATA CACHE
-- Snapshot of every faction's economic and diplomatic state.
-- ============================================================

local function RefreshFactionData()
    local turn = scripting.game_interface:model():turn_number()
    if faction_data_turn > 0 and (turn - faction_data_turn) < CFG.FACTION_DATA_REFRESH then
        return
    end

    faction_data = {}

    pcall(function()
        local flist = scripting.game_interface:model():world():faction_list()

        for i = 0, flist:num_items() - 1 do
            local fac = flist:item_at(i)
            local fkey = fac:name()

            if not IsSlaveFaction(fkey) and fac:has_home_region() then
                local data = {
                    regions     = 0,
                    treasury    = 0,
                    trade_count = 0,
                    has_port    = (port_cache[fkey] ~= nil),
                    is_human    = false,
                    at_war_with = {},
                    allies      = {},
                    naps        = {},
                    clients     = {},
                    trading     = {},
                    can_trade   = false,
                }

                pcall(function() data.regions = fac:region_list():num_items() end)
                pcall(function() data.treasury = fac:treasury() end)
                pcall(function() data.is_human = fac:is_human() end)
                pcall(function()
                    if fac:unused_international_trade_route() and not fac:trade_route_limit_reached() then
                        data.can_trade = true
                    end
                end)

                -- Parse treaties into categorized sets
                pcall(function()
                    local treaties = fac:treaty_details()
                    if treaties then
                        for other_key, treaty_list in pairs(treaties) do
                            local okey = tostring(other_key)
                            if type(treaty_list) == "table" then
                                for _, treaty in ipairs(treaty_list) do
                                    if treaty == "current_treaty_at_war" then
                                        data.at_war_with[okey] = true
                                    elseif treaty == "current_treaty_military_alliance" then
                                        data.allies[okey] = true
                                    elseif treaty == "current_treaty_defensive_alliance" then
                                        data.allies[okey] = true
                                    elseif treaty == "current_treaty_non_aggression_pact" then
                                        data.naps[okey] = true
                                    elseif treaty == "current_treaty_client_of_player"
                                        or treaty == "current_treaty_vassal" then
                                        data.clients[okey] = true
                                    elseif treaty == "current_treaty_trade_agreement" then
                                        data.trading[okey] = true
                                        data.trade_count = data.trade_count + 1
                                    end
                                end
                            end
                        end
                    end
                end)

                faction_data[fkey] = data
            end
        end
    end)

    faction_data_turn = turn
    local count = 0
    for _ in pairs(faction_data) do count = count + 1 end
    Log("FACTION DATA: Cached " .. count .. " factions (turn " .. turn .. ")")
end

-- ============================================================
-- TRADE PAIR SCORING
-- ============================================================

local function ScoreTradePair(fkey_a, fkey_b, is_sea_trade)
    local da = faction_data[fkey_a]
    local db = faction_data[fkey_b]
    if not da or not db then return 0 end

    local score = 0

    -- PORT BONUS (heavy)
    if da.has_port or db.has_port then
        score = score + CFG.SCORE_PORT_BONUS
    end
    if da.has_port and db.has_port then
        score = score + CFG.SCORE_BOTH_PORTS_BONUS
    end

    -- EMPIRE SIZE: bigger factions trade more
    local combined_regions = da.regions + db.regions
    score = score + (combined_regions * CFG.SCORE_EMPIRE_SIZE_WEIGHT)

    if da.regions >= CFG.MAJOR_FACTION_REGIONS or db.regions >= CFG.MAJOR_FACTION_REGIONS then
        score = score + CFG.SCORE_EMPIRE_MAJOR_BONUS
    elseif da.regions >= CFG.LARGE_FACTION_REGIONS or db.regions >= CFG.LARGE_FACTION_REGIONS then
        score = score + CFG.SCORE_EMPIRE_LARGE_BONUS
    end

    -- TREASURY NEED: broke factions need trade urgently
    if da.treasury < CFG.SCORE_LOW_TREASURY_THRESHOLD or db.treasury < CFG.SCORE_LOW_TREASURY_THRESHOLD then
        score = score + CFG.SCORE_LOW_TREASURY_BONUS
    end
    if da.treasury < 0 or db.treasury < 0 then
        score = score + CFG.SCORE_BROKE_BONUS
    end

    -- TRADE COUNT: catch-up for factions with few deals
    if da.trade_count == 0 or db.trade_count == 0 then
        score = score + CFG.SCORE_FEW_TRADES_BONUS
    elseif da.trade_count <= 2 or db.trade_count <= 2 then
        score = score + CFG.SCORE_SOME_TRADES_BONUS
    end

    -- DIPLOMATIC RELATIONSHIP
    if da.allies[fkey_b] then
        score = score + CFG.SCORE_ALLY_BONUS
    elseif da.naps[fkey_b] then
        score = score + CFG.SCORE_NAP_BONUS
    end
    if da.clients[fkey_b] then
        score = score + CFG.SCORE_CLIENT_BONUS
    end

    -- WAR ECONOMY: at war + partner is ally = supply lines
    local a_at_war = next(da.at_war_with) ~= nil
    local b_at_war = next(db.at_war_with) ~= nil
    if a_at_war and da.allies[fkey_b] then
        score = score + CFG.SCORE_WAR_ALLY_BONUS
    end
    if b_at_war and db.allies[fkey_a] then
        score = score + CFG.SCORE_WAR_ALLY_BONUS
    end

    -- SEA TRADE: large empires projecting across the map get rewarded
    if is_sea_trade then
        local bigger = math.max(da.regions, db.regions)
        score = score + math.floor(bigger * CFG.SCORE_SEA_EMPIRE_MULTIPLIER)
    end

    return score
end

-- ============================================================
-- DYNAMIC CAP CALCULATION
-- ============================================================

local function GetDynamicCap(base, faction_divisor, turn_bonus)
    local turn = scripting.game_interface:model():turn_number()

    local alive_count = 0
    for _, data in pairs(faction_data) do
        if not data.is_human and data.regions > 0 then
            alive_count = alive_count + 1
        end
    end

    local faction_bonus = math.floor(alive_count / faction_divisor)
    local turn_growth = math.floor(turn / CFG.CAP_TURN_GROWTH_INTERVAL) * turn_bonus
    return base + faction_bonus + turn_growth
end

-- ============================================================
-- ENHANCED DISCOVERY SYSTEM
-- Large factions discover more and get processed more often.
-- Major powers prioritize discovering other large factions.
-- ============================================================

local function GetDiscoveryCount(faction_key)
    local data = faction_data[faction_key]
    if not data then return CFG.BASE_DISCOVERIES_PER_FACTION end

    local count = CFG.BASE_DISCOVERIES_PER_FACTION

    if data.regions >= CFG.MAJOR_FACTION_REGIONS then
        count = count + CFG.MAJOR_DISCOVERY_BONUS
    elseif data.regions >= CFG.LARGE_FACTION_REGIONS then
        count = count + CFG.LARGE_DISCOVERY_BONUS
    end

    return count
end

local function FactionsKnowEachOther(fac_a, fac_b_key)
    local da = faction_data[fac_a:name()]
    if da then
        if da.allies[fac_b_key] or da.naps[fac_b_key]
            or da.trading[fac_b_key] or da.at_war_with[fac_b_key]
            or da.clients[fac_b_key] then
            return true
        end
    end

    -- Fallback: raw treaty check
    local known = false
    pcall(function()
        local treaties = fac_a:treaty_details()
        if treaties then
            for fac_key, _ in pairs(treaties) do
                if tostring(fac_key) == fac_b_key then
                    known = true
                    return
                end
            end
        end
    end)
    return known
end

local function ProcessDiscovery(faction_key)
    local cache = port_cache[faction_key]
    if not cache or #cache.port_regions == 0 then return end

    local fac = nil
    pcall(function()
        fac = scripting.game_interface:model():world():faction_by_key(faction_key)
    end)
    if not fac then return end

    -- Build candidate list
    local candidates = {}
    for _, other_key in ipairs(port_faction_list) do
        if other_key ~= faction_key then
            local other_cache = port_cache[other_key]
            if other_cache and #other_cache.port_regions > 0 then
                if not FactionsKnowEachOther(fac, other_key) then
                    table.insert(candidates, other_key)
                end
            end
        end
    end

    if #candidates == 0 then
        Log("DISCOVER: " .. faction_key .. " — knows all " .. (#port_faction_list - 1) .. " port factions")
        return
    end

    -- Large factions prioritize discovering other large factions first
    local data = faction_data[faction_key]
    if data and data.regions >= CFG.LARGE_FACTION_REGIONS then
        -- Sort top half by empire size (big finds big), shuffle bottom half
        table.sort(candidates, function(a, b)
            local sa = faction_data[a] and faction_data[a].regions or 0
            local sb = faction_data[b] and faction_data[b].regions or 0
            return sa > sb
        end)
        local mid = math.ceil(#candidates / 2)
        local bottom = {}
        for i = mid + 1, #candidates do
            table.insert(bottom, candidates[i])
        end
        Shuffle(bottom)
        for i = 1, #bottom do
            candidates[mid + i] = bottom[i]
        end
    else
        Shuffle(candidates)
    end

    local count = math.min(GetDiscoveryCount(faction_key), #candidates)

    for i = 1, count do
        local target_key = candidates[i]
        local target_cache = port_cache[target_key]

        local target_region = target_cache.port_regions[math.random(1, #target_cache.port_regions)]
        pcall(function()
            scripting.game_interface:make_region_visible_in_shroud(faction_key, target_region)
        end)

        local our_region = cache.port_regions[math.random(1, #cache.port_regions)]
        pcall(function()
            scripting.game_interface:make_region_visible_in_shroud(target_key, our_region)
        end)

        Log("DISCOVER: " .. faction_key .. " (" .. (data and data.regions or "?") .. " regions) <-> "
            .. target_key .. " (revealed " .. target_region .. " / " .. our_region .. ")")

        local pair_key = PairKey(faction_key, target_key)
        if not discovered_pairs[pair_key] then
            discovered_pairs[pair_key] = scripting.game_interface:model():turn_number()
        end
    end
end

local function TickDiscoveryClock()
    if #port_faction_list == 0 then
        Log("DISCOVER CLOCK: No port factions in cache")
        return
    end

    -- Build processing queue
    local process_queue = {}
    local base_count = math.min(CFG.BASE_FACTIONS_PER_TICK, #port_faction_list)

    -- Normal round-robin pass
    for p = 1, base_count do
        clock_index = clock_index + 1
        if clock_index > #port_faction_list then
            clock_index = 1
            Shuffle(port_faction_list)
            Log("DISCOVER CLOCK: Full cycle complete, reshuffled " .. #port_faction_list .. " factions")
        end

        local fkey = port_faction_list[clock_index]
        if port_cache[fkey] then
            table.insert(process_queue, fkey)
        end
    end

    -- Large/major factions get extra processing passes every tick
    for _, fkey in ipairs(port_faction_list) do
        local data = faction_data[fkey]
        if data and data.regions >= CFG.LARGE_FACTION_REGIONS then
            for e = 1, CFG.LARGE_FACTION_EXTRA_TICKS do
                table.insert(process_queue, fkey)
            end
        end
    end

    for _, fkey in ipairs(process_queue) do
        ProcessDiscovery(fkey)
    end

    Log("DISCOVER CLOCK: Processed " .. #process_queue .. " entries (base=" .. base_count
        .. " + large faction extras, index=" .. clock_index .. "/" .. #port_faction_list .. ")")
end

-- ============================================================
-- PLAYER DISCOVERY
-- Reveals random port faction regions to the player through
-- the shroud, simulating maritime exploration. Player gets
-- more discoveries as their empire and port count grow.
-- ============================================================

local function ProcessPlayerDiscovery()
    local player_key = nil
    local player_fac = nil
    local player_ports = {}

    -- Find the human faction and their ports
    pcall(function()
        local flist = scripting.game_interface:model():world():faction_list()
        for i = 0, flist:num_items() - 1 do
            local fac = flist:item_at(i)
            if fac:is_human() and fac:has_home_region() then
                player_key = fac:name()
                player_fac = fac

                local regions = fac:region_list()
                for r = 0, regions:num_items() - 1 do
                    local region = regions:item_at(r)
                    if RegionHasPort(region) then
                        table.insert(player_ports, region:name())
                    end
                end
                break
            end
        end
    end)

    if not player_key or not player_fac or #player_ports == 0 then
        Log("PLAYER DISCOVER: Player has no ports, skipping")
        return
    end

    -- Build candidate list: port factions the player hasn't discovered yet
    local candidates = {}
    for _, other_key in ipairs(port_faction_list) do
        if other_key ~= player_key then
            local other_cache = port_cache[other_key]
            if other_cache and #other_cache.port_regions > 0 then
                if not FactionsKnowEachOther(player_fac, other_key) then
                    table.insert(candidates, other_key)
                end
            end
        end
    end

    if #candidates == 0 then
        Log("PLAYER DISCOVER: Player knows all port factions already")
        return
    end

    Shuffle(candidates)

    -- Discovery count scales with player's port count
    local base = CFG.PLAYER_DISCOVERIES_PER_TICK
    local port_bonus = math.floor(#player_ports / 2)  -- +1 per 2 ports
    local count = math.min(base + port_bonus, #candidates)

    local revealed = 0
    for i = 1, count do
        local target_key = candidates[i]
        local target_cache = port_cache[target_key]
        if target_cache and #target_cache.port_regions > 0 then
            local target_region = target_cache.port_regions[math.random(1, #target_cache.port_regions)]
            pcall(function()
                scripting.game_interface:make_region_visible_in_shroud(player_key, target_region)
            end)
            revealed = revealed + 1

            local target_data = faction_data[target_key]
            local target_size = target_data and target_data.regions or "?"
            Log("PLAYER DISCOVER: " .. player_key .. " -> " .. target_key
                .. " (" .. target_size .. " regions, revealed " .. target_region .. ")")
        end
    end

    Log("PLAYER DISCOVER: Revealed " .. revealed .. " port factions to player"
        .. " (player has " .. #player_ports .. " ports)")
end

-- ============================================================
-- LAND BORDER TRADE (scored & prioritized)
-- ============================================================

local function ProcessLandTrades()
    local forced = 0

    pcall(function()
        local flist = scripting.game_interface:model():world():faction_list()
        local faction_objects = {}

        for i = 0, flist:num_items() - 1 do
            local fac = flist:item_at(i)
            local fkey = fac:name()
            if not IsSlaveFaction(fkey) and fac:has_home_region() then
                faction_objects[fkey] = fac
            end
        end

        local trade_pairs = {}
        local already_checked = {}

        for fkey_a, fac_a in pairs(faction_objects) do
            local da = faction_data[fkey_a]
            if da and da.can_trade and not da.is_human then
                local regions_a = fac_a:region_list()
                for r = 0, regions_a:num_items() - 1 do
                    local region = regions_a:item_at(r)
                    local adj = region:adjacent_region_list()

                    for j = 0, adj:num_items() - 1 do
                        local adj_region = adj:item_at(j)
                        local fkey_b = nil
                        pcall(function()
                            fkey_b = adj_region:owning_faction():name()
                        end)

                        if fkey_b and fkey_b ~= fkey_a
                            and not IsSlaveFaction(fkey_b)
                            and faction_objects[fkey_b] then

                            local pair_key = PairKey(fkey_a, fkey_b)
                            if not already_checked[pair_key] then
                                already_checked[pair_key] = true

                                local db = faction_data[fkey_b]
                                if db and db.can_trade and not db.is_human
                                    and not da.at_war_with[fkey_b]
                                    and not da.trading[fkey_b] then

                                    local score = ScoreTradePair(fkey_a, fkey_b, false)
                                    table.insert(trade_pairs, {
                                        a = fkey_a, b = fkey_b, score = score
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Sort by score descending — highest priority forced first
        table.sort(trade_pairs, function(x, y) return x.score > y.score end)

        local cap = GetDynamicCap(
            CFG.BASE_LAND_TRADES_PER_CYCLE,
            CFG.LAND_CAP_FACTION_DIVISOR,
            CFG.LAND_CAP_TURN_BONUS
        )
        cap = math.min(cap, #trade_pairs)

        for i = 1, cap do
            local pair = trade_pairs[i]
            pcall(function()
                scripting.game_interface:force_make_trade_agreement(pair.a, pair.b)
            end)
            forced = forced + 1
            Log("LAND TRADE: " .. pair.a .. " <-> " .. pair.b .. " (score=" .. pair.score .. ")")
        end

        if #trade_pairs > cap then
            Log("LAND TRADE: " .. (#trade_pairs - cap) .. " lower-priority pairs deferred")
        end
    end)

    local cap_val = GetDynamicCap(CFG.BASE_LAND_TRADES_PER_CYCLE, CFG.LAND_CAP_FACTION_DIVISOR, CFG.LAND_CAP_TURN_BONUS)
    Log("LAND TRADE: " .. forced .. " forced (dynamic cap=" .. cap_val .. ")")
end

-- ============================================================
-- SEA TRADE (scored & prioritized, large empires dominate)
-- ============================================================

local function ProcessSeaTrades()
    local forced = 0

    pcall(function()
        local turn = scripting.game_interface:model():turn_number()
        local trade_pairs = {}

        for pair_key, discovered_turn in pairs(discovered_pairs) do
            local sep = string.find(pair_key, "|")
            if sep then
                local fkey_a = string.sub(pair_key, 1, sep - 1)
                local fkey_b = string.sub(pair_key, sep + 1)

                -- Wait period after discovery
                if (turn - discovered_turn) >= CFG.SEA_TRADE_WAIT_TURNS then
                    local da = faction_data[fkey_a]
                    local db = faction_data[fkey_b]

                    if da and db
                        and not da.is_human and not db.is_human
                        and da.regions > 0 and db.regions > 0
                        and da.can_trade and db.can_trade
                        and not da.at_war_with[fkey_b]
                        and not da.trading[fkey_b] then

                        local score = ScoreTradePair(fkey_a, fkey_b, true)
                        table.insert(trade_pairs, { a = fkey_a, b = fkey_b, score = score })
                    end
                end
            end
        end

        -- Sort by score descending
        table.sort(trade_pairs, function(x, y) return x.score > y.score end)

        local cap = GetDynamicCap(
            CFG.BASE_SEA_TRADES_PER_CYCLE,
            CFG.SEA_CAP_FACTION_DIVISOR,
            CFG.SEA_CAP_TURN_BONUS
        )
        cap = math.min(cap, #trade_pairs)

        for i = 1, cap do
            local pair = trade_pairs[i]
            pcall(function()
                scripting.game_interface:force_make_trade_agreement(pair.a, pair.b)
            end)
            forced = forced + 1
            Log("SEA TRADE: " .. pair.a .. " <-> " .. pair.b .. " (score=" .. pair.score .. ")")
        end

        if #trade_pairs > cap then
            Log("SEA TRADE: " .. (#trade_pairs - cap) .. " lower-priority pairs deferred")
        end
    end)

    local cap_val = GetDynamicCap(CFG.BASE_SEA_TRADES_PER_CYCLE, CFG.SEA_CAP_FACTION_DIVISOR, CFG.SEA_CAP_TURN_BONUS)
    Log("SEA TRADE: " .. forced .. " forced (dynamic cap=" .. cap_val .. ")")
end

-- ============================================================
-- TRADE BREAKAGE
-- Dissolves trades that no longer make diplomatic sense.
-- ============================================================

local function ProcessTradeBreakage()
    local broken = 0

    pcall(function()
        local breakage_candidates = {}
        local seen_pairs = {}

        for fkey_a, da in pairs(faction_data) do
            if not da.is_human then
                for trading_partner, _ in pairs(da.trading) do
                    local db = faction_data[trading_partner]
                    if db and not db.is_human then
                        local pair_key = PairKey(fkey_a, trading_partner)
                        if not seen_pairs[pair_key] then
                            local should_break = false
                            local reason = ""

                            -- Direct war (engine usually handles, but clean up stragglers)
                            if da.at_war_with[trading_partner] then
                                should_break = true
                                reason = "at war"
                            end

                            -- Trading with the enemy's ally
                            if not should_break then
                                for enemy_key, _ in pairs(da.at_war_with) do
                                    if db.allies[enemy_key] then
                                        should_break = true
                                        reason = fkey_a .. " at war with " .. trading_partner .. "'s ally " .. enemy_key
                                        break
                                    end
                                end
                            end

                            -- Reverse check: partner at war with our ally
                            if not should_break then
                                for enemy_key, _ in pairs(db.at_war_with) do
                                    if da.allies[enemy_key] then
                                        should_break = true
                                        reason = trading_partner .. " at war with " .. fkey_a .. "'s ally " .. enemy_key
                                        break
                                    end
                                end
                            end

                            if should_break then
                                seen_pairs[pair_key] = true
                                table.insert(breakage_candidates, {
                                    a = fkey_a, b = trading_partner, reason = reason
                                })
                            end
                        end
                    end
                end
            end
        end

        Shuffle(breakage_candidates)
        local cap = math.min(CFG.MAX_BREAKAGES_PER_CYCLE, #breakage_candidates)

        for i = 1, cap do
            local c = breakage_candidates[i]
            pcall(function()
                scripting.game_interface:force_break_trade_agreement(c.a, c.b)
            end)
            broken = broken + 1
            Log("BREAKAGE: " .. c.a .. " <-> " .. c.b .. " (" .. c.reason .. ")")
        end
    end)

    Log("BREAKAGE: " .. broken .. " agreements dissolved")
end

-- ============================================================
-- EVENT HANDLER
-- ============================================================

local function OnFactionTurnStart(context)
    local ok, is_human = pcall(function() return context:faction():is_human() end)
    if not ok or not is_human then return end

    local turn = scripting.game_interface:model():turn_number()

    RefreshPortCache()
    RefreshFactionData()

    if turn >= CFG.MIN_TURN_DISCOVERY then
        TickDiscoveryClock()
    end

    if turn >= CFG.MIN_TURN_PLAYER_DISCOVERY
        and (turn - player_discovery_turn) >= CFG.PLAYER_DISCOVERY_INTERVAL then
        ProcessPlayerDiscovery()
        player_discovery_turn = turn
    end

    if turn >= CFG.MIN_TURN_LAND_TRADE and (turn - land_trade_turn) >= CFG.LAND_TRADE_INTERVAL then
        ProcessLandTrades()
        land_trade_turn = turn
    end

    if turn >= CFG.MIN_TURN_SEA_TRADE and (turn - sea_trade_turn) >= CFG.SEA_TRADE_INTERVAL then
        ProcessSeaTrades()
        sea_trade_turn = turn
    end

    if turn >= CFG.MIN_TURN_BREAKAGE and (turn - breakage_turn) >= CFG.BREAKAGE_INTERVAL then
        ProcessTradeBreakage()
        breakage_turn = turn
    end
end

-- ============================================================
-- INIT
-- ============================================================

scripting.AddEventCallBack("FactionTurnStart", OnFactionTurnStart)

Log("==========================================================")
Log("Smart Economy v2.0 loaded")
Log("Discovery: base " .. CFG.BASE_FACTIONS_PER_TICK .. " factions/turn, "
    .. CFG.BASE_DISCOVERIES_PER_FACTION .. " discoveries each")
Log("Large factions (" .. CFG.LARGE_FACTION_REGIONS .. "+ regions): +"
    .. CFG.LARGE_DISCOVERY_BONUS .. " discoveries, +"
    .. CFG.LARGE_FACTION_EXTRA_TICKS .. " extra ticks")
Log("Major powers (" .. CFG.MAJOR_FACTION_REGIONS .. "+ regions): +"
    .. CFG.MAJOR_DISCOVERY_BONUS .. " discoveries")
Log("Player discovery: every " .. CFG.PLAYER_DISCOVERY_INTERVAL .. " turns, base "
    .. CFG.PLAYER_DISCOVERIES_PER_TICK .. " reveals (scales with port count)")
Log("Land trade: every " .. CFG.LAND_TRADE_INTERVAL .. " turns, base cap "
    .. CFG.BASE_LAND_TRADES_PER_CYCLE)
Log("Sea trade: every " .. CFG.SEA_TRADE_INTERVAL .. " turns, base cap "
    .. CFG.BASE_SEA_TRADES_PER_CYCLE)
Log("Breakage: every " .. CFG.BREAKAGE_INTERVAL .. " turns, max "
    .. CFG.MAX_BREAKAGES_PER_CYCLE .. "/cycle")
Log("==========================================================")
