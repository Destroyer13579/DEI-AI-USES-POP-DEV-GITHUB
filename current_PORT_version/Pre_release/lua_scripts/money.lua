-- ************************************************************************
-- ************************************************************************
-- ************************************************************************
-- DIVIDE ET IMPERA
-- AI Money Balancing Script
-- Author: Litharion (Modified)
--
-- Patched: explicit Pop_script_log.txt logging + imperium test bundle
-- ************************************************************************
-- ************************************************************************

-- ***************************************
-- General
-- ***************************************

-- Make the script a module one
module(..., package.seeall);

-- Used to have the object library able to see the variables in this new environment
_G.main_env = getfenv(1);

-- Load libraries
scripting = require "lua_scripts.EpisodicScripting";

-- ************************************************************************
--
-- GENERAL FUNCTIONS
--
-- ************************************************************************

-- Returns the current turn number
function Turn()
	return scripting.game_interface:model():turn_number()
end

-- Checks if an element is in a given list
function contains(element, list)
	for _, v in ipairs(list) do
		if element == v then
			return true;
		end
	end
	return false;
end

-- ************************************************************************
--
-- EXPLICIT POP SCRIPT LOG OUTPUT (Pop_script_log.txt)
--
-- ***********************************

local POP_LOG_FILE = "Pop_script_log.txt";

-- Set to false for release builds to eliminate logging overhead
local MONEY_LOG_ENABLED = false

local function pop_log(line)
	if not MONEY_LOG_ENABLED then return end

	local ok, f = pcall(io.open, POP_LOG_FILE, "a");
	if ok and f then
		f:write(tostring(line) .. "\n");
		f:close();
	else
		out("POP_LOG_FALLBACK | " .. tostring(line));
	end
end

local function fmt_money(n)
	if n == nil then return "nil" end
	return tostring(n)
end

-- Track per-faction start-of-turn treasury and what bundle we applied,
-- so we can log at end-of-turn (income usually updates later).
local ai_money_tracker = {
	turn_start_treasury = {},
	applied_bundle = {},
	applied_tax_bundle = {}
};

-- ***** PERFORMANCE: Bundle-change tracking *****
-- Track the last imperium bundle applied per faction so we skip redundant
-- remove-all + apply cycles when the imperium level hasn't changed.
local ai_last_imperium_bundle = {};
-- Track whether the tax bundle has already been applied per faction
-- (it's always the same bundle, so we only need to apply it once ever).
local ai_tax_bundle_applied = {};

-- ************************************************************************
--
-- AI FINANCIAL ADJUSTMENTS
--
-- ************************************************************************

-- Adjust AI economy by providing a fair tax multiplier rather than direct money injections
function AdjustAIEconomy(context)
	local faction = context:faction();
	local factionName = faction:name();

	if faction:is_human() == false and faction:region_list():num_items() > 0 then
		local t_before = faction:treasury();

		-- record start treasury for end-of-turn delta logging
		ai_money_tracker.turn_start_treasury[factionName] = t_before;

		-- Only apply tax bundle if we haven't already (it's duration 0 = permanent,
		-- so it persists across turns and never needs reapplication).
		if not ai_tax_bundle_applied[factionName] then
			scripting.game_interface:remove_effect_bundle("AI_Fair_Tax_Boost", factionName);
			scripting.game_interface:apply_effect_bundle("AI_Fair_Tax_Boost", factionName, 0);
			ai_tax_bundle_applied[factionName] = true;
		end

		ai_money_tracker.applied_tax_bundle[factionName] = "AI_Fair_Tax_Boost";

		pop_log("[MONEY_LUA] turn="..Turn()
			.." event=FactionTurnStart"
			.." faction="..factionName
			.." treasury_before="..fmt_money(t_before)
			.." applied_tax_bundle=AI_Fair_Tax_Boost"
			.." note=treasury_updates_end_of_turn");
	end
end

scripting.AddEventCallBack("FactionTurnStart", AdjustAIEconomy);

--
--
-- AI Imperium-Based Bonuses
--
function AdjustAIImperiumBonuses(context)
	local faction = context:faction();
	local factionName = faction:name();

	if faction:is_human() == false and faction:region_list():num_items() > 0 then
		local imp = faction:imperium_level();

		-- decide which bundle to apply 
		local desired = "NONE";

		if imp >= 6 then
			desired = "AI_Imperium_Fair_Boost_6";
		elseif imp == 5 then
			desired = "AI_Imperium_Fair_Boost_5";
		elseif imp == 4 then
			desired = "AI_Imperium_Bonus_4";
		elseif imp == 3 then
			desired = "AI_Imperium_Bonus_3";
		elseif imp == 2 then
			desired = "AI_Imperium_Bonus_2";
		else
			desired = "AI_Imperium_Bonus_1";
		end

		-- ***** PERFORMANCE: Only swap bundles if the imperium tier changed *****
		if ai_last_imperium_bundle[factionName] ~= desired then
			-- Remove the old bundle (if any) instead of removing all 13
			local old_bundle = ai_last_imperium_bundle[factionName];
			if old_bundle and old_bundle ~= "NONE" then
				scripting.game_interface:remove_effect_bundle(old_bundle, factionName);
			end

			-- On first run (or after load), clean up any legacy bundles that might exist
			if not old_bundle then
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Bonus_6", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Bonus_5", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Bonus_4", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Bonus_3", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Bonus_2", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Bonus_1", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Fair_Boost_6", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Fair_Boost_5", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Fair_Boost_4", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Fair_Boost_3", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Fair_Boost_2", factionName);
				scripting.game_interface:remove_effect_bundle("AI_Imperium_Fair_Boost_1", factionName);
			end

			scripting.game_interface:apply_effect_bundle(desired, factionName, 0);
			ai_last_imperium_bundle[factionName] = desired;

			pop_log("[MONEY_LUA] turn="..Turn()
				.." event=ImperiumApply"
				.." faction="..factionName
				.." imperium="..tostring(imp)
				.." applied_imperium_bundle="..desired
				.." changed_from="..(old_bundle or "FIRST_RUN"));
		end

		ai_money_tracker.applied_bundle[factionName] = desired;
	end
end

scripting.AddEventCallBack("FactionTurnStart", AdjustAIImperiumBonuses);

-- **********************************************
--
-- END OF TURN TREASURY LOGGING (proves effect impact)
--
-- ************
function LogAITreasuryEndTurn(context)
	local faction = context:faction();
	local factionName = faction:name();

	if faction:is_human() == false and faction:region_list():num_items() > 0 then
		local t_end = faction:treasury();
		local t_start = ai_money_tracker.turn_start_treasury[factionName];
		local delta = "nil";
		if t_start ~= nil then
			delta = tostring(t_end - t_start);
		end

		local imp_bundle = ai_money_tracker.applied_bundle[factionName] or "UNKNOWN";
		local tax_bundle = ai_money_tracker.applied_tax_bundle[factionName] or "UNKNOWN";

		pop_log("[MONEY_LUA] turn="..Turn()
			.." event=FactionTurnEnd"
			.." faction="..factionName
			.." treasury_start="..fmt_money(t_start)
			.." treasury_end="..fmt_money(t_end)
			.." delta="..delta
			.." imperium_bundle="..imp_bundle
			.." tax_bundle="..tax_bundle
			.." note=delta_includes_income_and_spending");
	end
end

scripting.AddEventCallBack("FactionTurnEnd", LogAITreasuryEndTurn);
