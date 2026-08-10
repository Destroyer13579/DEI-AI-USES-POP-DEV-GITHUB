-----------------------
--******* Author: MrTimbe68
--******* Mod "Trade_Regions"
--******* July 2020
-----------------------

--***Changelog***
--12.7.2020 || turned debugging on, uses DeI_utility_functions debug for supply_system
--13.7.2020 || tweaked message events to better describe the actual transaction
--16.7.2020 || Added new triggers both allied and neutral regions, see comments
--23.7.2020 || Added advisor with dynamic counter calculation
--26.7.2020 || Tweaked messages and counter values to give zeros more often
--28.7.2020 || Added another random seed to calculated counter to add more variety
--30.7.2020 || Added info texts that inform lack of funds, cannot purchase if treasury goes < 0
--5.8.2020  || Added info texts for 1 region factions and also price for % chance advisor
--6.8.2020  || Added limit regions saved counter if it gets too big
--7.8.2020  || Added mechanism for deploy button: acquirance happens only if diplomat is deployed (added couple of more advisor texts...)
--10.8.2020 || New way to acquire region, deplomat has to be deployed, also added expiration time/values. 
--             Bug fixes: more checkpoints for "0 <= counter <= 100" should reduce odd bahavior
--11.8.2020 || Couple of new advisor texts added
--21.8.2020 || Added client state/region transaction mechanic
--22.8.2020 || changed transaction cost to factional bundle due to events limits...
--9.9.2022  || Implemented Sold Mechanics, also some changes to transaction (added "dilemma" pay interface)
--11.9.2022 || Tweaked UI and message triggers and texts
--14.9.2022 || Added save/load functions for tables/variables
--14.9.2022 || Update on acquire function -> added major region variable to province calc
-- 2.8.2023 || Added bug fix for situation where byer becomes enemy between turns

-- WIP -> still need pop converion function to be added

--***To-Do-list***
-- Have to see if theres any possibilities to trigger region cost/money add in unision...

--***START***--
module(..., package.seeall);
_G.main_env = getfenv(1);

--******************
-- Load Libraries
--******************

local scripting = require "lua_scripts.EpisodicScripting";
require "DeI_utility_functions";
local lib_diplomat_turns = require "script._lib.regions.diplomat_region_turns";

-- population is resolved LAZILY, not with a load-time require.
-- lua_scripts/population.lua is what pulls this module in (from its own tail), so a
-- top-level `require "lua_scripts.population"` here would be a cyclic require that
-- only works because module(..., package.seeall) registers the module in
-- package.loaded before its body runs. Resolving on first use drops that assumption:
-- every call site below fires in-game, long after population.lua has finished loading.
local population_module = nil
local function GetPopulation()
	if population_module == nil then
		population_module = require "lua_scripts.population";
	end;
	return population_module;
end;

------------------------------
-- TRADE REGIONS  ------------
------------------------------

--******************
-- Local helpers
--******************
-- These are deliberately local. DeI defines its own SupplyGetFactionTreaties in
-- script/_lib/supply_system/supply_system_functions.lua as a TRUE global returning
-- only 2 values (Allied, Enemy). The version below returns 3 (Allied, Enemy, Client)
-- and reads its own treaty-type lists, so it must never be visible outside this file.

local ally_diplomatic_treaty_types = {
	"current_treaty_defensive_alliance",
	"current_treaty_military_alliance",
};

local client_diplomatic_treaty_types = {
	"current_treaty_vassal_of_player",
	"current_treaty_client_of_player",
};

local SpecialCapitalsList = {
"dei_superchain_city_ROME",
"dei_superchain_city_PELLA",
"dei_superchain_city_CARTHAGE",
"dei_superchain_city_SYRACUSE",
"dei_superchain_city_ATHENS",
"dei_superchain_city_ALEXANDRIA",
"dei_superchain_city_PERGAMON",
"dei_superchain_city_ANTIOCH",
"dei_superchain_city_MASSILIA",
"dei_superchain_city_BIBRACTE",
};

-- local so it cannot collide with a DeI-side definition of the same name
local function containsBuildingSuperchain(region, list)
    if region == nil or list == nil then return false end
    for _, v in ipairs(list) do
        if region:building_superchain_exists(v) then
            return true
        end
    end
    return false
end

--Call this to figure out allies/enemies/clients (3 return values, trade-module only)
local function TradeGetFactionTreaties(treaty_details)
local AlliedFactionKeys = {};
local EnemyFactionKeys = {};
local ClientFactionKeys = {};
	for faction, details in pairs(treaty_details) do
	 LogSupply("TradeGetFactionTreaties(treaty_details)","faction: "..tostring(faction));
		for k, treaty in ipairs(details) do
		 LogSupply("TradeGetFactionTreaties(treaty_details)","treaty_details: "..treaty);
			if contains(treaty, ally_diplomatic_treaty_types) then
			 table.insert(AlliedFactionKeys, tostring(faction));
			 LogSupply("TradeGetFactionTreaties(treaty_details)","ally_diplomatic_treaty: "..faction);
			elseif contains(treaty, client_diplomatic_treaty_types) then
			 table.insert(ClientFactionKeys, tostring(faction));
			 LogSupply("TradeGetFactionTreaties(treaty_details)","client_diplomatic_treaty: "..faction);
			elseif treaty == "current_treaty_at_war" then
			 table.insert(EnemyFactionKeys, tostring(faction));
			 LogSupply("TradeGetFactionTreaties(treaty_details)","current_treaty_at_war: "..faction);
			end;
		end;
	end;
	return AlliedFactionKeys, EnemyFactionKeys, ClientFactionKeys
end;


--Random seed/funtion--
-- Seeded off game state, not os.clock(): os.clock() diverges across reloads and
-- between multiplayer clients, which made acquisition rolls non-reproducible and
-- desynced MP. Uses turn number + a stable hash of the faction key, both of which
-- are identical on every client and survive a save/reload.
-- The phase argument keeps the turn-start and turn-end streams distinct; without it
-- both callbacks would reseed identically and replay the same sequence.
local function Diplomat_Acquires_Region_Seed(context, phase)
	if context:faction():is_human() == true
	then
		local seed = scripting.game_interface:model():turn_number() * 1000 + phase;
		local name = context:faction():name();
		for i = 1, string.len(name) do
			seed = seed + string.byte(name, i) * i;
		end;
		math.randomseed(seed);
	end;
end;

local function Diplomat_Acquires_Region_random_seed_turn_start(context)
	Diplomat_Acquires_Region_Seed(context, 1);
end;

local function Diplomat_Acquires_Region_random_seed_turn_end(context)
	Diplomat_Acquires_Region_Seed(context, 2);
end;

local function Diplomat_Acquires_Region_CallMathRandom(cont) 
local i = cont;
	while ( i > 0 )
	do
	math.random(1,100);
	i = i - 1;
	end;
end;

--Advisor Text
local function Diplomat_AR_Advisor(context)
local char = context:character()
	if (char:faction():name() == faction_name_info or char:faction():is_human() == true)
	and char:has_region()
	and char:character_type("dignitary")
	then 
		local region_name = char:region():name()
		local AlliedFactionKeys, EnemyFactionKeys, ClientFactionKeys = TradeGetFactionTreaties(char:faction():treaty_details())
		local diplomat_faction_name = char:faction():name()
		local region_faction_name = char:region():garrison_residence():faction():name()
		local counter = Diplomat_Region_Time_Counter(char, region_name)
		LogSupply("Diplomat_Time_On_Allied_Region()","Counter_Number: "..counter);	
		if counter == -1
		and region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
			then effect.advance_contextual_advice_thread("Region.101.Acquire", 1, context);
			return;
		end;
		if counter == -4
		and region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
			then effect.advance_contextual_advice_thread("Region.104.Acquire", 1, context);
			return;
		end;
		if region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
		and contains(region_faction_name, ClientFactionKeys)
		then 
			if char:region():building_superchain_exists("rom_SettlementMajor")
			or containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
				then
				LogSupply("Diplomat_Time_On_Allied_Region()","Major: "..counter);
				if char:faction():treasury() < 7500
					then effect.advance_contextual_advice_thread("Region.109.Acquire", 1, context);
					return;
				end;
			elseif not char:region():building_superchain_exists("rom_SettlementMajor")
			and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
				then
				LogSupply("Diplomat_Time_On_Allied_Region()","Minor: "..counter);
				if char:faction():treasury() < 3750
					then effect.advance_contextual_advice_thread("Region.110.Acquire", 1, context);
					return;
				end;
			end;
		end;
		if region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
		and not contains(region_faction_name, ClientFactionKeys)
		then 
			if char:region():building_superchain_exists("rom_SettlementMajor")
			or containsBuildingSuperchain(char:region(), SpecialCapitalsList)
				then
				LogSupply("Diplomat_Time_On_Allied_Region()","Major: "..counter);
				if char:faction():treasury() < 25000
					then effect.advance_contextual_advice_thread("Region.102.Acquire", 1, context);
					return;
				end;
			elseif not char:region():building_superchain_exists("rom_SettlementMajor")
			and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)
				then
				LogSupply("Diplomat_Time_On_Allied_Region()","Minor: "..counter);
				if char:faction():treasury() < 12500
					then effect.advance_contextual_advice_thread("Region.103.Acquire", 1, context);
					return;
				end;
			end;
		end;
		if region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
		and contains(region_faction_name, ClientFactionKeys)
		and Diplomat_Button_Flag[region_name] == true
		then 
			if char:region():building_superchain_exists("rom_SettlementMajor")
			or containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
				then
				if char:faction():treasury() >= 7500
					then effect.advance_contextual_advice_thread("Region.108.Acquire", 1, context);
					LogSupply("Diplomat_Time_On_Allied_Region()","Major: "..counter);
					LogSupply("Diplomat_Time_On_Allied_Region()","Button_Flag_True_Region: "..region_name);
					return;
				end;
			elseif not char:region():building_superchain_exists("rom_SettlementMajor")
			and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
				then
				if char:faction():treasury() >= 3750
					then effect.advance_contextual_advice_thread("Region.107.Acquire", 1, context);
					LogSupply("Diplomat_Time_On_Allied_Region()","Minor: "..counter);
					LogSupply("Diplomat_Time_On_Allied_Region()","Button_Flag_True_Region: "..region_name);
					return;
				end;
			end;
		end;
		if region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
		and not contains(region_faction_name, ClientFactionKeys)
		and Diplomat_Button_Flag[region_name] == true
		then 
			if char:region():building_superchain_exists("rom_SettlementMajor")
			or containsBuildingSuperchain(char:region(), SpecialCapitalsList)
				then 
				if char:faction():treasury() >= 25000
					then effect.advance_contextual_advice_thread("Region.106.Acquire", 1, context);
					LogSupply("Diplomat_Time_On_Allied_Region()","Major: "..counter);
					LogSupply("Diplomat_Time_On_Allied_Region()","Button_Flag_True_Region: "..region_name);
					return;
				end;
			elseif not char:region():building_superchain_exists("rom_SettlementMajor")
			and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)
				then 
				if char:faction():treasury() >= 12500
					then effect.advance_contextual_advice_thread("Region.105.Acquire", 1, context);
					LogSupply("Diplomat_Time_On_Allied_Region()","Minor: "..counter);
					LogSupply("Diplomat_Time_On_Allied_Region()","Button_Flag_True_Region: "..region_name);
					return;
				end;
			end;
		end;
		if region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
		and contains(region_faction_name, ClientFactionKeys)
		then
			if char:region():building_superchain_exists("rom_SettlementMajor")
			or containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
				then 
				effect.advance_contextual_advice_thread("Client_Major_Region."..counter..".Acquire", 1, context);
				LogSupply("Diplomat_Time_On_Allied_Region()","Give_Advisor_Counter_Major: "..counter);
				return;
			elseif not char:region():building_superchain_exists("rom_SettlementMajor")
			and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
				then 
				effect.advance_contextual_advice_thread("Client_Region."..counter..".Acquire", 1, context);
				LogSupply("Diplomat_Time_On_Allied_Region()","Give_Advisor_Counter_Minor: "..counter);
				return;
			end;
		end;
		if region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, EnemyFactionKeys)
		and not contains(region_faction_name, ClientFactionKeys)
		then
			if char:region():building_superchain_exists("rom_SettlementMajor")
			or containsBuildingSuperchain(char:region(), SpecialCapitalsList)
				then
				effect.advance_contextual_advice_thread("Major_Region."..counter..".Acquire", 1, context);
				LogSupply("Diplomat_Time_On_Allied_Region()","Give_Advisor_Counter_Major: "..counter);
				return;
			elseif not char:region():building_superchain_exists("rom_SettlementMajor")
			and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)
				then
				effect.advance_contextual_advice_thread("Region."..counter..".Acquire", 1, context);
				LogSupply("Diplomat_Time_On_Allied_Region()","Give_Advisor_Counter_Minor: "..counter);
				return;
			end;
		end;
	end;
end;

local function DiplomatOnAlliedLand(context)
local char = context:character()
	if char:faction():is_human() == true 
	and char:has_region()
	and char:character_type("dignitary")
	then 
		local AlliedFactionKeys, EnemyFactionKeys, ClientFactionKeys = TradeGetFactionTreaties(char:faction():treaty_details())
		local region_name = char:region():name()
		local diplomat_faction_name = char:faction():name()
		local region_faction_name = char:region():garrison_residence():faction():name()
		local counter = Diplomat_Region_Time_Counter(char, region_name)
		LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." Chance to get Region: "..counter.."%");
		local random_number = math.random(1, 100)
		LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." Math.Random_Number: "..random_number)
		if Diplomat_Button_Flag[region_name] == true
		and region_faction_name ~= diplomat_faction_name
			then 
			if char:is_deployed()
				then 
				if contains(region_faction_name, ClientFactionKeys)
					then 
					if char:region():building_superchain_exists("rom_SettlementMajor")
					or containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
					and char:faction():treasury() >= 7500
						then Diplomat_Acquire_Client_Region_Flag[region_name] = true
						LogSupply("Diplomat_Time_On_Allied_Region()","Client_Region_Acquisition_True: "..region_name)
						return --Deal made!
					elseif not char:region():building_superchain_exists("rom_SettlementMajor")
					and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
					and char:faction():treasury() >= 3750
						then Diplomat_Acquire_Client_Region_Flag[region_name] = true
						LogSupply("Diplomat_Time_On_Allied_Region()","Client_Region_Acquisition_True: "..region_name)
						return --Deal made!
					end
				else 
					if char:region():building_superchain_exists("rom_SettlementMajor")
					or containsBuildingSuperchain(char:region(), SpecialCapitalsList)
					and char:faction():treasury() >= 25000
						then Diplomat_Acquire_Region_Flag[region_name] = true
						LogSupply("Diplomat_Time_On_Allied_Region()","Region_Acquisition_True: "..region_name)
						return --Deal made!
					elseif not char:region():building_superchain_exists("rom_SettlementMajor") 
					and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)
					and char:faction():treasury() >= 12500
						then Diplomat_Acquire_Region_Flag[region_name] = true
						LogSupply("Diplomat_Time_On_Allied_Region()","Region_Acquisition_True: "..region_name)
						return --Deal made!
					end
				end
			else
				counter = counter - 10
				LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." After Expiration: "..counter)
				Diplomat_Time_On_Allied_Region[region_name] = counter
				if counter <= 0
					then
					Trade_Expiration_Flag[region_name] = true
					Diplomat_Time_On_Allied_Region[region_name] = 0
					LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Trade_Expiration_Flag_True")
				end
				return --do not count enymore
			end
		--Make flag true if hit...
		elseif Diplomat_Button_Flag[region_name] == false
		and region_faction_name ~= diplomat_faction_name
			then
			if counter ~= -1
			and counter ~= -4
			and (random_number >= 1 and random_number <= counter)
				then 
				if contains(region_faction_name, ClientFactionKeys)
					then
					if char:region():building_superchain_exists("rom_SettlementMajor")
					or containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
						then
						if char:faction():treasury() >= 7500
							then Diplomat_Button_Flag[region_name] = true
							LogSupply("Diplomat_Time_On_Allied_Region()","Region_Button_Flag_True: "..region_name)
							return --do not count enymore
						end;
					elseif not char:region():building_superchain_exists("rom_SettlementMajor")
					and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
						then
						if char:faction():treasury() >= 3750
							then Diplomat_Button_Flag[region_name] = true
							LogSupply("Diplomat_Time_On_Allied_Region()","Region_Button_Flag_True: "..region_name)
							return --do not count enymore
						end;
					end;
				elseif not contains(region_faction_name, ClientFactionKeys)
					then
					if char:region():building_superchain_exists("rom_SettlementMajor")
					or containsBuildingSuperchain(char:region(), SpecialCapitalsList)
						then
						if char:faction():treasury() >= 25000
							then Diplomat_Button_Flag[region_name] = true
							LogSupply("Diplomat_Time_On_Allied_Region()","Region_Button_Flag_True: "..region_name)
							return --do not count enymore
						end;
					elseif not char:region():building_superchain_exists("rom_SettlementMajor")
					and not containsBuildingSuperchain(char:region(), SpecialCapitalsList)
						then
						if char:faction():treasury() >= 12500
							then Diplomat_Button_Flag[region_name] = true
							LogSupply("Diplomat_Time_On_Allied_Region()","Region_Button_Flag_True: "..region_name)
							return --do not count enymore
						end;
					end;
				end;
			end;
		end;
		if counter ~= -1
		and counter ~= -4
		then
		--mix counter a bit for next round if not hit
		local mix_counter = math.random(1, 100)
			if (mix_counter > 0 and mix_counter <= 20)
				then counter = math.ceil(counter * 0.6)
				LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." Mix.Counter 0.6: "..counter)
			end
			if (mix_counter > 20 and mix_counter <= 40)
				then counter = math.ceil(counter * 0.8)
				LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." Mix.Counter 0.8: "..counter)
			end
			if (mix_counter > 40 and mix_counter <= 60)
				then counter = math.ceil(counter * 1)
				LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." Mix.Counter 1: "..counter)
			end
			if (mix_counter > 60 and mix_counter <= 80)
				then counter = math.ceil(counter * 1.2)
				LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." Mix.Counter 1.2: "..counter)
			end
			if (mix_counter > 80 and mix_counter <= 100)
				then counter = math.ceil(counter * 1.4)
				LogSupply("Diplomat_Time_On_Allied_Region()","Diplomat_In_Region: "..region_name.." Mix.Counter 1.4: "..counter)
			end;
			if counter < 0
				then counter = 0
			elseif counter > 100
				then counter = 100
			end;
		end;
		--reset flags if own region
		if region_faction_name == diplomat_faction_name
			then Diplomat_Button_Flag[region_name] = false
		end
	Diplomat_Time_On_Allied_Region[region_name] = counter
	end;
end;

-- SpecialCapitalsList and containsBuildingSuperchain are now declared as locals
-- at the top of this file, above their first use.


function Diplomat_Region_Time_Counter(char, region_name)
local counter = 0
local new_counter = 0
local counter_reducer = 0
local region_faction_name = char:region():garrison_residence():faction():name()
local AlliedFactionKeys, EnemyFactionKeys, ClientFactionKeys = TradeGetFactionTreaties(char:faction():treaty_details())
--local region_name = char:region():name()
	if containsBuildingSuperchain(char:region(), SpecialCapitalsList)--(char:region():building_superchain_exists("dei_superchain_city_ROME") or char:region():building_superchain_exists("dei_superchain_city_PELLA") or char:region():building_superchain_exists("dei_superchain_city_CARTHAGE") or char:region():building_superchain_exists("dei_superchain_city_SYRACUSE") or char:region():building_superchain_exists("dei_superchain_city_ATHENS") or char:region():building_superchain_exists("dei_superchain_city_ALEXANDRIA") or char:region():building_superchain_exists("dei_superchain_city_PERGAMON") or char:region():building_superchain_exists("dei_superchain_city_ANTIOCH") or char:region():building_superchain_exists("dei_superchain_city_MASSILIA") or char:region():building_superchain_exists("dei_superchain_city_BIBRACTE"))
	and not contains(region_faction_name, ClientFactionKeys)
		then
			counter = -1;
			LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Return_counter: "..counter)
			return counter;
	else
		local char_faction = char:faction()
		local ai_faction = char:region():garrison_residence():faction()
		local diplomat_faction_name = char:faction():name()
		local province = char:region():province_name()
		local ai_matched_regions = 0
		local player_matched_regions = 0
		local faction_regions_count = 0
		local ai_faction_regions_count = 0
		local player_owns_province_capital = false
		LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." Diplomat Found: "..province)
		--check how many regions Player has
		local factions_regions = char_faction:region_list()
		for i = 0, factions_regions:num_items() - 1 do
			local f_region = factions_regions:item_at(i)
			local region_province_name = f_region:province_name()
			if diplomat_faction_name == f_region:garrison_residence():faction():name()
				then faction_regions_count = faction_regions_count + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." Region Count: "..faction_regions_count)
				--Who owns province capital?
				if f_region:building_superchain_exists("rom_SettlementMajor")
					then
					local capital_region_name = f_region:name()
					--player owns the province capital
					player_owns_province_capital = true
					LogSupply("Diplomat_Time_On_Allied_Region()","Province: "..region_province_name.." Player_owns_province_capital: "..capital_region_name)
				end;
			end;
			--This calculation tells how many regions Player ownes in particular province, used later...
			if region_province_name == province then
				player_matched_regions = player_matched_regions + 1;
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." Matched Regions: "..player_matched_regions);
			end;
		end;
		
		--check how many regions AI has
		if ai_faction ~= char_faction
		then
			local ai_factions_regions = ai_faction:region_list()
			for j = 0, ai_factions_regions:num_items() - 1 do
				local ai_region = ai_factions_regions:item_at(j)
				local ai_region_province_name = ai_region:province_name()
				if region_faction_name == ai_region:garrison_residence():faction():name()
					then ai_faction_regions_count = ai_faction_regions_count + 1
					LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." Region Count: "..ai_faction_regions_count)
					if ai_region:building_superchain_exists("rom_SettlementMajor")
						then
						local capital_region_name = ai_region:name()
						--AI owns the province capital
						player_owns_province_capital = false
						LogSupply("Diplomat_Time_On_Allied_Region()","Province: "..ai_region_province_name.." AI_owns_province_capital: "..capital_region_name)
					end;
				end;
				--This calculation tells how many regions AI ownes in particular province, used later...
				if ai_region_province_name == province then
					ai_matched_regions = ai_matched_regions + 1;
					LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." Matched Regions: "..ai_matched_regions);
				end;
			end;
			--break if only one region...
			if ai_faction_regions_count == 1
			and not contains(region_faction_name, ClientFactionKeys)
				then counter = -4;
				LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Return_counter: "..counter)
				return counter;
			end;
		end;
		
		for r,t in pairs (Diplomat_Time_On_Allied_Region) do
			if r == region_name then
				counter = t
				LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Return_old_counter: "..counter)
				if Diplomat_Button_Flag[region_name] == true
					then 
					if counter < 0
						then counter = 0
					elseif counter > 100
						then counter = 100
					end;
					return counter;
				end;
			end;
		end;
		
		--decrease the counter if it gets too big...
		if counter <= 10
			then counter_reducer = 0.6
		elseif counter <= 20
			then counter_reducer = 0.5
		elseif counter <= 30
			then counter_reducer = 0.4
		elseif counter <= 40
			then counter_reducer = 0.3
		elseif counter <= 50
			then counter_reducer = 0.2
		else counter_reducer = 0.1
		end
		
		
		if region_faction_name ~= diplomat_faction_name
		and contains(region_faction_name, ClientFactionKeys)
			then
			--diplomat skills
			if char:number_of_traits() >= 5
				then
				new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect >= 5: "..region_name)
			elseif char:number_of_traits() >= 3
				then
				new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect >= 3: "..region_name)
			else
				new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect: "..region_name)
			end
			--culture effect
			if char:region():majority_religion() == char:faction():state_religion()
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." culture dominant effect: "..region_name)
			else
				new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." culture effect: "..region_name)
			end
			--number of own regions in province
			if player_matched_regions == 3
				then new_counter = new_counter + 10
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 3: "..region_name)
			elseif player_matched_regions == 2
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 2: "..region_name)
			elseif player_matched_regions == 1
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 1: "..region_name)
			elseif player_matched_regions == 0
				then new_counter = new_counter - 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 0: "..region_name)
			end
			--number of AI regions in province
			if ai_matched_regions == 4
				then new_counter = new_counter - 9
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." number of AI regions in province 4: "..region_name)
			elseif ai_matched_regions == 3
				then new_counter = new_counter - 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." number of AI regions in province 3: "..region_name)
			elseif ai_matched_regions == 2
				then new_counter = new_counter - 3
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." number of AI regions in province 2: "..region_name)
			elseif ai_matched_regions == 1
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." number of AI regions in province 1: "..region_name)
			end
			--who owns province capital?
			if player_owns_province_capital == true
				then new_counter = new_counter + 6
			elseif player_owns_province_capital == false
				then new_counter = new_counter - 2
			end
			--diplomat faction treasury
			if char:faction():treasury() >= 150000
				then new_counter = new_counter + 7
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 150000: "..region_name)
			elseif char:faction():treasury() >= 125000
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 125000: "..region_name)
			elseif char:faction():treasury() >= 100000
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 100000: "..region_name)
			elseif char:faction():treasury() >= 75000
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 75000: "..region_name)
			elseif char:faction():treasury() >= 50000
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 50000: "..region_name)
			elseif char:faction():treasury() >= 25000
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 25000: "..region_name)
			elseif char:faction():treasury() >= 0
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 0: "..region_name)
			end
			--region faction treasury
			if char:faction():treasury() <= 25000
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region faction treasury <= 25000: "..region_name)
			elseif char:faction():treasury() <= 50000
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region faction treasury <= 50000: "..region_name)
			elseif char:faction():treasury() <= 75000
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region faction treasury <= 75000: "..region_name)
			elseif char:faction():treasury() <= 100000
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region faction treasury <= 100000: "..region_name)
			elseif char:faction():treasury() <= 125000
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region faction treasury <= 125000: "..region_name)
			elseif char:faction():treasury() <= 150000
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region faction treasury <= 150000: "..region_name)
			elseif char:faction():treasury() > 150000
				then new_counter = new_counter - 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region faction treasury > 150000: "..region_name)
			end
			--how many regions player has
			if faction_regions_count >= 13
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 13: "..region_name)
			elseif faction_regions_count >= 11
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 11: "..region_name)
			elseif faction_regions_count >= 9
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 9: "..region_name)
			elseif faction_regions_count >= 7
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 7: "..region_name)
			elseif faction_regions_count >= 5
				then new_counter = new_counter + 7
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 5: "..region_name)
			elseif faction_regions_count >= 3
				then new_counter = new_counter + 8
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 3: "..region_name)
			elseif faction_regions_count == 1
				then new_counter = new_counter + 9
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..diplomat_faction_name.." how many regions player has == 1: "..region_name)
			end
			--how many regions AI has
			if ai_faction_regions_count >= 13
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." how many regions AI has >= 13: "..region_name)
			elseif ai_faction_regions_count >= 11
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." how many regions AI has >= 11: "..region_name)
			elseif ai_faction_regions_count >= 9
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." how many regions AI has >= 9: "..region_name)
			elseif ai_faction_regions_count >= 7
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." how many regions AI has >= 7: "..region_name)
			elseif ai_faction_regions_count >= 5
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." how many regions AI has >= 5: "..region_name)
			elseif ai_faction_regions_count >= 3
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." how many regions AI has >= 3: "..region_name)
			elseif ai_faction_regions_count >= 1
				then new_counter = new_counter - 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." how many regions AI has >= 1: "..region_name)
			end
			--if Major city
			if char:region():building_superchain_exists("rom_SettlementMajor")
				then new_counter = new_counter - 2;
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." Is Major City: "..region_name)
			end;
			--if Capital
			if char:region():garrison_residence():faction():home_region()
				then new_counter = new_counter - 3;
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." Is Capital: "..region_name)
			end;
			--region public order
			if char:region():garrison_residence():region():public_order() >= 75
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= 75: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 50
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= 50: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 25
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= 25: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 0
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= 0: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -25
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= -25: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -50
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= -50: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -75
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= -75: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -100
				then new_counter = new_counter + 7
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." region public order >= -100: "..region_name)
			end;
		elseif region_faction_name ~= diplomat_faction_name
		and contains(region_faction_name, AlliedFactionKeys)
			then
			--diplomat skills
			if char:number_of_traits() >= 5
				then
				new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect >= 5: "..region_name)
			elseif char:number_of_traits() >= 3
				then
				new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect >= 3: "..region_name)
			else
				new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect: "..region_name)
			end
			--culture effect
			if char:region():majority_religion() == char:faction():state_religion()
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." culture dominant effect: "..region_name)
			else
				new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." culture effect: "..region_name)
			end
			--number of own regions in province
			if player_matched_regions == 3
				then new_counter = new_counter + 9
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 3: "..region_name)
			elseif player_matched_regions == 2
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 2: "..region_name)
			elseif player_matched_regions == 1
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 1: "..region_name)
			elseif player_matched_regions == 0
				then new_counter = new_counter - 7
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 0: "..region_name)
			end
			--number of AI regions in province
			if ai_matched_regions == 4
				then new_counter = new_counter - 10
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 4: "..region_name)
			elseif ai_matched_regions == 3
				then new_counter = new_counter - 7
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 3: "..region_name)
			elseif ai_matched_regions == 2
				then new_counter = new_counter - 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 2: "..region_name)
			elseif ai_matched_regions == 1
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 1: "..region_name)
			end
			--who owns province capital?
			if player_owns_province_capital == true
				then new_counter = new_counter + 5
			elseif player_owns_province_capital == false
				then new_counter = new_counter - 3
			end
			--diplomat faction treasury
			if char:faction():treasury() >= 150000
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 150000: "..region_name)
			elseif char:faction():treasury() >= 125000
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 125000: "..region_name)
			elseif char:faction():treasury() >= 100000
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 100000: "..region_name)
			elseif char:faction():treasury() >= 75000
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 75000: "..region_name)
			elseif char:faction():treasury() >= 50000
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 50000: "..region_name)
			elseif char:faction():treasury() >= 25000
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 25000: "..region_name)
			elseif char:faction():treasury() >= 0
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 0: "..region_name)
			end
			--region faction treasury
			if char:faction():treasury() <= 25000
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 25000: "..region_name)
			elseif char:faction():treasury() <= 50000
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 50000: "..region_name)
			elseif char:faction():treasury() <= 75000
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 75000: "..region_name)
			elseif char:faction():treasury() <= 100000
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 100000: "..region_name)
			elseif char:faction():treasury() <= 125000
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 125000: "..region_name)
			elseif char:faction():treasury() <= 150000
				then new_counter = new_counter - 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 150000: "..region_name)
				elseif char:faction():treasury() > 150000
				then new_counter = new_counter - 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury > 150000: "..region_name)
			end
			--how many regions player has
			if faction_regions_count >= 13
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 13: "..region_name)
			elseif faction_regions_count >= 11
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 11: "..region_name)
			elseif faction_regions_count >= 9
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 9: "..region_name)
			elseif faction_regions_count >= 7
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 7: "..region_name)
			elseif faction_regions_count >= 5
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 5: "..region_name)
			elseif faction_regions_count >= 3
				then new_counter = new_counter + 7
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 3: "..region_name)
			elseif faction_regions_count == 1
				then new_counter = new_counter + 8
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has == 1: "..region_name)
			end
			--how many regions AI has
			if ai_faction_regions_count >= 13
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 13: "..region_name)
			elseif ai_faction_regions_count >= 11
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 11: "..region_name)
			elseif ai_faction_regions_count >= 9
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 9: "..region_name)
			elseif ai_faction_regions_count >= 7
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 7: "..region_name)
			elseif ai_faction_regions_count >= 5
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 5: "..region_name)
			elseif ai_faction_regions_count >= 3
				then new_counter = new_counter - 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 3: "..region_name)
			elseif ai_faction_regions_count >= 1
				then new_counter = new_counter - 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 1: "..region_name)
			end
			--if Major city
			if char:region():building_superchain_exists("rom_SettlementMajor")
				then new_counter = new_counter - 3;
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." Is Major City: "..region_name)
			end;
			--if Capital
			if char:region():garrison_residence():faction():home_region()
				then new_counter = new_counter - 4;
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." Is Capital: "..region_name)
			end;
			--region public order
			if char:region():garrison_residence():region():public_order() >= 75
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 75: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 50
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 50: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 25
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 25: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 0
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 0: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -25
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -25: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -50
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -50: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -75
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -75: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -100
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -100: "..region_name)
			end;
		elseif region_faction_name ~= diplomat_faction_name
		and not contains(region_faction_name, AlliedFactionKeys)
		and not contains(region_faction_name, EnemyFactionKeys)
		and not contains(region_faction_name, ClientFactionKeys)
			then
			--diplomat skills
			if char:number_of_traits() >= 5
				then
				new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect >= 5: "..region_name)
			elseif char:number_of_traits() >= 3
				then
				new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect >= 3: "..region_name)
			else
				new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat skills effect: "..region_name)
			end
			--culture effect
			if char:region():majority_religion() == char:faction():state_religion()
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." culture dominant effect: "..region_name)
			else
				new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." culture effect: "..region_name)
			end
			--number of own regions in province
			if player_matched_regions == 3
				then new_counter = new_counter + 8
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 3: "..region_name)
			elseif player_matched_regions == 2
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 2: "..region_name)
			elseif player_matched_regions == 1
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 1: "..region_name)
			elseif player_matched_regions == 0
				then new_counter = new_counter - 8
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." number of own regions in province 0: "..region_name)
			end
			--number of AI regions in province
			if ai_matched_regions == 4
				then new_counter = new_counter - 11
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 4: "..region_name)
			elseif ai_matched_regions == 3
				then new_counter = new_counter - 8
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 3: "..region_name)
			elseif ai_matched_regions == 2
				then new_counter = new_counter - 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 2: "..region_name)
			elseif ai_matched_regions == 1
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." number of AI regions in province 1: "..region_name)
			end
			--who owns province capital?
			if player_owns_province_capital == true
				then new_counter = new_counter + 4
			elseif player_owns_province_capital == false
				then new_counter = new_counter - 4
			end
			--diplomat faction treasury
			if char:faction():treasury() >= 150000
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 150000: "..region_name)
			elseif char:faction():treasury() >= 125000
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 125000: "..region_name)
			elseif char:faction():treasury() >= 100000
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 100000: "..region_name)
			elseif char:faction():treasury() >= 75000
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 75000: "..region_name)
			elseif char:faction():treasury() >= 50000
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 50000: "..region_name)
			elseif char:faction():treasury() >= 25000
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 25000: "..region_name)
			elseif char:faction():treasury() >= 0
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." diplomat faction treasury >= 0: "..region_name)
			end
			--region faction treasury
			if char:faction():treasury() <= 25000
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 25000: "..region_name)
			elseif char:faction():treasury() <= 50000
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 50000: "..region_name)
			elseif char:faction():treasury() <= 75000
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 75000: "..region_name)
			elseif char:faction():treasury() <= 100000
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 100000: "..region_name)
			elseif char:faction():treasury() <= 125000
				then new_counter = new_counter - 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 125000: "..region_name)
			elseif char:faction():treasury() <= 150000
				then new_counter = new_counter - 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury <= 150000: "..region_name)
			elseif char:faction():treasury() > 150000
				then new_counter = new_counter - 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region faction treasury > 150000: "..region_name)
			end
			--how many regions player has
			if faction_regions_count >= 13
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 13: "..region_name)
			elseif faction_regions_count >= 11
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 11: "..region_name)
			elseif faction_regions_count >= 9
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 9: "..region_name)
			elseif faction_regions_count >= 7
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 7: "..region_name)
			elseif faction_regions_count >= 5
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 5: "..region_name)
			elseif faction_regions_count >= 3
				then new_counter = new_counter + 6
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has >= 3: "..region_name)
			elseif faction_regions_count == 1
				then new_counter = new_counter + 7
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..diplomat_faction_name.." how many regions player has == 1: "..region_name)
			end
			--how many regions AI has
			if ai_faction_regions_count >= 13
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 13: "..region_name)
			elseif ai_faction_regions_count >= 11
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 11: "..region_name)
			elseif ai_faction_regions_count >= 9
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 9: "..region_name)
			elseif ai_faction_regions_count >= 7
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 7: "..region_name)
			elseif ai_faction_regions_count >= 5
				then new_counter = new_counter - 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 5: "..region_name)
			elseif ai_faction_regions_count >= 3
				then new_counter = new_counter - 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 3: "..region_name)
			elseif ai_faction_regions_count >= 1
				then new_counter = new_counter - 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." how many regions AI has >= 1: "..region_name)
			end
			--if Major city
			if char:region():building_superchain_exists("rom_SettlementMajor")
				then new_counter = new_counter - 4;
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." Is Major City: "..region_name)
			end;
			--if Capital
			if char:region():garrison_residence():faction():home_region()
				then new_counter = new_counter - 5;
				LogSupply("Diplomat_Time_On_Client_Region()","Faction: "..region_faction_name.." Is Capital: "..region_name)
			end;
			--region public order
			if char:region():garrison_residence():region():public_order() >= 75
				then new_counter = new_counter - 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 75: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 50
				then new_counter = new_counter - 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 50: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 25
				then new_counter = new_counter + 0
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 25: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= 0
				then new_counter = new_counter + 1
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= 0: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -25
				then new_counter = new_counter + 2
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -25: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -50
				then new_counter = new_counter + 3
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -50: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -75
				then new_counter = new_counter + 4
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -75: "..region_name)
			elseif char:region():garrison_residence():region():public_order() >= -100
				then new_counter = new_counter + 5
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction: "..region_faction_name.." region public order >= -100: "..region_name)
			end;
		else counter = 0;
		return counter;
		--we're on own land or enemy and thus want to clear counter...
		end;
		
		counter = math.ceil(counter + (new_counter * counter_reducer))
		LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Return_new_counter: "..new_counter)
		LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Return_counter_reducer: "..counter_reducer)
		
		if counter < 0
			then counter = 0
		elseif counter > 100
			then counter = 100
		end;
	-- fix counter if -0
	counter = math.abs(counter)
	return counter;
	end;
end;

---- Region acquired via diplomacy ----
local function Show_Message_Region_Acquired_Via_Diplomacy(context)
	local curr_faction = context:faction()
    local diplomat_faction_name = curr_faction:name()
    if curr_faction:is_human() == true then
        local region_list = scripting.game_interface:model():world():region_manager():region_list()
        for j = 0, region_list:num_items() - 1 do
            local region = region_list:item_at(j)
            local region_name = region:name()
            local turn_reducer = 0
            local x = region:settlement():display_position_x()
            local y = region:settlement():display_position_y()
            local region_faction_name = region:garrison_residence():faction():name()
			--faction already owns the region
			if diplomat_faction_name == region:garrison_residence():faction():name()
				then
				Diplomat_Time_On_Allied_Region[region_name] = 0
				Diplomat_Acquire_Region_Flag[region_name] = false
				Diplomat_Button_Flag[region_name] = false
				LogSupply("Diplomat_Time_On_Allied_Region()","Faction already owns the region...")
			end
            if Diplomat_Acquire_Region_Flag[region_name] == true 
				then 
				if region:building_superchain_exists("rom_SettlementMajor")
					then scripting.game_interface:show_message_event("custom_event_851", x, y)
					LogSupply("Diplomat_Acquired_Region_Message()","Message_Region: "..region_name)
					scripting.game_interface:transfer_region_to_faction(region_name, diplomat_faction_name)
					GetPopulation().ConvertPopulationClasses(curr_faction, region_name)
--					scripting.game_interface:apply_effect_bundle("Region_Trade_Deal_20000", diplomat_faction_name, 1)
					scripting.game_interface:trigger_custom_dilemma(diplomat_faction_name, "trade_region_interface_20000", "payload { money -20000; }", "payload { money -20000; }" ,true)
					scripting.game_interface:treasury_mod(region_faction_name, 20000)
					LogSupply("Diplomat_Time_On_Allied_Region()","Transaction_cost_20000"..diplomat_faction_name)
					Diplomat_Time_On_Allied_Region[region_name] = 0
					Diplomat_Acquire_Region_Flag[region_name] = false
					Diplomat_Button_Flag[region_name] = false
				else
					scripting.game_interface:show_message_event("custom_event_850", x, y)
					LogSupply("Diplomat_Acquired_Region_Message()","Message_Region: "..region_name)
					scripting.game_interface:transfer_region_to_faction(region_name, diplomat_faction_name)
					GetPopulation().ConvertPopulationClasses(curr_faction, region_name)
--					scripting.game_interface:apply_effect_bundle("Region_Trade_Deal_10000", diplomat_faction_name, 1)
					scripting.game_interface:trigger_custom_dilemma(diplomat_faction_name, "trade_region_interface_10000", "payload { money -10000; }", "payload { money -10000; }" ,true)
					scripting.game_interface:treasury_mod(region_faction_name, 10000)
					LogSupply("Diplomat_Time_On_Allied_Region()","Transaction_cost_10000"..diplomat_faction_name)
					Diplomat_Time_On_Allied_Region[region_name] = 0
					Diplomat_Acquire_Region_Flag[region_name] = false
					Diplomat_Button_Flag[region_name] = false
				end
			end
			if Diplomat_Acquire_Client_Region_Flag[region_name] == true
				then 
				if region:building_superchain_exists("rom_SettlementMajor")
				or containsBuildingSuperchain(region, SpecialCapitalsList)	--(region:building_superchain_exists("dei_superchain_city_ROME") or region:building_superchain_exists("dei_superchain_city_PELLA") or region:building_superchain_exists("dei_superchain_city_CARTHAGE") or region:building_superchain_exists("dei_superchain_city_SYRACUSE") or region:building_superchain_exists("dei_superchain_city_ATHENS") or region:building_superchain_exists("dei_superchain_city_ALEXANDRIA") or region:building_superchain_exists("dei_superchain_city_PERGAMON") or region:building_superchain_exists("dei_superchain_city_ANTIOCH") or region:building_superchain_exists("dei_superchain_city_MASSILIA") or region:building_superchain_exists("dei_superchain_city_BIBRACTE"))
					then scripting.game_interface:show_message_event("custom_event_854", x, y)
					LogSupply("Diplomat_Acquired_Region_Message()","Message_Region: "..region_name)
					scripting.game_interface:transfer_region_to_faction(region_name, diplomat_faction_name)
					GetPopulation().ConvertPopulationClasses(curr_faction, region_name)
--					scripting.game_interface:apply_effect_bundle("Region_Trade_Deal_5000", diplomat_faction_name, 1)
					scripting.game_interface:trigger_custom_dilemma(diplomat_faction_name, "trade_region_interface_5000", "payload { money -5000; }", "payload { money -5000; }" ,true)
					scripting.game_interface:treasury_mod(region_faction_name, 5000)
					LogSupply("Diplomat_Time_On_Allied_Region()","Transaction_cost_5000"..diplomat_faction_name)
					Diplomat_Time_On_Allied_Region[region_name] = 0
					Diplomat_Acquire_Client_Region_Flag[region_name] = false
					Diplomat_Button_Flag[region_name] = false
				else
					scripting.game_interface:show_message_event("custom_event_853", x, y)
					LogSupply("Diplomat_Acquired_Region_Message()","Message_Region: "..region_name)
					scripting.game_interface:transfer_region_to_faction(region_name, diplomat_faction_name)
					GetPopulation().ConvertPopulationClasses(curr_faction, region_name)
--					scripting.game_interface:apply_effect_bundle("Region_Trade_Deal_2500", diplomat_faction_name, 1)
					scripting.game_interface:trigger_custom_dilemma(diplomat_faction_name, "trade_region_interface_2500", "payload { money -2500; }", "payload { money -2500; }" ,true)
					scripting.game_interface:treasury_mod(region_faction_name, 2500)
					LogSupply("Diplomat_Time_On_Allied_Region()","Transaction_cost_2500"..diplomat_faction_name)
					Diplomat_Time_On_Allied_Region[region_name] = 0
					Diplomat_Acquire_Client_Region_Flag[region_name] = false
					Diplomat_Button_Flag[region_name] = false
				end
			end
			--reduce counter globally every turn (idle or not)
			turn_reducer = Diplomat_Time_On_Allied_Region[region_name]
			if turn_reducer >= 15
				then
				if Diplomat_Button_Flag[region_name] == true
					then 
					Diplomat_Time_On_Allied_Region[region_name] = math.floor(turn_reducer*0.8)
					local show_reducer = Diplomat_Time_On_Allied_Region[region_name]
					LogSupply("Diplomat_Acquired_Region_Message()","turn_reducer_Diplomat_Button_Flag_On: "..region_name.." after_turn_reduced: "..show_reducer)
					if Diplomat_Time_On_Allied_Region[region_name] < 15
						then
						Trade_Expiration_Flag[region_name] = true
						LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Trade_Expiration_Flag_True")
					end
				else
					Diplomat_Time_On_Allied_Region[region_name] = math.floor(turn_reducer*0.9)
					LogSupply("Diplomat_Acquired_Region_Message()","turn_reducer_No Diplomat_Button_Flag: "..region_name.." after_turn_reduced: "..turn_reducer)
					if Diplomat_Time_On_Allied_Region[region_name] <= 0
						then
						Trade_Expiration_Flag[region_name] = true
						LogSupply("Diplomat_Time_On_Allied_Region()","Region_from_to_return: "..region_name.." Trade_Expiration_Flag_True")
					end
				end
			end
			
			if Trade_Expiration_Flag[region_name] == true
				then scripting.game_interface:show_message_event("custom_event_852", x, y)
				LogSupply("Diplomat_Acquired_Region_Message()","Trade_Expiration_Flag: "..region_name)
				Diplomat_Time_On_Allied_Region[region_name] = 0
				Trade_Expiration_Flag[region_name] = false
				Diplomat_Button_Flag[region_name] = false	
				Diplomat_Acquire_Region_Flag[region_name] = false
			end
			--give message and show region that is available to acquire
			if Diplomat_Button_Flag[region_name] == true
				then 
				local show_reducer = Diplomat_Time_On_Allied_Region[region_name]
				LogSupply("Diplomat_Time_On_Allied_Region()","Region up to sale: "..region_name.." This is the counter it has left: "..show_reducer)
				if region:building_superchain_exists("rom_SettlementMajor")
				or containsBuildingSuperchain(region, SpecialCapitalsList)
					then scripting.game_interface:show_message_event("custom_event_856", x, y)
				else 
					scripting.game_interface:show_message_event("custom_event_855", x, y)
				end
			end
		end
	end
end

-- TradeGetFactionTreaties and the ally/client treaty-type lists are now declared as
-- locals at the top of this file, above their first use.

--***Sell funtion begin here..***

-- main_emperor_faction_names (script/_lib/regions/diplomat_region_turns.lua) is
-- misleadingly named: it actually holds ~700 faction keys covering rom_, emp_, inv_,
-- gaul_, pun_, pel_, gen_ and pro_ prefixes, so it spans every campaign. It is still
-- not exhaustive, and the original returned nil on a miss, which crashed the tooltip
-- string concatenation. Fall back to the raw faction key instead.
function Show_Faction_Name(ownerName)
	if ownerName == nil or ownerName == "none" then
		return ""
	end;
	if main_emperor_faction_names[ownerName]
		then
		return main_emperor_faction_names[ownerName]
	end;
	return tostring(ownerName)
end;

RegionToBeSelled = "none"
RegionToBeSelledRegion = "none"
RegionSellList = "none"
RegionSellListRegion = "none"
SellerFaction = "none"
SellerFactionPlain = "none"
Buyer_Faction = "none"
Buyer_Faction_Plain = "none"
Transaction_Made = false


-- Triggering the put settlement on selling list event
local function Select_Sell_Region_ButtonTick(context)

	if context.string == "BUTT_SBB1_Trad_Regi"
	then
		scripting.game_interface:add_time_trigger("TriggerSelectSettlementEvent", 0.2);
		return;
	end;
end;

--select region
local function Sell_SaveNewRegion(context)
	local region = context:garrison_residence():region()
	RegionToBeSelled = region:name()
	RegionToBeSelledRegion = region
	LogSupply("Sell_SaveNewRegion()","This_region_is_selected : "..RegionToBeSelled);	
end;

-- Put on selling list action time trigger
local function Select_Selled_Settlement_TimeTrigger(context)

	if (context.string == "TriggerSelectSettlementEvent")
	then
		Sell_Region_point_out()
	end;
end;

--Show button
local function Sell_Region_Info(context)

	local yo = "[[rgba:255:204:51:150]]"
	local yc = "[[/rgba:255:204:51:150]]"
	local go = "[[rgba:75:174:77:150]]"
	local gc = "[[/rgba:75:174:77:150]]"
	local ro = "[[rgba:143:37:38:150]]" 
	local rc = "[[/rgba:143:37:38:150]]"
	local bo = "[[rgba:23:82:255:150]]"
	local bc = "[[/rgba:23:82:255:150]]"

	if context.string == "BUTT_SBB1_Trad_Regi"
	then
		if RegionToBeSelled ~= "none"
			then
			local region = RegionToBeSelledRegion
			local region_name = region:name()
			local regionKey = scripting.game_interface:model():world():region_manager():region_by_key(RegionToBeSelled)
			local ownerKey = regionKey:owning_faction()
			local ownerName = ownerKey:name()
			local ownerNameAsText = Show_Faction_Name(ownerName)
			local BuyerFactionAsText = Show_Faction_Name(Buyer_Faction)
			local factionName = GetLocalFactionName()
			local RegionDisplay = RegionKeytoRegionLoc[RegionToBeSelled]
			LogSupply("Sell_Region_Info()","Local_Faction : "..factionName);
			LogSupply("Sell_Region_Info()","Display_region : "..RegionDisplay);
			LogSupply("Sell_Region_Info()","Owner_Name : "..ownerName);
			
			if ownerName ~= factionName
				then
				if Transaction_Made == true
					then
					UIComponent(context.component):SetTooltipText(ro.."A region selling transaction has already been made, no further transaction this turn..."..rc)
					return;
				else
					if RegionSellList ~= "none"
						then 
						local SellRegionDisplay = RegionKeytoRegionLoc[RegionSellList]
						local AlliedFactionKeys, EnemyFactionKeys, ClientFactionKeys = TradeGetFactionTreaties(SellerFactionPlain:treaty_details())
			
						if contains(ownerName, EnemyFactionKeys)
							then
							UIComponent(context.component):SetTooltipText(ro.."You cannot sell settlement: "..rc..yo..SellRegionDisplay..yc..ro.." to enemy faction..."..rc)
						else
							if RegionSellListRegion:building_superchain_exists("rom_SettlementMajor")
							or containsBuildingSuperchain(RegionSellListRegion, SpecialCapitalsList)
								then
								if contains(ownerName, ClientFactionKeys)
									then 
									if ownerKey:treasury() >= 24000
										then
										UIComponent(context.component):SetTooltipText("Sell settlement: "..yo..SellRegionDisplay..yc.."\n\n At the price of: "..yo.."24000"..yc.."\n\n To this faction: "..go..ownerNameAsText..gc)
									else
										UIComponent(context.component):SetTooltipText("You cannot sell settlement: "..yo..SellRegionDisplay..yc.."\n\n To this faction: "..go..ownerNameAsText..gc..ro.." \nSince it lacks the money to pay for the transaction"..rc)
									end;
								elseif contains(ownerName, AlliedFactionKeys)
									then
									if ownerKey:treasury() >= 20000
										then
										UIComponent(context.component):SetTooltipText("Sell settlement: "..yo..SellRegionDisplay..yc.."\n\n At the price of: "..yo.."20000"..yc.."\n\n To this faction: "..go..ownerNameAsText..gc)
									else
										UIComponent(context.component):SetTooltipText("You cannot sell settlement: "..yo..SellRegionDisplay..yc.."\n\n To this faction: "..go..ownerNameAsText..gc..ro.." \nSince it lacks the money to pay for the transaction"..rc)
									end;
								else
									if ownerKey:treasury() >= 16000
										then
										UIComponent(context.component):SetTooltipText("Sell settlement: "..yo..SellRegionDisplay..yc.."\n\n At the price of: "..yo.."16000"..yc.."\n\n To this faction: "..go..ownerNameAsText..gc)
									else
										UIComponent(context.component):SetTooltipText("You cannot sell settlement: "..yo..SellRegionDisplay..yc.."\n\n To this faction: "..go..ownerNameAsText..gc..ro.." \nSince it lacks the money to pay for the transaction"..rc)
									end;
								end;
							else	
								if contains(ownerName, ClientFactionKeys)
									then
									if ownerKey:treasury() >= 12000
										then
										UIComponent(context.component):SetTooltipText("Sell settlement: "..yo..SellRegionDisplay..yc.."\n\n At the price of: "..yo.."12000"..yc.."\n\n To this faction: "..go..ownerNameAsText..gc)
									else
										UIComponent(context.component):SetTooltipText("You cannot sell settlement: "..yo..SellRegionDisplay..yc.."\n\n To this faction: "..go..ownerNameAsText..gc..ro.." \nSince it lacks the money to pay for the transaction"..rc)
									end;
								elseif contains(ownerName, AlliedFactionKeys)
									then
									if ownerKey:treasury() >= 10000
										then
										UIComponent(context.component):SetTooltipText("Sell settlement: "..yo..SellRegionDisplay..yc.."\n\n At the price of: "..yo.."10000"..yc.."\n\n To this faction: "..go..ownerNameAsText..gc)
									else
										UIComponent(context.component):SetTooltipText("You cannot sell settlement: "..yo..SellRegionDisplay..yc.."\n\n To this faction: "..go..ownerNameAsText..gc..ro.." \nSince it lacks the money to pay for the transaction"..rc)
									end;
								else
									if ownerKey:treasury() >= 8000
										then
										UIComponent(context.component):SetTooltipText("Sell settlement: "..yo..SellRegionDisplay..yc.."\n\n At the price of: "..yo.."8000"..yc.."\n\n To this faction: "..go..ownerNameAsText..gc)
									else
										UIComponent(context.component):SetTooltipText("You cannot sell settlement: "..yo..SellRegionDisplay..yc.."\n\n To this faction: "..go..ownerNameAsText..gc..ro.." \nSince it lacks the money to pay for the transaction"..rc)
									end;
								end;
							end;
						end;
					else
						UIComponent(context.component):SetTooltipText(ro.. "This settlement belongs to another faction, cannot be selled.." ..rc)
					end;
				end;
			end;
			
			if ownerName == factionName
				then
				if Transaction_Made == true
					then
					local SellRegionDisplay = RegionKeytoRegionLoc[RegionSellList]
					local BuyerFactionAsText = Show_Faction_Name(Buyer_Faction)
					UIComponent(context.component):SetTooltipText("Region: "..go..SellRegionDisplay..gc.."\nis to be selled to Faction: "..yo..BuyerFactionAsText..yc..ro.."\n No more transaction this turn"..rc)
					return
				else
					if RegionToBeSelled ~= RegionSellList
						then
						if isLocalFaction(ownerName) 
						and ownerKey:is_human() 
						and ownerName == factionName
							then 
							if RegionToBeSelled ~= ownerKey:home_region():name()
								then
								if region:building_superchain_exists("rom_SettlementMajor")
								or containsBuildingSuperchain(region, SpecialCapitalsList)
									then 
									UIComponent(context.component):SetTooltipText(yo.."Sell Settlement||"..yc.."Selling price if selling to client faction: "..go.."24000"..gc.." \n Selling price if selling to allied faction: "..go.."20000"..gc.." \nSelling price if selling to neutral faction: "..go.."16000"..gc.." \n\nThis settlement: " ..yo..RegionDisplay..yc.."\nis added to sell list if button is pressed")
								else
									UIComponent(context.component):SetTooltipText(yo.."Sell Settlement||"..yc.."Selling price if selling to client faction: "..go.."12000"..gc.." \n Selling price if selling to allied faction: "..go.."10000"..gc.." \nSelling price if selling to neutral faction: "..go.."8000"..gc.." \n\nThis settlement: " ..yo..RegionDisplay..yc.."\nis added to sell list if button is pressed")
								end;
							else
								UIComponent(context.component):SetTooltipText(ro.. "This settlement is your capital, it cannot be selled.." ..rc)
							end;
						end;
					elseif RegionToBeSelled == RegionSellList
						then
						UIComponent(context.component):SetTooltipText(go.. "This settlement is already picked to be selled||" ..gc.."To sell, just find a settlement belonging to a faction you want to sell and press this same button")
					end;
				end;
			end;
		end;
	end;
end;

function Sell_Region_point_out()
	local region = RegionToBeSelledRegion
	local x = region:settlement():display_position_x()
    local y = region:settlement():display_position_y()
	local turn_num = GetTurnNum()
	

	if RegionToBeSelled ~= "none"
		then 
		local regionKey = scripting.game_interface:model():world():region_manager():region_by_key(RegionToBeSelled)
		local region_name = regionKey:name()
		local ownerKey =  regionKey:owning_faction()
		local ownerName = ownerKey:name()
		local factionName = GetLocalFactionName()
		
		if Transaction_Made == true
			then 
			return
		else
			if isLocalFaction(ownerName) 
			and ownerKey:is_human() 
			and ownerName == factionName
			and RegionToBeSelled ~= ownerKey:home_region():name()
				then
				scripting.game_interface:show_message_event("custom_event_708", x, y)
				RegionSellList = RegionToBeSelled
				RegionSellListRegion = region
				SellerFaction = ownerName
				SellerFactionPlain = ownerKey
				Region_Sell_Flag[1] = RegionToBeSelled 
				LogSupply("Sell_Region_point_out()","Region_added_to_sell_list: "..RegionSellList);	
			end;
		
			--point out buyer..
			if RegionSellList ~= "none"
			and ownerName ~= factionName
				then
				local x_x = RegionSellListRegion:settlement():display_position_x()
				local y_y = RegionSellListRegion:settlement():display_position_y()
				local AlliedFactionKeys, EnemyFactionKeys, ClientFactionKeys = TradeGetFactionTreaties(SellerFactionPlain:treaty_details())
				if RegionSellListRegion:building_superchain_exists("rom_SettlementMajor")
				or containsBuildingSuperchain(RegionSellListRegion, SpecialCapitalsList)
					then
					if contains(ownerName, ClientFactionKeys)
					and ownerKey:treasury() >= 24000
						then
						Region_Sell_Flag[2] = ownerName
						Region_Sell_Flag[3] = factionName
						Region_Sell_Flag[4] = true
						Transaction_Made = true
						Buyer_Faction = ownerName
						scripting.game_interface:show_message_event("custom_event_707", x_x, y_y)
						LogSupply("Sell_Region_point_out()","Selled_Region_to_Faction: "..ownerName);
					elseif contains(ownerName, AlliedFactionKeys)
					and ownerKey:treasury() >= 20000
						then
						Region_Sell_Flag[2] = ownerName
						Region_Sell_Flag[3] = factionName
						Region_Sell_Flag[4] = true
						Transaction_Made = true
						Buyer_Faction = ownerName
						scripting.game_interface:show_message_event("custom_event_707", x_x, y_y)
						LogSupply("Sell_Region_point_out()","Selled_Region_to_Faction: "..ownerName);
					elseif not contains(ownerName, EnemyFactionKeys)
					and ownerKey:treasury() >= 16000
						then
						Region_Sell_Flag[2] = ownerName
						Region_Sell_Flag[3] = factionName
						Region_Sell_Flag[4] = true
						Transaction_Made = true
						Buyer_Faction = ownerName
						scripting.game_interface:show_message_event("custom_event_707", x_x, y_y)
						LogSupply("Sell_Region_point_out()","Selled_Region_to_Faction: "..ownerName);
					end;
				else
					if contains(ownerName, ClientFactionKeys)
					and ownerKey:treasury() >= 12000
						then
						Region_Sell_Flag[2] = ownerName
						Region_Sell_Flag[3] = factionName
						Region_Sell_Flag[4] = true
						Transaction_Made = true
						Buyer_Faction = ownerName
						scripting.game_interface:show_message_event("custom_event_707", x_x, y_y)
						LogSupply("Sell_Region_point_out()","Selled_Region_to_Faction: "..ownerName);
					elseif contains(ownerName, AlliedFactionKeys)
					and ownerKey:treasury() >= 10000
						then
						Region_Sell_Flag[2] = ownerName
						Region_Sell_Flag[3] = factionName
						Region_Sell_Flag[4] = true
						Transaction_Made = true
						Buyer_Faction = ownerName
						scripting.game_interface:show_message_event("custom_event_707", x_x, y_y)
						LogSupply("Sell_Region_point_out()","Selled_Region_to_Faction: "..ownerName);
					elseif not contains(ownerName, EnemyFactionKeys)
					and ownerKey:treasury() >= 8000
						then
						Region_Sell_Flag[2] = ownerName
						Region_Sell_Flag[3] = factionName
						Region_Sell_Flag[4] = true
						Transaction_Made = true
						Buyer_Faction = ownerName
						scripting.game_interface:show_message_event("custom_event_707", x_x, y_y)
						LogSupply("Sell_Region_point_out()","Selled_Region_to_Faction: "..ownerName);
					end;
				end;
			end;
		end;
	end;
end;

---- Region selled message and transactions ----
local function Show_Message_Region_Selled(context)
	local curr_faction = context:faction()
    local faction_name = curr_faction:name()
    if curr_faction:is_human() == true then
        local region_list = scripting.game_interface:model():world():region_manager():region_list()
        for j = 0, region_list:num_items() - 1 do
            local region = region_list:item_at(j)
            local region_name = region:name()
            local turn_reducer = 0
            local x = region:settlement():display_position_x()
            local y = region:settlement():display_position_y()
            local region_faction_name = region:garrison_residence():faction():name()

            if Region_Sell_Flag[1] == region_name 
				then 
				SellerFaction = Region_Sell_Flag[3]
				if region_faction_name == SellerFaction
					then 
					local buyer_faction_name = Region_Sell_Flag[2]
					local selled_region = region
					local selled_region_name = region_name
					local AlliedFactionKeys, EnemyFactionKeys, ClientFactionKeys = TradeGetFactionTreaties(curr_faction:treaty_details())
					
					--Bug fix, if for some reason, the buyer becomes enemy, clear all flags and return to starting position
					if contains(buyer_faction_name, EnemyFactionKeys)
						then 
						Region_Sell_Flag[1] = "none"
						Region_Sell_Flag[2] = "none"
						Region_Sell_Flag[3] = "none"
						Region_Sell_Flag[4] = false
						Transaction_Made = false
						RegionToBeSelled = "none"
						RegionToBeSelledRegion = "none"
						RegionSellList = "none"
						RegionSellListRegion = "none"
						SellerFaction = "none"
						SellerFactionPlain = "none"
						Buyer_Faction = "none"
						Buyer_Faction_Plain = "none"
						LogSupply("buyer becomes enemy, clear all flags and return to starting position","Buyer_name: "..buyer_faction_name);
						return						
					end
					
					if RegionSellListRegion:building_superchain_exists("rom_SettlementMajor")
					or containsBuildingSuperchain(RegionSellListRegion, SpecialCapitalsList)
						then
						if contains(buyer_faction_name, ClientFactionKeys)
							then
							scripting.game_interface:transfer_region_to_faction(selled_region_name, buyer_faction_name);
							scripting.game_interface:apply_effect_bundle("Region_Sold_24000", buyer_faction_name, 1);
							LogSupply("Show_Message_Region_Selled()","buyer_name: "..buyer_faction_name);	
							scripting.game_interface:treasury_mod(faction_name, 24000)
							LogSupply("Show_Message_Region_Selled()","Seller_name: "..faction_name);
							GetPopulation().ConvertPopulationClasses(Buyer_Faction_Plain, selled_region_name)				
							scripting.game_interface:show_message_event("custom_event_701", x, y)
							--clear variables
							Region_Sell_Flag[1] = "none"
							Region_Sell_Flag[2] = "none"
							Region_Sell_Flag[3] = "none"
							Region_Sell_Flag[4] = false
							Transaction_Made = false
							RegionToBeSelled = "none"
							RegionToBeSelledRegion = "none"
							RegionSellList = "none"
							RegionSellListRegion = "none"
							SellerFaction = "none"
							SellerFactionPlain = "none"
							Buyer_Faction = "none"
							Buyer_Faction_Plain = "none"
						elseif contains(buyer_faction_name, AlliedFactionKeys)
							then
							scripting.game_interface:transfer_region_to_faction(selled_region_name, buyer_faction_name)
							scripting.game_interface:apply_effect_bundle("Region_Sold_20000", buyer_faction_name, 1);
							LogSupply("Show_Message_Region_Selled()","buyer_name: "..buyer_faction_name);	
							scripting.game_interface:treasury_mod(faction_name, 20000)
							LogSupply("Show_Message_Region_Selled()","Seller_name: "..faction_name);
							GetPopulation().ConvertPopulationClasses(Buyer_Faction_Plain, selled_region_name)
							scripting.game_interface:show_message_event("custom_event_702", x, y)
							--clear variables
							Region_Sell_Flag[1] = "none"
							Region_Sell_Flag[2] = "none"
							Region_Sell_Flag[3] = "none"
							Region_Sell_Flag[4] = false
							Transaction_Made = false
							RegionToBeSelled = "none"
							RegionToBeSelledRegion = "none"
							RegionSellList = "none"
							RegionSellListRegion = "none"
							SellerFaction = "none"
							SellerFactionPlain = "none"
							Buyer_Faction = "none"
							Buyer_Faction_Plain = "none"
						elseif not contains(buyer_faction_name, EnemyFactionKeys)
							then
							scripting.game_interface:transfer_region_to_faction(selled_region_name, buyer_faction_name)
							scripting.game_interface:apply_effect_bundle("Region_Sold_16000", buyer_faction_name, 1);
							LogSupply("Show_Message_Region_Selled()","buyer_name: "..buyer_faction_name);	
							scripting.game_interface:treasury_mod(faction_name, 16000)
							LogSupply("Show_Message_Region_Selled()","Seller_name: "..faction_name);
							GetPopulation().ConvertPopulationClasses(Buyer_Faction_Plain, selled_region_name)
							scripting.game_interface:show_message_event("custom_event_703", x, y)
							--clear variables
							Region_Sell_Flag[1] = "none"
							Region_Sell_Flag[2] = "none"
							Region_Sell_Flag[3] = "none"
							Region_Sell_Flag[4] = false
							Transaction_Made = false
							RegionToBeSelled = "none"
							RegionToBeSelledRegion = "none"
							RegionSellList = "none"
							RegionSellListRegion = "none"
							SellerFaction = "none"
							SellerFactionPlain = "none"
							Buyer_Faction = "none"
							Buyer_Faction_Plain = "none"
						end;
					else
						if contains(buyer_faction_name, ClientFactionKeys)
							then
							scripting.game_interface:transfer_region_to_faction(selled_region_name, buyer_faction_name)
							scripting.game_interface:apply_effect_bundle("Region_Sold_12000", buyer_faction_name, 1);
							LogSupply("Show_Message_Region_Selled()","buyer_name: "..buyer_faction_name);	
							scripting.game_interface:treasury_mod(faction_name, 12000)
							LogSupply("Show_Message_Region_Selled()","Seller_name: "..faction_name);
							GetPopulation().ConvertPopulationClasses(Buyer_Faction_Plain, selled_region_name)
							scripting.game_interface:show_message_event("custom_event_704", x, y)
							--clear variables
							Region_Sell_Flag[1] = "none"
							Region_Sell_Flag[2] = "none"
							Region_Sell_Flag[3] = "none"
							Region_Sell_Flag[4] = false
							Transaction_Made = false
							RegionToBeSelled = "none"
							RegionToBeSelledRegion = "none"
							RegionSellList = "none"
							RegionSellListRegion = "none"
							SellerFaction = "none"
							SellerFactionPlain = "none"
							Buyer_Faction = "none"
							Buyer_Faction_Plain = "none"
						elseif contains(buyer_faction_name, AlliedFactionKeys)
							then
							scripting.game_interface:transfer_region_to_faction(selled_region_name, buyer_faction_name)
							scripting.game_interface:apply_effect_bundle("Region_Sold_10000", buyer_faction_name, 1);
							LogSupply("Show_Message_Region_Selled()","buyer_name: "..buyer_faction_name);	
							scripting.game_interface:treasury_mod(faction_name, 10000)
							LogSupply("Show_Message_Region_Selled()","Seller_name: "..faction_name);
							GetPopulation().ConvertPopulationClasses(Buyer_Faction_Plain, selled_region_name)
							scripting.game_interface:show_message_event("custom_event_705", x, y)
							--clear variables
							Region_Sell_Flag[1] = "none"
							Region_Sell_Flag[2] = "none"
							Region_Sell_Flag[3] = "none"
							Region_Sell_Flag[4] = false
							Transaction_Made = false
							RegionToBeSelled = "none"
							RegionToBeSelledRegion = "none"
							RegionSellList = "none"
							RegionSellListRegion = "none"
							SellerFaction = "none"
							SellerFactionPlain = "none"
							Buyer_Faction = "none"
							Buyer_Faction_Plain = "none"
						elseif not contains(buyer_faction_name, EnemyFactionKeys)
							then
							scripting.game_interface:transfer_region_to_faction(selled_region_name, buyer_faction_name)
							scripting.game_interface:apply_effect_bundle("Region_Sold_8000", buyer_faction_name, 1);
							LogSupply("Show_Message_Region_Selled()","buyer_name: "..buyer_faction_name);	
							scripting.game_interface:treasury_mod(faction_name, 8000)
							LogSupply("Show_Message_Region_Selled()","Seller_name: "..faction_name);
							GetPopulation().ConvertPopulationClasses(Buyer_Faction_Plain, selled_region_name)
							scripting.game_interface:show_message_event("custom_event_706", x, y)
							--clear variables
							Region_Sell_Flag[1] = "none"
							Region_Sell_Flag[2] = "none"
							Region_Sell_Flag[3] = "none"
							Region_Sell_Flag[4] = false
							Transaction_Made = false
							RegionToBeSelled = "none"
							RegionToBeSelledRegion = "none"
							RegionSellList = "none"
							RegionSellListRegion = "none"
							SellerFaction = "none"
							SellerFactionPlain = "none"
							Buyer_Faction = "none"
							Buyer_Faction_Plain = "none"
						end;
					end;
				else
					--clear variables, this settlement has changed its owner before transaction...
					Region_Sell_Flag[1] = "none"
					Region_Sell_Flag[2] = "none"
					Region_Sell_Flag[3] = "none"
					Region_Sell_Flag[4] = false
					Transaction_Made = false
					RegionToBeSelled = "none"
					RegionToBeSelledRegion = "none"
					RegionSellList = "none"
					RegionSellListRegion = "none"
					SellerFaction = "none"
					SellerFactionPlain = "none"
					Buyer_Faction = "none"
					Buyer_Faction_Plain = "none"
				end;
			end;
		end;
	end;
end;

--figure out seller faction plain
local function Load_Seller_Faction_Plain(context)
	if context:faction():is_human()
		then
		LogSupply("Load_Seller_Faction_Plain()","Start Function..");
		if SellerFaction ~= "none"
		and SellerFactionPlain == "none"
			then 
			local faction_list = scripting.game_interface:model():world():faction_list()  
			for i = 0, faction_list:num_items() - 1 do
			local current_faction = faction_list:item_at(i)
			local current_faction_name = current_faction:name()
				if current_faction_name == SellerFaction
					then SellerFactionPlain = current_faction
					LogSupply("Load_Seller_Faction_Plain()","Seller_faction_plain_found : "..current_faction_name);
				end
			end
		end	
		--figure out "RegionSellListRegion" from "RegionSellList"
		if RegionSellList ~= "none"
		and SellerFactionPlain ~= "none"
		and RegionSellListRegion == "none"
			then 
			for i = 0, SellerFactionPlain:region_list():num_items() -1 do
			local region = SellerFactionPlain:region_list():item_at(i)
			local region_name = region:name()
				if RegionSellList == region_name
					then RegionSellListRegion = region
					LogSupply("Load_Seller_Faction_Plain()","selled_region_found : "..region_name);
				end
			end
		end
		--figure Buyer faction "Buyer_Faction_Plain" from "RegionSellList"
		if Buyer_Faction ~= "none"
		and Buyer_Faction_Plain == "none"
			then
			local faction_list = scripting.game_interface:model():world():faction_list()  
			for i = 0, faction_list:num_items() - 1 do
			local current_faction = faction_list:item_at(i)
			local current_faction_name = current_faction:name()
				if current_faction_name == Buyer_Faction
					then Buyer_Faction_Plain = current_faction
					LogSupply("Load_Seller_Faction_Plain()","Buyer_faction_plain_found : "..current_faction_name);
				end
			end
		end
	end	
end

--<<<Save/Load Values>>>
local function Save_Values(context)
	for i,value in pairs(Diplomat_Time_On_Allied_Region) do
		scripting.game_interface:save_named_value("Diplomat_Time_On_Allied_Region"..i, value, context)
	end
	for i,value in pairs(Diplomat_Button_Flag) do
		scripting.game_interface:save_named_value("Diplomat_Button_Flag"..i, value, context)
	end
	-- These three are set on CharacterTurnEnd and consumed on the next FactionTurnStart.
	-- The turn-start autosave lands between the two, so without persisting them a
	-- save/reload at the wrong moment silently loses an in-flight acquisition.
	for i,value in pairs(Diplomat_Acquire_Region_Flag) do
		scripting.game_interface:save_named_value("Diplomat_Acquire_Region_Flag"..i, value, context)
	end
	for i,value in pairs(Diplomat_Acquire_Client_Region_Flag) do
		scripting.game_interface:save_named_value("Diplomat_Acquire_Client_Region_Flag"..i, value, context)
	end
	for i,value in pairs(Trade_Expiration_Flag) do
		scripting.game_interface:save_named_value("Trade_Expiration_Flag"..i, value, context)
	end
	
	local value_1 = ""
	local value_2 = ""
	local value_3 = ""
	local value_4 = false
	value_1 = Region_Sell_Flag[1]
	value_2 = Region_Sell_Flag[2]
	value_3 = Region_Sell_Flag[3]
	value_4 = Region_Sell_Flag[4]
	scripting.game_interface:save_named_value("Region_Sell_Flag_region_", value_1, context)
	scripting.game_interface:save_named_value("Region_Sell_Flag_buyer_", value_2, context)
	scripting.game_interface:save_named_value("Region_Sell_Flag_seller_", value_3, context)
	scripting.game_interface:save_named_value("Region_Sell_Flag_trans_", value_4, context)
	--log
	LogSupply("Save_Sell_Region_Values","Region_Sell_Flag_region: "..value_1);
	LogSupply("Save_Sell_Region_Values","Region_Sell_Flag_buyer: "..value_2);
	LogSupply("Save_Sell_Region_Values","Region_Sell_Flag_seller: "..value_3);
	LogSupply("Save_Sell_Region_Values","Region_Sell_Flag_trans: "..tostring(value_4))
end

local function Load_Values(context)
  for i,value in pairs(Diplomat_Time_On_Allied_Region) do
    Diplomat_Time_On_Allied_Region[i] = scripting.game_interface:load_named_value("Diplomat_Time_On_Allied_Region"..i, value, context)
  end
  for i,value in pairs(Diplomat_Button_Flag) do
    Diplomat_Button_Flag[i] = scripting.game_interface:load_named_value("Diplomat_Button_Flag"..i, value, context) 
  end
  for i,value in pairs(Diplomat_Acquire_Region_Flag) do
    Diplomat_Acquire_Region_Flag[i] = scripting.game_interface:load_named_value("Diplomat_Acquire_Region_Flag"..i, value, context)
  end
  for i,value in pairs(Diplomat_Acquire_Client_Region_Flag) do
    Diplomat_Acquire_Client_Region_Flag[i] = scripting.game_interface:load_named_value("Diplomat_Acquire_Client_Region_Flag"..i, value, context)
  end
  for i,value in pairs(Trade_Expiration_Flag) do
    Trade_Expiration_Flag[i] = scripting.game_interface:load_named_value("Trade_Expiration_Flag"..i, value, context)
  end
  
	local value_1 = ""
	local value_2 = ""
	local value_3 = ""
	local value_4 = false
	value_1 = scripting.game_interface:load_named_value("Region_Sell_Flag_region_", "none", context)
    value_2 = scripting.game_interface:load_named_value("Region_Sell_Flag_buyer_", "none", context)
	value_3 = scripting.game_interface:load_named_value("Region_Sell_Flag_seller_", "none", context)
	value_4 = scripting.game_interface:load_named_value("Region_Sell_Flag_trans_", false, context)
	--put values to table
	Region_Sell_Flag[1] = value_1
	Region_Sell_Flag[2] = value_2
	Region_Sell_Flag[3] = value_3
	Region_Sell_Flag[4] = value_4
	--log
	LogSupply("Load_Sell_Region_Values","Region_Sell_Flag_region: "..value_1);
	LogSupply("Load_Sell_Region_Values","Region_Sell_Flag_buyer: "..value_2);
	LogSupply("Load_Sell_Region_Values","Region_Sell_Flag_seller: "..value_3);
	LogSupply("Load_Sell_Region_Values","Region_Sell_Flag_trans: "..tostring(value_4))
	
	--Put global Variables in place on load
	RegionSellList = Region_Sell_Flag[1]
	Buyer_Faction = Region_Sell_Flag[2]
	SellerFaction = Region_Sell_Flag[3]
	Transaction_Made = Region_Sell_Flag[4]
end

--***********************
-- CALLBACKS ------------
--***********************
scripting.AddEventCallBack("LoadingGame", Load_Values)
scripting.AddEventCallBack("SavingGame", Save_Values)
scripting.AddEventCallBack("FactionTurnStart", Load_Seller_Faction_Plain)
scripting.AddEventCallBack("CharacterTurnEnd", DiplomatOnAlliedLand)--/Diplomat On Allied Land counter
scripting.AddEventCallBack("CharacterSelected", Diplomat_AR_Advisor)--Acquire Region advisor
scripting.AddEventCallBack("FactionTurnStart", Show_Message_Region_Acquired_Via_Diplomacy)
--Random seeds
scripting.AddEventCallBack("FactionTurnStart", Diplomat_Acquires_Region_random_seed_turn_start)
scripting.AddEventCallBack("FactionTurnEnd", Diplomat_Acquires_Region_random_seed_turn_end)
--Sell settlement
scripting.AddEventCallBack("ComponentMouseOn", Sell_Region_Info);
scripting.AddEventCallBack("ComponentLClickUp", Select_Sell_Region_ButtonTick);
scripting.AddEventCallBack("SettlementSelected", Sell_SaveNewRegion);
scripting.AddEventCallBack("TimeTrigger", Select_Selled_Settlement_TimeTrigger);
scripting.AddEventCallBack("FactionTurnStart", Show_Message_Region_Selled)