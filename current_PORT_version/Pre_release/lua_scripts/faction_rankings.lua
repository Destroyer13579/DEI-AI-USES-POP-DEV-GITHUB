-- faction_rankings.lua
-- Faction Power Rankings - AI Uses Population and More
-- In-game button toggles a styled rankings panel

local scripting = require "lua_scripts.EpisodicScripting"
local triggers  = require "data.lua_scripts.export_triggers"
local events    = triggers.events

-- ============================================================
-- LOGGING (set to false to disable log file)
-- ============================================================
local LOG_ENABLED = false

local function Log(text)
    if not LOG_ENABLED then return end
    print("[FactionRankings] " .. text)
    local f = io.open("FactionRankings_Log.txt", "a")
    if f then f:write(text .. "\n") f:close() end
end

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
    -- Click cycle order: Overall > Settlements > Military > Income > Income(DEV) > Coalition > close
    SORT_MODES  = { "overall", "settlements", "military", "income", "coalition" },
    SORT_LABELS = {
        overall      = "OVERALL RANKINGS",
        settlements  = "SETTLEMENTS AND POPULATION",
        military     = "MILITARY",
        income       = "INCOME",
        income_dev   = "INCOME (DEV)",
        coalition    = "COALITIONS"
    },
    SKIP_REBELS   = true,
    SKIP_NEUTRALS = true,
    FOG_OF_WAR    = true,    -- only show factions the player has discovered
    BUTTON_ID     = "faction_rankings_panel_toggle",
    TOP_N         = 20,
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    is_visible         = false,
    current_sort_index = 1,
    ui_root            = nil,
    ui_ready           = false,
    panel_cleaned      = false,
}

-- Trend data: snapshots of faction stats per turn
local prev_snapshot = {}   -- faction_key -> {settlements, armies, wars, treasury}
local curr_snapshot = {}   -- updated at start of each player turn
local snapshot_turn = 0    -- turn when curr_snapshot was taken

-- ============================================================
-- UTILITY
-- ============================================================
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function fmt_num(n)
    n = math.floor(n or 0)
    local s = tostring(n < 0 and -n or n)
    local o = ""
    local len = #s
    for i = 1, len do
        o = o .. s:sub(i, i)
        local rem = len - i
        if rem > 0 and rem % 3 == 0 then o = o .. "," end
    end
    return (n < 0 and "-" or "") .. o
end

local function ui_find(name)
    if not State.ui_root then return nil end
    local ok, raw = pcall(function() return State.ui_root:Find(name) end)
    if ok and raw then
        local ok2, comp = pcall(UIComponent, raw)
        if ok2 and comp then
            local ok3, vis = pcall(function() return comp:Visible() end)
            if ok3 and vis ~= nil then return comp end
        end
    end
    return nil
end

local function c(color, text)
    return "[[col:" .. color .. "]]" .. text .. "[[/col]]"
end

-- ============================================================
-- DATA COLLECTION
-- ============================================================
local function get_display_name(faction)
    local ok1, name = pcall(function() return faction:localised_name() end)
    if ok1 and name and name ~= "" then return name end
    local ok_key, fkey = pcall(function() return faction:name() end)
    if not ok_key or not fkey then return "Unknown" end
    local ok2, lname = pcall(function()
        return common.get_localised_string("faction_name_" .. fkey)
    end)
    if ok2 and lname and lname ~= "" then return lname end
    -- strip common prefixes like rom_, att_, dei_, emp_ etc
    local clean = fkey
    clean = clean:gsub("^rom_", "")
    clean = clean:gsub("^att_", "")
    clean = clean:gsub("^dei_", "")
    clean = clean:gsub("^emp_", "")
    clean = clean:gsub("^nap_", "")
    -- capitalize
    return clean:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b)
        return a:upper() .. b:lower()
    end)
end

local function should_skip(f)
    local ok_dead, is_dead = pcall(function() return f:is_dead() end)
    if ok_dead and is_dead then return true end
    if CFG.SKIP_REBELS then
        local ok, rebel = pcall(function() return f:is_rebel() end)
        if ok and rebel then return true end
    end
    local ok_r, rc = pcall(function() return f:region_list():num_items() end)
    if CFG.SKIP_NEUTRALS and ok_r and rc == 0 then return true end
    -- skip generic/minor factions with "gen_" prefix
    local ok_name, fname = pcall(function() return f:name() end)
    if ok_name and fname and string.sub(fname, 1, 4) == "gen_" then return true end
    return false
end

-- ============================================================
-- FOG OF WAR DETECTION
-- ============================================================
local _human_faction_key = nil

local function get_human_faction()
    -- always look up the faction object fresh (userdata can go stale between turns)
    -- but cache the key since that's a string and safe
    local human_fac = nil
    pcall(function()
        if _human_faction_key then
            human_fac = scripting.game_interface:model():world():faction_by_key(_human_faction_key)
        else
            local flist = scripting.game_interface:model():world():faction_list()
            for i = 0, flist:num_items() - 1 do
                local f = flist:item_at(i)
                if f:is_human() then
                    _human_faction_key = f:name()
                    human_fac = f
                    return
                end
            end
        end
    end)
    return human_fac, _human_faction_key
end

-- check if the human player has "met" another faction
-- uses treaty_details (safe, proven in smart_diplomacy) and adjacent regions
local function is_faction_known(other_faction, other_key)
    -- player always knows themselves
    if other_key == _human_faction_key then return true end

    local human_fac = get_human_faction()
    if not human_fac then return true end  -- safety: show all if we can't find human

    local known = false

    -- Method 1: check player's treaty_details for this faction
    pcall(function()
        local treaties = human_fac:treaty_details()
        if treaties then
            for fac_key, treaty_list in pairs(treaties) do
                if tostring(fac_key) == other_key then
                    known = true
                    return
                end
            end
        end
    end)

    if not known then
        -- Method 2: check if other faction has player in THEIR treaty_details
        pcall(function()
            local treaties = other_faction:treaty_details()
            if treaties then
                for fac_key, treaty_list in pairs(treaties) do
                    if tostring(fac_key) == _human_faction_key then
                        known = true
                        return
                    end
                end
            end
        end)
    end

    if not known then
        -- Method 3: adjacent regions — if any of our regions border theirs, we've met
        pcall(function()
            local our_regions = human_fac:region_list()
            for i = 0, our_regions:num_items() - 1 do
                if known then return end
                local our_region = our_regions:item_at(i)
                local adj = our_region:adjacent_region_list()
                for j = 0, adj:num_items() - 1 do
                    local adj_region = adj:item_at(j)
                    local adj_owner = adj_region:owning_faction()
                    if adj_owner:name() == other_key then
                        known = true
                        return
                    end
                end
            end
        end)
    end

    return known
end

-- count field armies: character_type("general") with a non-navy force
-- colonels are garrison commanders, generals are field army leaders
local army_method_logged = false
local function count_field_armies(faction)
    local count = 0
    local ok, err = pcall(function()
        local chars = faction:character_list()
        local total = chars:num_items()
        for i = 0, total - 1 do
            local char = chars:item_at(i)
            local ok_type, is_gen = pcall(function() return char:character_type("general") end)
            local ok_force, has_force = pcall(function() return char:has_military_force() end)
            if ok_type and is_gen and ok_force and has_force then
                local ok_navy, is_navy = pcall(function() return char:military_force():is_navy() end)
                if not (ok_navy and is_navy) then
                    count = count + 1
                end
            end
        end
        if not army_method_logged then
            Log("ARMY DEBUG: " .. (pcall(function() return faction:name() end) and faction:name() or "?") ..
                " total_chars=" .. total .. " field_armies=" .. count)
            army_method_logged = true
        end
    end)
    if not ok and not army_method_logged then
        Log("ARMY DEBUG ERROR: " .. tostring(err))
        army_method_logged = true
    end
    return count
end

-- count wars using treaty_details (from smart_diplomacy pattern)
local war_method_logged = false
local function count_wars(faction)
    local wars = 0
    local ok, err = pcall(function()
        local treaties = faction:treaty_details()
        if not treaties then
            if not war_method_logged then
                Log("WAR DEBUG: treaty_details() returned nil")
                war_method_logged = true
            end
            return
        end
        if not war_method_logged then
            Log("WAR DEBUG: treaty_details() returned type=" .. type(treaties))
            local count = 0
            for k, v in pairs(treaties) do
                count = count + 1
                if count <= 3 then
                    Log("  treaty entry: key_type=" .. type(k) .. " val_type=" .. type(v))
                    if type(v) == "table" then
                        for ii, tt in ipairs(v) do
                            Log("    treaty[" .. ii .. "]=" .. tostring(tt))
                        end
                    end
                end
            end
            Log("  total treaty entries: " .. count)
            war_method_logged = true
        end
        for other_faction, treaty_list in pairs(treaties) do
            if type(treaty_list) == "table" then
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_at_war" then
                        wars = wars + 1
                        break
                    end
                end
            end
        end
    end)
    if not ok and not war_method_logged then
        Log("WAR DEBUG: count_wars ERROR: " .. tostring(err))
        war_method_logged = true
    end
    return wars
end

-- get list of faction keys we're at war with
local function get_war_enemies(faction)
    local enemies = {}
    pcall(function()
        local treaties = faction:treaty_details()
        if not treaties then return end
        for other_faction, treaty_list in pairs(treaties) do
            if type(treaty_list) == "table" then
                for _, treaty in ipairs(treaty_list) do
                    if treaty == "current_treaty_at_war" then
                        table.insert(enemies, tostring(other_faction))
                        break
                    end
                end
            end
        end
    end)
    return enemies
end

local function collect_factions(filter_fog)
    if filter_fog and CFG.FOG_OF_WAR then
        get_human_faction()  -- ensure human faction is cached
    end
    local results = {}
    local flist = scripting.game_interface:model():world():faction_list()
    for i = 0, flist:num_items() - 1 do
        local f = flist:item_at(i)
        if not should_skip(f) then
            local ok6, v6 = pcall(function() return f:name() end)
            local fname = ok6 and v6 or "unknown"

            -- fog of war filter: skip factions player hasn't discovered
            if filter_fog and CFG.FOG_OF_WAR and not is_faction_known(f, fname) then
                -- skip this faction
            else

            local treasury, settlements = 0, 0
            local is_human = false
            local ok2, v2 = pcall(function() return f:treasury() end)
            if ok2 then treasury = v2 or 0 end
            local ok3, v3 = pcall(function() return f:region_list():num_items() end)
            if ok3 then settlements = v3 or 0 end
            local ok5, v5 = pcall(function() return f:is_human() end)
            if ok5 then is_human = v5 end

            local armies = count_field_armies(f)
            local wars = count_wars(f)
            local war_enemies = get_war_enemies(f)

            -- get total population from population.lua bridge
            local population = 0
            local ok_pop, pop_val = pcall(function() return GetFactionTotalPopulation(f) end)
            if ok_pop and pop_val then population = pop_val end

            -- compute actual income: sum of tax_income across all regions + trade_value
            local income = 0
            pcall(function()
                -- tax income from each region
                for r = 0, f:region_list():num_items() - 1 do
                    local region = f:region_list():item_at(r)
                    income = income + (region:tax_income() or 0)
                end
                -- trade income
                income = income + (f:trade_value() or 0)
            end)

            -- economic status
            local trade_deals = 0
            local ok_td, td_val = pcall(function() return f:num_trade_agreements() end)
            if ok_td and td_val then trade_deals = td_val end

            table.insert(results, {
                name = fname,
                display_name = get_display_name(f),
                settlements = settlements, armies = armies,
                wars = wars, treasury = treasury,
                population = population, income = income,
                trade_deals = trade_deals,
                is_human = is_human,
            })
            end -- fog of war else
        end
    end
    return results
end

-- ============================================================
-- OVERALL RANKING (rank-based equal weight)
-- ============================================================
local function compute_overall_scores(factions)
    local cats = { "settlements", "armies", "income", "population" }

    -- for each category, sort factions and assign ranks
    local ranks = {}
    for _, f in ipairs(factions) do
        ranks[f.name] = {}
    end

    for _, cat in ipairs(cats) do
        local sorted = {}
        for idx, f in ipairs(factions) do
            table.insert(sorted, { idx = idx, name = f.name, val = f[cat] or 0 })
        end
        table.sort(sorted, function(a, b) return a.val > b.val end)

        local rank = 1
        for i, entry in ipairs(sorted) do
            if i > 1 and entry.val < sorted[i - 1].val then
                rank = i
            end
            ranks[entry.name][cat] = rank
        end
    end

    -- compute average rank for each faction (lower = better)
    -- also store sub-ranks for display
    for _, f in ipairs(factions) do
        local r = ranks[f.name]
        f.overall = (r.settlements + r.armies + r.income + r.population) / 4
        f.rank_s = r.settlements
        f.rank_m = r.armies       -- "Military" = armies rank
        f.rank_i = r.income
        f.rank_p = r.population
    end
end

-- ============================================================
-- TREND SYSTEM
-- ============================================================
local function take_snapshot(factions)
    local snap = {}
    for _, f in ipairs(factions) do
        snap[f.name] = {
            settlements = f.settlements,
            armies = f.armies,
            wars = f.wars,
            treasury = f.treasury,
            income = f.income or 0,
            population = f.population or 0,
        }
    end
    return snap
end

-- compute ranks for a given category from a snapshot table
-- for "overall", computes rank-based average across all 5 categories
-- returns faction_key -> rank (1-based, lower = better)
local function compute_snapshot_ranks(snapshot, category)
    if category == "overall" then
        local cats = { "settlements", "armies", "income", "population" }
        local entries = {}
        for fkey, data in pairs(snapshot) do
            table.insert(entries, { name = fkey, settlements = data.settlements, armies = data.armies, income = data.income or 0, population = data.population or 0 })
        end

        local cat_ranks = {}
        for _, e in ipairs(entries) do cat_ranks[e.name] = {} end

        for _, cat in ipairs(cats) do
            local sorted = {}
            for _, e in ipairs(entries) do
                table.insert(sorted, { name = e.name, val = e[cat] or 0 })
            end
            table.sort(sorted, function(a, b) return a.val > b.val end)
            local r = 1
            for i, s in ipairs(sorted) do
                if i > 1 and s.val < sorted[i - 1].val then r = i end
                cat_ranks[s.name][cat] = r
            end
        end

        -- average ranks then convert to final ranking
        local avg_list = {}
        for fkey, cr in pairs(cat_ranks) do
            local avg = (cr.settlements + cr.armies + cr.income + cr.population) / 4
            table.insert(avg_list, { name = fkey, avg = avg })
        end
        table.sort(avg_list, function(a, b) return a.avg < b.avg end)

        local result = {}
        local r = 1
        for i, e in ipairs(avg_list) do
            if i > 1 and e.avg > avg_list[i - 1].avg then r = i end
            result[e.name] = r
        end
        return result
    else
        -- map tab names to snapshot data keys
        local snap_key = category
        if category == "military" then snap_key = "armies" end
        if category == "income" or category == "income_dev" then snap_key = "income" end

        -- single category: rank by value descending
        local sorted = {}
        for fkey, data in pairs(snapshot) do
            table.insert(sorted, { name = fkey, val = data[snap_key] or 0 })
        end
        table.sort(sorted, function(a, b) return a.val > b.val end)

        local result = {}
        local r = 1
        for i, e in ipairs(sorted) do
            if i > 1 and e.val < sorted[i - 1].val then r = i end
            result[e.name] = r
        end
        return result
    end
end

-- returns trend string: green +N for improvement, red -N for decline
local function rank_trend_arrow(current_rank, prev_rank, sort_key)
    if not prev_rank then return "" end
    local diff = prev_rank - current_rank
    if diff == 0 then return "" end
    if diff > 0 then
        return " " .. c("green", "+" .. diff)
    else
        return " " .. c("red", tostring(diff))
    end
end

-- ============================================================
-- COALITION TRACKER (reads from smart_diplomacy bridge)
-- ============================================================
local function get_coalition_data()
    -- try to read from smart_diplomacy's global bridge functions
    local coalitions = nil
    local threats = nil

    local ok1, result1 = pcall(function() return GetActiveCoalitions() end)
    if ok1 and result1 then coalitions = result1 end

    local ok2, result2 = pcall(function() return GetFactionThreatScores() end)
    if ok2 and result2 then threats = result2 end

    return coalitions, threats
end

-- compute faction "strength" for coalition display (settlements + armies)
local function get_faction_strength(faction_key, factions_data)
    for _, f in ipairs(factions_data) do
        if f.name == faction_key then
            return f.settlements + f.armies
        end
    end
    return 0
end

local function get_faction_display_from_key(faction_key, factions_data)
    for _, f in ipairs(factions_data) do
        if f.name == faction_key then
            return f.display_name
        end
    end
    -- fallback: clean up the key
    local clean = faction_key:gsub("^rom_", ""):gsub("_", " ")
    return clean:gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b:lower() end)
end

-- ============================================================
-- TEXT BUILDERS
-- ============================================================

-- rank colors: top 5 green, 6-10 yellow, 11+ red
local function get_rank_color(rank)
    if rank <= 5 then return "green"
    elseif rank <= 10 then return "yellow"
    else return "red"
    end
end

local function get_suffix(sort_key, val)
    local suffixes = {
        overall      = { "", "" },
        settlements  = { "", "" },
        military     = { "", "" },
        income       = { "", "" },
        income_dev   = { "", "" },
    }
    local pair = suffixes[sort_key] or { "", "" }
    return (val == 1) and pair[1] or pair[2]
end

local function build_header(turn, faction_count, label)
    local lines = {}
    local function w(s) table.insert(lines, s) end
    w("")
    w("       Turn " .. turn ..
      "  |  " .. faction_count .. " factions" ..
      "  |  " .. c("yellow", label))
    w("")
    return lines
end

local function build_footer(factions_total, shown_count)
    local lines = {}
    local function w(s) table.insert(lines, s) end
    if factions_total > shown_count then
        w("       ... and " .. (factions_total - shown_count) .. " more factions")
    end
    w("")
    w("       AI Uses Population and More")
    w("")
    return lines
end

-- standard ranking view
local function build_rankings(factions, sort_key)
    local turn = scripting.game_interface:model():turn_number()
    local label = CFG.SORT_LABELS[sort_key]

    -- map tab names to data fields for sorting
    local data_key = sort_key
    if sort_key == "military" then data_key = "armies" end
    if sort_key == "income_dev" then data_key = "income" end
    if sort_key == "income" then data_key = "income" end
    if sort_key == "overall" then data_key = "overall" end

    -- for overall, lower is better (avg rank). for everything else, higher is better.
    local sort_ascending = (sort_key == "overall")

    local max_val = 1
    if not sort_ascending then
        for _, f in ipairs(factions) do
            if (f[data_key] or 0) > max_val then max_val = f[data_key] end
        end
    end

    local lines = build_header(turn, #factions, label)
    local function w(s) table.insert(lines, s) end

    -- precompute previous ranks for this category's trend arrows
    -- IMPORTANT: filter snapshot to only include factions in current display list
    -- otherwise ranks from 70+ factions produce misleading +47 type jumps
    local prev_ranks = nil
    if next(prev_snapshot) then
        local filtered_snapshot = {}
        for _, f in ipairs(factions) do
            if prev_snapshot[f.name] then
                filtered_snapshot[f.name] = prev_snapshot[f.name]
            end
        end
        if next(filtered_snapshot) then
            local rank_category = data_key
            if sort_key == "overall" then rank_category = "overall" end
            prev_ranks = compute_snapshot_ranks(filtered_snapshot, rank_category)
        end
    end

    local count = math.min(#factions, CFG.TOP_N)
    for rank = 1, count do
        local f = factions[rank]
        local rc = get_rank_color(rank)

        local name_str = f.display_name
        if #name_str > 22 then name_str = name_str:sub(1, 20) .. ".." end

        -- rank number
        local rank_part = c(rc, "#" .. rank)

        -- faction name
        local name_part = c(rc, name_str)

        -- trend arrow (right after name)
        local arrow = ""
        if prev_ranks then
            arrow = rank_trend_arrow(rank, prev_ranks[f.name], sort_key)
        end

        -- player tag
        if f.is_human then
            name_part = name_part .. " <YOU>"
        end

        -- stat value
        local val = f[data_key] or 0
        local val_str
        if sort_key == "income" then
            -- economic tier based on income (tax + trade revenue)
            local inc = f.income or 0
            local tier_str
            if inc >= 5000 then
                tier_str = c("green", "Thriving")
            elseif inc >= 2000 then
                tier_str = c("green", "Stable")
            elseif inc >= 500 then
                tier_str = c("yellow", "Modest")
            else
                tier_str = c("red", "Poor")
            end
            -- trade deals
            local td = f.trade_deals or 0
            local td_str = tostring(td) .. (td == 1 and " trade deal" or " trade deals")
            val_str = tier_str .. " | " .. td_str
        elseif sort_key == "income_dev" then
            local inc = f.income or 0
            if inc >= 0 then
                val_str = c("green", "+" .. fmt_num(inc)) .. " gold/turn"
            else
                val_str = c("red", fmt_num(inc)) .. " gold/turn"
            end
        elseif sort_key == "overall" then
            -- tier label
            local tier
            if val <= 3 then
                tier = c("green", "Superpower")
            elseif val <= 8 then
                tier = c("yellow", "Great Power")
            elseif val <= 15 then
                tier = "Regional Power"
            elseif val <= 25 then
                tier = "Minor Power"
            elseif val <= 40 then
                tier = "Minor Power"
            else
                tier = "Emerging Faction"
            end
            -- color rank numbers by performance: green=top5, yellow=top15, red=bottom half
            local function rank_color(r, total)
                if not r then return "?" end
                if r <= 5 then return c("green", "#" .. r)
                elseif r <= 15 then return c("yellow", "#" .. r)
                else return c("red", "#" .. r)
                end
            end
            local n = #factions
            -- spelled out sub-category breakdown
            val_str = tier .. "\n"
                .. "          Settlements: " .. rank_color(f.rank_s, n)
                .. "  Military: " .. rank_color(f.rank_m, n)
                .. "  Income: " .. rank_color(f.rank_i, n)
                .. "  Pop: " .. rank_color(f.rank_p, n)
        elseif sort_key == "settlements" then
            -- settlements + population + avg per settlement
            local pop = f.population or 0
            local pop_str
            if pop >= 1000000 then
                pop_str = string.format("%.1fM", pop / 1000000)
            elseif pop >= 1000 then
                pop_str = string.format("%.0fk", pop / 1000)
            else
                pop_str = tostring(math.floor(pop))
            end
            local sett_count = math.floor(val)
            local avg_str = ""
            if sett_count > 0 then
                local avg_pop = pop / sett_count
                if avg_pop >= 1000 then
                    avg_str = " (" .. string.format("%.0fk", avg_pop / 1000) .. " avg)"
                else
                    avg_str = " (" .. tostring(math.floor(avg_pop)) .. " avg)"
                end
            end
            val_str = tostring(sett_count) .. (sett_count == 1 and " settlement" or " settlements") .. " | " .. pop_str .. " pop" .. avg_str
        elseif sort_key == "military" then
            -- show armies + wars combined
            local army_count = f.armies or 0
            local war_count = f.wars or 0
            val_str = tostring(army_count) .. (army_count == 1 and " army" or " armies")
                .. " | " .. tostring(war_count) .. (war_count == 1 and " war" or " wars")
        else
            val_str = tostring(math.floor(val))
        end
        local suffix = get_suffix(sort_key, math.floor(val))
        local stat_part = val_str .. suffix

        -- power bar: top 5 only, in rank color
        local bar = ""
        if rank <= 5 and not sort_ascending and max_val > 0 then
            local bar_len = math.floor((f[data_key] / max_val) * 15)
            if bar_len < 1 and f[data_key] > 0 then bar_len = 1 end
            bar = "  " .. c(rc, string.rep("I", bar_len))
        end

        w("   " .. rank_part .. "  " .. name_part .. arrow .. "  -  " .. stat_part .. bar)
        w("")
    end

    for _, line in ipairs(build_footer(#factions, count)) do
        table.insert(lines, line)
    end

    return table.concat(lines, "\n")
end

-- coalition view: list active coalitions with details
local function build_coalition_view(factions)
    local turn = scripting.game_interface:model():turn_number()
    local lines = build_header(turn, #factions, "COALITIONS")
    local function w(s) table.insert(lines, s) end

    local coalitions, threats = get_coalition_data()

    if not coalitions or #coalitions == 0 then
        w("       No active coalitions.")
        w("")
        -- show top threat scores even without active coalitions
        if threats and next(threats) then
            w("       " .. c("yellow", "THREAT LEVELS:"))
            w("")
            local threat_list = {}
            for fkey, score in pairs(threats) do
                table.insert(threat_list, { key = fkey, score = score })
            end
            table.sort(threat_list, function(a, b) return a.score > b.score end)
            local tcount = math.min(#threat_list, 10)
            for i = 1, tcount do
                local t = threat_list[i]
                local dname = get_faction_display_from_key(t.key, factions)
                local score_str = string.format("%.0f", t.score)
                local color = "green"
                if t.score >= 80 then color = "red"
                elseif t.score >= 50 then color = "yellow" end
                w("       " .. dname .. "  " .. c(color, score_str))
            end
            w("")
        end
        w("       AI Uses Population and More")
        w("")
        return table.concat(lines, "\n")
    end

    for ci, coal in ipairs(coalitions) do
        -- coalition header
        local target_name = get_faction_display_from_key(coal.threat_key, factions)
        local duration = turn - (coal.formed_turn or turn)

        w("   " .. c("yellow", "COALITION #" .. ci) .. "  vs  " .. c("red", target_name))
        w("")

        -- duration
        local dur_str = duration .. (duration == 1 and " turn" or " turns")
        w("       Duration: " .. dur_str)

        -- active coalition — the coalition existing IS the threat
        w("       Status: " .. c("red", "ACTIVE"))

        -- members
        local member_names = {}
        local coalition_strength = 0
        for _, mkey in ipairs(coal.members or {}) do
            local mname = get_faction_display_from_key(mkey, factions)
            table.insert(member_names, mname)
            coalition_strength = coalition_strength + get_faction_strength(mkey, factions)
        end
        w("       Members: " .. c("green", table.concat(member_names, ", ")))

        -- strength comparison
        local target_strength = get_faction_strength(coal.threat_key, factions)
        w("       Strength: " .. c("green", tostring(coalition_strength)) ..
          " vs " .. c("red", tostring(target_strength)))
        w("")
    end

    -- show remaining threat scores below coalitions
    if threats and next(threats) then
        w("       " .. c("yellow", "THREAT LEVELS:"))
        w("")
        local threat_list = {}
        for fkey, score in pairs(threats) do
            table.insert(threat_list, { key = fkey, score = score })
        end
        table.sort(threat_list, function(a, b) return a.score > b.score end)
        local tcount = math.min(#threat_list, 10)
        for i = 1, tcount do
            local t = threat_list[i]
            local dname = get_faction_display_from_key(t.key, factions)
            local score_str = string.format("%.0f", t.score)
            local color = "green"
            if t.score >= 80 then color = "red"
            elseif t.score >= 50 then color = "yellow" end
            w("       " .. dname .. "  " .. c(color, score_str))
        end
        w("")
    end

    w("       AI Uses Population and More")
    w("")
    return table.concat(lines, "\n")
end

-- ============================================================
-- PANEL DISPLAY
-- ============================================================
local function cleanup_panel()
    if State.panel_cleaned then return end

    -- hide sidebar junk
    local hide_these = {
        "room_list", "friends_list",
        "consul_console_input", "consul_send_cmd",
        "consul_history_up_btn", "consul_history_down_btn",
        "consul_page_next_btn", "consul_page_prev_btn",
        "button_lock_chat", "room_list_button_minimize",
        "friends_list_button_minimize",
        "scriptum_entry", "scriptum_entry_text", "toggle_chat",
        "h_line",
    }
    for _, name in ipairs(hide_these) do
        local comp = ui_find(name)
        if comp then pcall(function() comp:SetVisible(false) end) end
    end

    -- repurpose title bar for big heading
    local title_comp = ui_find("title")
    if title_comp then
        pcall(function() title_comp:SetVisible(true) end)
        pcall(function() title_comp:SetStateText("FACTION POWER RANKINGS") end)
    end

    State.panel_cleaned = true
    Log("Panel cleaned")
end

local function show_panel(text)
    local panel = ui_find("consul_scriptum")
    if not panel then
        Log("Panel not found")
        return false
    end

    cleanup_panel()

    local text_comp = ui_find("console_output_text1")
    if text_comp then
        pcall(function() text_comp:SetStateText(text) end)
    else
        pcall(function() panel:SetStateText(text) end)
    end

    pcall(function() panel:SetVisible(true) end)

    -- center panel on screen
    -- panel is 1000x750 from XML, Y center is always 165 (1080 virtual height)
    -- X center depends on actual screen width (ultrawide vs 16:9)
    pcall(function()
        local panel_w = 1000
        local panel_h = 750
        local screen_w = 1920  -- default 16:9
        local screen_h = 1080

        -- try to read actual virtual screen dimensions from root UI
        if scripting.m_root then
            pcall(function()
                local rw, rh = scripting.m_root:Width(), scripting.m_root:Height()
                if rw and rw > 0 then
                    screen_w = rw
                    screen_h = rh
                    Log("Screen from m_root: " .. screen_w .. "x" .. screen_h)
                end
            end)
            -- fallback: try Bounds
            if screen_w == 1920 then
                pcall(function()
                    local rx, ry, rw, rh = scripting.m_root:Bounds()
                    if rw and rw > 100 then
                        screen_w = rw
                        screen_h = rh
                        Log("Screen from m_root:Bounds: " .. screen_w .. "x" .. screen_h)
                    end
                end)
            end
        end

        -- try State.ui_root as backup
        if screen_w == 1920 and State.ui_root then
            pcall(function()
                local rw, rh = State.ui_root:Width(), State.ui_root:Height()
                if rw and rw > 0 then
                    screen_w = rw
                    screen_h = rh
                    Log("Screen from ui_root: " .. screen_w .. "x" .. screen_h)
                end
            end)
            if screen_w == 1920 then
                pcall(function()
                    local rx, ry, rw, rh = State.ui_root:Bounds()
                    if rw and rw > 100 then
                        screen_w = rw
                        screen_h = rh
                        Log("Screen from ui_root:Bounds: " .. screen_w .. "x" .. screen_h)
                    end
                end)
            end
        end

        local center_x = math.floor((screen_w - panel_w) / 2)
        local center_y = math.floor((screen_h - panel_h) / 2)
        panel:MoveTo(center_x, center_y)
        Log("Panel positioned: screen=" .. screen_w .. "x" .. screen_h .. " -> MoveTo(" .. center_x .. ", " .. center_y .. ")")
    end)
    return true
end

local function hide_panel()
    local panel = ui_find("consul_scriptum")
    if panel then pcall(function() panel:SetVisible(false) end) end
    State.is_visible = false
end

-- ============================================================
-- CORE ACTIONS
-- ============================================================
local function refresh()
    local sort_key = CFG.SORT_MODES[State.current_sort_index]

    -- coalition tab uses unfiltered data (coalitions can involve unknown factions)
    -- all other tabs use fog of war filter
    local use_fog = (sort_key ~= "coalition")
    local factions = collect_factions(use_fog)
    Log("Collected " .. #factions .. " factions, sort=" .. sort_key .. " fog=" .. tostring(use_fog))

    -- log first 5 factions
    for i = 1, math.min(5, #factions) do
        local f = factions[i]
        Log("  " .. f.name .. " -> " .. f.display_name .. " wars=" .. f.wars .. " armies=" .. f.armies)
    end

    -- special display modes
    if sort_key == "coalition" then
        local text = build_coalition_view(factions)
        show_panel(text)
        return
    end

    -- compute overall scores for all modes (needed for trend arrows)
    compute_overall_scores(factions)

    -- determine sort field and direction
    local data_key = sort_key
    if sort_key == "military" then data_key = "armies" end
    if sort_key == "income" or sort_key == "income_dev" then data_key = "income" end
    local sort_ascending = (sort_key == "overall")

    if sort_ascending then
        table.sort(factions, function(a, b)
            return (a[data_key] or 0) < (b[data_key] or 0)
        end)
    else
        table.sort(factions, function(a, b)
            return (a[data_key] or 0) > (b[data_key] or 0)
        end)
    end

    local text = build_rankings(factions, sort_key)
    local ok = show_panel(text)
    if ok then
        Log("Panel shown")
    else
        Log("Panel display failed")
    end
end

local function toggle()
    if State.is_visible then
        hide_panel()
    else
        State.is_visible = true
        refresh()
    end
end

local function cycle_and_refresh()
    State.current_sort_index = (State.current_sort_index % #CFG.SORT_MODES) + 1
    if State.is_visible then refresh() end
end

-- ============================================================
-- SAVE / LOAD (trend data persistence)
-- ============================================================
local function OnSavingGame(context)
    Log("TREND SAVE: saving snapshot data...")
    local count = 0
    for fkey, data in pairs(prev_snapshot) do
        local prefix = "_rankings_prev_" .. count .. "_"
        scripting.game_interface:save_named_value(prefix .. "key", fkey, context)
        scripting.game_interface:save_named_value(prefix .. "s", data.settlements or 0, context)
        scripting.game_interface:save_named_value(prefix .. "a", data.armies or 0, context)
        scripting.game_interface:save_named_value(prefix .. "w", data.wars or 0, context)
        scripting.game_interface:save_named_value(prefix .. "t", math.floor(data.treasury or 0), context)
        scripting.game_interface:save_named_value(prefix .. "p", math.floor(data.population or 0), context)
        scripting.game_interface:save_named_value(prefix .. "i", math.floor(data.income or 0), context)
        count = count + 1
    end
    scripting.game_interface:save_named_value("_rankings_prev_count", count, context)
    scripting.game_interface:save_named_value("_rankings_snap_turn", snapshot_turn, context)
    Log("TREND SAVE: " .. count .. " factions saved, turn=" .. snapshot_turn)
end

local function OnLoadingGame(context)
    Log("TREND LOAD: loading snapshot data...")
    prev_snapshot = {}
    local count = scripting.game_interface:load_named_value("_rankings_prev_count", 0, context)
    snapshot_turn = scripting.game_interface:load_named_value("_rankings_snap_turn", 0, context)
    for i = 0, count - 1 do
        local prefix = "_rankings_prev_" .. i .. "_"
        local fkey = scripting.game_interface:load_named_value(prefix .. "key", "", context)
        if fkey ~= "" then
            prev_snapshot[fkey] = {
                settlements = scripting.game_interface:load_named_value(prefix .. "s", 0, context),
                armies      = scripting.game_interface:load_named_value(prefix .. "a", 0, context),
                wars        = scripting.game_interface:load_named_value(prefix .. "w", 0, context),
                treasury    = scripting.game_interface:load_named_value(prefix .. "t", 0, context),
                population  = scripting.game_interface:load_named_value(prefix .. "p", 0, context),
                income      = scripting.game_interface:load_named_value(prefix .. "i", 0, context),
            }
        end
    end
    Log("TREND LOAD: " .. count .. " factions loaded, turn=" .. snapshot_turn)
end

-- snapshot on player turn start
local function OnFactionTurnStart(context)
    local ok, is_human = pcall(function() return context:faction():is_human() end)
    if not ok or not is_human then return end

    local turn = scripting.game_interface:model():turn_number()
    if turn == snapshot_turn then return end  -- already snapped this turn

    Log("TREND: Player turn " .. turn .. " — rotating snapshots")

    -- rotate: current becomes previous
    if next(curr_snapshot) then
        prev_snapshot = curr_snapshot
    end

    -- take new current snapshot
    local factions = collect_factions()
    curr_snapshot = take_snapshot(factions)
    snapshot_turn = turn

    Log("TREND: Snapshot taken, " .. #factions .. " factions")
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================
local function OnUICreated(context)
    if State.ui_ready then return end
    local ok, root = pcall(UIComponent, context.component)
    if ok and root then
        State.ui_root = root
        State.ui_ready = true
        Log("UI root captured")
        local btn = ui_find(CFG.BUTTON_ID)
        if btn then
            pcall(function() btn:SetTooltipText("Faction Power Rankings (click to toggle, click again to cycle sort)", true) end)
            Log("Button found")
        else
            Log("Button NOT found")
        end
    end
end

local function OnComponentLClickUp(context)
    local ok, name = pcall(function() return context.string end)
    if not ok or not name then return end
    if name == CFG.BUTTON_ID then
        if not State.is_visible then
            -- open panel with first sort mode
            State.current_sort_index = 1
            Log("Opening panel")
            local ok2, err = pcall(toggle)
            if not ok2 then Log("ERROR: " .. tostring(err)) end
        elseif State.current_sort_index < #CFG.SORT_MODES then
            -- cycle to next sort
            Log("Cycling sort")
            local ok2, err = pcall(cycle_and_refresh)
            if not ok2 then Log("ERROR: " .. tostring(err)) end
        else
            -- cycled through all sorts, close
            Log("Closing panel")
            hide_panel()
        end
    end
end

-- ============================================================
-- INIT
-- ============================================================
local function setup()
    Log("Registering event handlers...")
    if events.UICreated then table.insert(events.UICreated, OnUICreated) end
    if events.ComponentLClickUp then table.insert(events.ComponentLClickUp, OnComponentLClickUp) end

    -- save/load for trend data
    scripting.AddEventCallBack("SavingGame", OnSavingGame)
    scripting.AddEventCallBack("LoadingGame", OnLoadingGame)
    scripting.AddEventCallBack("FactionTurnStart", OnFactionTurnStart)

    Log("Setup complete")
end

setup()
Log("faction_rankings.lua loaded OK")
