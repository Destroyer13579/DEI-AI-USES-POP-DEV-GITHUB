-- ============================================================
-- SMART ECONOMY
-- AI Uses Population and More
-- ============================================================
-- Two systems:
-- 1. DISCOVERY: Port factions gradually discover other port factions
--    via shroud reveals. AI decides on its own whether to trade.
-- 2. LAND TRADE: Forces trade agreements between land neighbors
--    who have unused routes (capped per cycle).
--
-- Runs on a round-robin clock so every AI gets equal chances.
-- ============================================================

local scripting = require "lua_scripts.EpisodicScripting"

-- ============================================================
-- CONFIG
-- ============================================================

local CFG = {
    -- Discovery clock: how many factions to process per turn
    FACTIONS_PER_TICK = 5,

    -- How many random port factions each processed faction discovers per tick
    DISCOVERIES_PER_FACTION = 3,

    -- Minimum turn before systems activate
    MIN_TURN_DISCOVERY = 8,
    MIN_TURN_LAND_TRADE = 5,
    MIN_TURN_SEA_TRADE = 12,

    -- Land trade: run every N turns
    LAND_TRADE_INTERVAL = 3,

    -- Sea trade: run every N turns (less frequent, for discovered port pairs)
    SEA_TRADE_INTERVAL = 5,

    -- Max trades forced per cycle
    MAX_LAND_TRADES_PER_CYCLE = 15,
    MAX_SEA_TRADES_PER_CYCLE = 2,

    -- Turns to wait after discovery before forcing trade (give AI a chance first)
    SEA_TRADE_WAIT_TURNS = 3,

    -- Port cache refresh interval
    PORT_CACHE_REFRESH = 10,

    -- Logging
    LOG_ENABLED = true,
    LOG_FILE = "smart_economy_log.txt",
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

local port_cache = {}           -- faction_key -> { port_regions = {} }
local port_cache_turn = 0
local port_faction_list = {}    -- ordered list of AI faction keys with ports
local clock_index = 0           -- round-robin pointer
local land_trade_turn = 0
local sea_trade_turn = 0
local discovered_pairs = {}     -- "fkey_a|fkey_b" -> turn discovered

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
                -- fallback: check building chain name
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
-- DISCOVERY SYSTEM
-- ============================================================

local function FactionsKnowEachOther(fac_a, fac_b_key)
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

    -- build candidate list: any port faction we don't already know
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
        Log("DISCOVER: " .. faction_key .. " — knows all " .. (#port_faction_list - 1) .. " port factions already")
        return
    end

    Shuffle(candidates)
    local count = math.min(CFG.DISCOVERIES_PER_FACTION, #candidates)

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

        Log("DISCOVER: " .. faction_key .. " <-> " .. target_key
            .. " (revealed " .. target_region .. " / " .. our_region .. ")")

        -- record this pair for sea trade eligibility
        local pair_key = faction_key < target_key and (faction_key .. "|" .. target_key) or (target_key .. "|" .. faction_key)
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

    local processed = 0
    while processed < CFG.FACTIONS_PER_TICK do
        clock_index = clock_index + 1

        if clock_index > #port_faction_list then
            clock_index = 1
            Shuffle(port_faction_list)
            Log("DISCOVER CLOCK: Full cycle complete, reshuffled " .. #port_faction_list .. " factions")
        end

        local fkey = port_faction_list[clock_index]
        if port_cache[fkey] then
            ProcessDiscovery(fkey)
        end
        processed = processed + 1
    end

    Log("DISCOVER CLOCK: Processed " .. processed .. " factions (index=" .. clock_index .. "/" .. #port_faction_list .. ")")
end

-- ============================================================
-- LAND BORDER TRADE
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

        -- collect all valid trade pairs, then shuffle and cap
        local trade_pairs = {}
        local already_checked = {}

        for fkey_a, fac_a in pairs(faction_objects) do
            local can_trade_a = false
            pcall(function()
                if fac_a:unused_international_trade_route() and not fac_a:trade_route_limit_reached() then
                    can_trade_a = true
                end
            end)

            if can_trade_a then
                local regions_a = fac_a:region_list()
                for r = 0, regions_a:num_items() - 1 do
                    local region = regions_a:item_at(r)
                    local adj = region:adjacent_region_list()
                    for j = 0, adj:num_items() - 1 do
                        local adj_region = adj:item_at(j)
                        local fkey_b = adj_region:owning_faction():name()

                        if fkey_b ~= fkey_a and not IsSlaveFaction(fkey_b) and faction_objects[fkey_b] then
                            local pair_key = fkey_a < fkey_b and (fkey_a .. "|" .. fkey_b) or (fkey_b .. "|" .. fkey_a)
                            if not already_checked[pair_key] then
                                already_checked[pair_key] = true

                                local fac_b = faction_objects[fkey_b]
                                local can_trade_b = false
                                pcall(function()
                                    if fac_b:unused_international_trade_route() and not fac_b:trade_route_limit_reached() then
                                        can_trade_b = true
                                    end
                                end)

                                if can_trade_b then
                                    local at_war = false
                                    local already_trading = false
                                    pcall(function()
                                        local treaties = fac_a:treaty_details()
                                        if treaties then
                                            for fac_key, treaty_list in pairs(treaties) do
                                                if tostring(fac_key) == fkey_b and type(treaty_list) == "table" then
                                                    for _, treaty in ipairs(treaty_list) do
                                                        if treaty == "current_treaty_at_war" then
                                                            at_war = true
                                                        end
                                                        if treaty == "current_treaty_trade_agreement" then
                                                            already_trading = true
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end)

                                    if not at_war and not already_trading then
                                        table.insert(trade_pairs, { a = fkey_a, b = fkey_b })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- shuffle and cap
        Shuffle(trade_pairs)
        local cap = math.min(CFG.MAX_LAND_TRADES_PER_CYCLE, #trade_pairs)

        for i = 1, cap do
            local pair = trade_pairs[i]
            pcall(function()
                scripting.game_interface:force_make_trade_agreement(pair.a, pair.b)
            end)
            forced = forced + 1
            Log("LAND TRADE: Forced " .. pair.a .. " <-> " .. pair.b)
        end

        if #trade_pairs > cap then
            Log("LAND TRADE: " .. (#trade_pairs - cap) .. " pairs deferred to next cycle")
        end
    end)

    Log("LAND TRADE: " .. forced .. " agreements forced this cycle")
end

-- ============================================================
-- SEA TRADE (force trade between discovered port pairs)
-- Only between factions introduced by our discovery system.
-- At least one must be an established trader (2+ existing deals).
-- ============================================================

local function ProcessSeaTrades()
    local forced = 0

    pcall(function()
        local trade_pairs = {}

        for pair_key, discovered_turn in pairs(discovered_pairs) do
            -- split pair key
            local sep = string.find(pair_key, "|")
            local eligible = (sep ~= nil)
            local fkey_a, fkey_b = "", ""

            if eligible then
                fkey_a = string.sub(pair_key, 1, sep - 1)
                fkey_b = string.sub(pair_key, sep + 1)
            end

            -- wait period: give AI a chance to trade naturally before forcing
            local turn = scripting.game_interface:model():turn_number()
            if eligible and (turn - discovered_turn) < CFG.SEA_TRADE_WAIT_TURNS then
                eligible = false
            end

            -- get faction objects fresh
            local fac_a, fac_b = nil, nil
            if eligible then
                pcall(function()
                    fac_a = scripting.game_interface:model():world():faction_by_key(fkey_a)
                    fac_b = scripting.game_interface:model():world():faction_by_key(fkey_b)
                end)
                if not fac_a or not fac_b then eligible = false end
            end
            if eligible then
                if not fac_a:has_home_region() or not fac_b:has_home_region() then eligible = false end
            end

            -- both must have unused routes
            if eligible then
                local can_a, can_b = false, false
                pcall(function()
                    if fac_a:unused_international_trade_route() and not fac_a:trade_route_limit_reached() then can_a = true end
                end)
                pcall(function()
                    if fac_b:unused_international_trade_route() and not fac_b:trade_route_limit_reached() then can_b = true end
                end)
                if not can_a or not can_b then eligible = false end
            end

            -- not at war, not already trading
            if eligible then
                local at_war = false
                local already_trading = false
                pcall(function()
                    local treaties = fac_a:treaty_details()
                    if treaties then
                        for fac_key, treaty_list in pairs(treaties) do
                            if tostring(fac_key) == fkey_b and type(treaty_list) == "table" then
                                for _, treaty in ipairs(treaty_list) do
                                    if treaty == "current_treaty_at_war" then at_war = true end
                                    if treaty == "current_treaty_trade_agreement" then already_trading = true end
                                end
                            end
                        end
                    end
                end)
                if at_war or already_trading then eligible = false end
            end

            if eligible then
                table.insert(trade_pairs, { a = fkey_a, b = fkey_b })
            end
        end

        -- shuffle and cap at 2
        Shuffle(trade_pairs)
        local cap = math.min(CFG.MAX_SEA_TRADES_PER_CYCLE, #trade_pairs)

        for i = 1, cap do
            local pair = trade_pairs[i]
            pcall(function()
                scripting.game_interface:force_make_trade_agreement(pair.a, pair.b)
            end)
            forced = forced + 1
            Log("SEA TRADE: Forced " .. pair.a .. " <-> " .. pair.b)
        end

        if #trade_pairs > cap then
            Log("SEA TRADE: " .. (#trade_pairs - cap) .. " pairs deferred to next cycle")
        end
    end)

    Log("SEA TRADE: " .. forced .. " agreements forced this cycle")
end

-- ============================================================
-- EVENT HANDLER
-- ============================================================

local function OnFactionTurnStart(context)
    local ok, is_human = pcall(function() return context:faction():is_human() end)
    if not ok or not is_human then return end

    local turn = scripting.game_interface:model():turn_number()

    RefreshPortCache()

    if turn >= CFG.MIN_TURN_DISCOVERY then
        TickDiscoveryClock()
    end

    if turn >= CFG.MIN_TURN_LAND_TRADE and (turn - land_trade_turn) >= CFG.LAND_TRADE_INTERVAL then
        ProcessLandTrades()
        land_trade_turn = turn
    end

    -- sea trade: force trade between discovered port pairs (established traders only)
    if turn >= CFG.MIN_TURN_SEA_TRADE and (turn - sea_trade_turn) >= CFG.SEA_TRADE_INTERVAL then
        ProcessSeaTrades()
        sea_trade_turn = turn
    end
end

-- ============================================================
-- INIT
-- ============================================================

scripting.AddEventCallBack("FactionTurnStart", OnFactionTurnStart)

Log("Smart Economy loaded")
Log("Discovery: " .. CFG.FACTIONS_PER_TICK .. " factions/turn, " .. CFG.DISCOVERIES_PER_FACTION .. " discoveries each")
Log("Land trade: every " .. CFG.LAND_TRADE_INTERVAL .. " turns, max " .. CFG.MAX_LAND_TRADES_PER_CYCLE .. " per cycle")
