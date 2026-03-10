-- ***** SUPPLY FACTION IS BAR ***** --

function SupplyFactionisBAR(factionCulture)
	local bool = false;
	if factionCulture == "rom_Barbarian"
	then
		bool = true;
	end;
	return bool;
end;

-- ***** SUPPLY FACTION IS NOMADIC ***** --

function SupplyFactionisNOMADIC(factionName, factionSubculture)
	local bool = false;
	if factionSubculture == "sc_rom_barb_east"
	or contains(factionName, global_supply_variables.nomadic_factions_table)
	then
		bool = true;
	end;
	return bool;
end;


-- ***** SUPPLY FACTION IS CIV ***** --

function SupplyFactionisCIV(factionCulture)
	local bool = false;
	if factionCulture ~= "rom_Barbarian"
	then
		bool = true;
	end;
	return bool;
end;


-- ***** SUPPLY CHAR IS TRANSPORT FLEET ***** --

function SupplyCharisTransportFleet(curr_char)
	local bool = false;

	if char_is_general_with_navy(curr_char) == false
	and curr_char:has_military_force()
	and (char_is_general_with_navy(curr_char)) == false
	and curr_char:has_region() == false
	and curr_char:military_force():unit_list():num_items() >= 2
	and curr_char:character_type("general")
	and curr_char:turns_at_sea() <= 1
	then
		bool = true;
	end;
	return bool;
end;


-- ***** SUPPLY CHAR IS ADMIRAL ***** --
function SupplyCharisAdmiral(curr_char)
	local bool = false;
	if curr_char:has_military_force()
	and char_is_general_with_navy(curr_char)
	then
		bool = true;
	end;
	return bool;
end;


-- ***** SUPPLY CHARACTER IS GENERAL ***** --
function SupplyCharacterisGeneral(character)
	local bool = false;
	LogSupply("SupplyCharacterisGeneral(character)", "Start SupplyCharacterisGeneral")

	if character:has_military_force() == false then
		LogSupply("SupplyCharacterisGeneral(character)", "Character is Polititian/Agent:")
		return bool;
	end;

	if character:has_region()
		and character:military_force():is_army()
		and character:character_type("general")
		and character:military_force():unit_list():num_items() >= 2 then
			bool = true;
		LogSupply("SupplyCharacterisGeneral(character)", "Character is General")
	end;
	return bool;
end;

-- ***** SUPPLY ARMY SIZE ***** --
function SupplyArmySize(military_force)
	local supply_points = military_force:unit_list():num_items()
	local force = military_force

	for i = 0, force:unit_list():num_items() - 1 do
		local unit = force:unit_list():item_at(i)

		if Unit_Is_in_Unit_List(unit:unit_class(), elephant_class_list) then
			supply_points = supply_points + 4
		end

		if Unit_Is_in_Unit_List(unit:unit_class(), cavalry_class_list) then
			supply_points = supply_points + 1;
		end;
	end;
	return supply_points;
end;

-- ***** IS DESERT FACTION ***** --
function Is_Desert_Faction(faction_name)

	if contains (faction_name, global_supply_variables.desert_factions_list_table) then
		return true;
	else
		return false;
	end;
end;

-- ***** IS WINTER IN ALPS ***** --
function Is_Winter_In_Alps(region)
	LogSupply("Is_Winter_In_Alps(region)","Winter in Apline region Attrition check: "..region);
	local bool = false;
	if current_Season() == 3
	and contains (region, global_supply_variables.alpine_regions_table)
	then
		bool = true;
	end;
	LogSupply("Is_Winter_In_Alps(region)","Winter in Apline region Attrition check: "..tostring(bool));
	return bool;
end;


-- ***** DESERT ATTRITION ***** --
function Desert_Attrition(faction, region)

 	LogSupply("Desert_Attrition(faction, region)","Desert region Attrition check in region: "..region);
 	local bool = false;
	if Is_Desert_Faction(faction) == false
	and current_Season() == 1
	and contains (region, global_supply_variables.desert_regions_table)
	then
		bool = true;
	end;
	LogSupply("Desert_Attrition(faction, region)","Desert region Attrition check:"..tostring(bool));
	return bool;
end;

-- ***** SUPPLY CHAR GARBAGE COLLECTOR ***** --
function SupplyCharGarbageCollector(char, garbageculture)
	local character = char;
	local army = char:cqi();
	local garbagelist = supply_bundle_list
	if garbageculture == "civ" then
		garbagelist =  civ_effect_bundle_list
	elseif garbageculture == "nom" then
		garbagelist = nom_effect_bundle_list
	elseif garbageculture == "bar" then
		garbagelist = bar_effect_bundle_list
	end
	if character:has_military_force()
		-- and character:military_force():unit_list():num_items() == 1
	then RemoveBundle(army, garbagelist);
	end;
end;


-- ***** SUPPLY UPDATE ARMY STATE ***** --
function SupplyUpdateArmyState(cqi, EffectBundle, RegionName, SupplyConsumption,isSupplyConsumptionOn, owner)
	scripting.game_interface:apply_effect_bundle_to_characters_force(EffectBundle, cqi,-1);
	RemoveSuppliesBasic(RegionName, SupplyConsumption, isSupplyConsumptionOn, owner);
	LogSupply("SupplyUpdateArmyState(cqi, EffectBundle, RegionName, SupplyConsumption,isSupplyConsumptionOn)", "***SupplyUpdateArmyState***")
end;

-- ***** REMOVE SUPPLIES BASIC ***** --
function RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn, owner)
	LogSupply("RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn)","Start RemoveSuppliesBasic");

	if not SupplyConsumptionOn then
		LogSupply("RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn)", "UI Function - no supplies consumed");
		return;
	end;

	local regional_supplies = Supply_Region_Table[region]
	LogSupply("RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn)","regional supplies: "..regional_supplies.. " in region: "..region);
	-- make sure only region owner or allies can access storage
	if owner == true then
		local supply_stored = Supply_Storage_Table[region];
		LogSupply("RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn)","supplies stored: "..supply_stored.. " in region: "..region);

		if supply_stored >= supply_consumption then
			Supply_Storage_Table[region] = supply_stored - supply_consumption
			LogSupply("RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn)","Remove: ".. supply_consumption .. " from: " .. region .. " Current Stored Supplies: " .. supply_stored.. " New Supplies: "..Supply_Storage_Table[region]);
		elseif supply_stored < supply_consumption then
			Supply_Region_Table[region] = regional_supplies - supply_consumption
			LogSupply("RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn)","Remove: ".. supply_consumption .. " from: " .. region .. " Current Supplies: " .. regional_supplies.. " New Supplies: "..Supply_Region_Table[region]);
		end;
	elseif owner == false then Supply_Region_Table[region] = regional_supplies - supply_consumption
		LogSupply("RemoveSuppliesBasic(region, supply_consumption, SupplyConsumptionOn)","Remove: ".. supply_consumption .. " from: " .. region .. " Current Supplies: " .. regional_supplies.. " New Supplies: "..Supply_Region_Table[region]);
	end;
end;

-- ***** SUPPLY GLOBAL FOOD SUPPLY COSTS ***** --
function SupplyGlobalFoodSupplyCosts(GlobalSupplies, faction)

	if faction:is_human()
	then
		local player_faction = faction:name()
		LogSupply("SupplyGlobalFoodSupplyCosts(GlobalSupplies, faction)","Start PlayerGlobalFoodSupplyLine : ".. player_faction);
		RemoveFactionBundle(player_faction, logistic_costs_effect_bundles)
		LogSupply("SupplyGlobalFoodSupplyCosts(GlobalSupplies, faction)","Removed logistic effect bundles for: "..player_faction);

		if GlobalSupplies > 20
		then
			GlobalSupplies = 20;
		end;
		scripting.game_interface:apply_effect_bundle("Faction_Army_Supply_"..GlobalSupplies, player_faction, 99);
	end;
end;


-- ***** SUPPLY FROM DEPOT ***** --
-- we already know that the region has enough supplies so no need to check this

function SupplyFromDepot(cqi, local_region, depot_region, supply_shif, supply_consumption, SupplyConsumptionOn, owner)

	LogSupply("SupplyFromDepot(cqi, local_region, depot_region, supply_shif, supply_consumption, SupplyConsumptionOn)", "Start SupplyFromDepot in region for: "..local_region.." Command Queue Index: "..cqi)
	--local strategic_depot_storage = regions_storage_table[depot_region]
	--local strategic_depot_supply = regions_table[depot_region]
	--local ui_supply_shift = SupplyImportsExportsTable_table[depot_region]
	--local regional_supplies = Supply_Region_Table[local_region]
	-- From Depot
	RemoveSuppliesBasic(depot_region, supply_shif, SupplyConsumptionOn, owner);
	-- in Current region
	RemoveSuppliesBasic(local_region, supply_consumption, SupplyConsumptionOn, false)
	--if SupplyConsumptionOn then
		--SupplyImportsExportsTable_table[depot_region] = ui_supply_shift + supply_shif
		--Supply_Region_Table[local_region] = regional_supplies - supply_consumption
	--end;
	LogSupply("SupplyFromDepot(cqi, local_region, depot_region, supply_shif, supply_consumption, SupplyConsumptionOn)","Supply line established to: "..local_region.." from: "..depot_region.." Command Queue Index: "..cqi)
	return true;
end;

-- ***** SUPPLY FORAGING ***** --

function SupplyForaging(region_id, supply_consumption, cqi, culture, isAI, SupplyConsumptionOn, owner)

	local region_name = region_id:name()
	local regional_supplies = Supply_Region_Table[region_name]

	LogSupply("SupplyForaging(region_id, supply_consumption, cqi, culture, isAI, SupplyConsumptionOn)","SupplyForaging culture: "..culture);

	local Foraging_No_Supply = "Bar_Foraging_No_Supply";
	local Foraging_1 = "Bar_Foraging_1";
	local Foraging_2 = "Bar_Foraging_2";
	local Foraging_3 = "Bar_Foraging_3";
	local Foraging_4 = "Bar_Foraging_4";

	if culture == "civilized" then
		Foraging_No_Supply = "Foraging_No_Supply";
		Foraging_1 = "Foraging_1";
		Foraging_2 = "Foraging_2";
		Foraging_3 = "Foraging_3";
		Foraging_4 = "Foraging_4" ;

	elseif culture == "nomadic" then
		Foraging_No_Supply = "Nomads_No_Supply";
		Foraging_1 = "Nomads_Foraging_1";
		Foraging_2 = "Nomads_Foraging_2";
		Foraging_3 = "Nomads_Foraging_3";
		Foraging_4 = "Nomads_Foraging_4";
	end;

	LogSupply("SupplyForaging(region_id, supply_consumption, cqi, culture, isAI, SupplyConsumptionOn)",culture.." set");

	if regional_supplies < global_supply_variables.supply_values_table["devastated_region"] then
		if (isAI and activate_attrition_for_ai == true) or not isAI then
			scripting.game_interface:apply_effect_bundle_to_characters_force(Foraging_No_Supply, cqi,-1);
			LogSupply("SupplyForaging(region_id, supply_consumption, cqi, culture, isAI, SupplyConsumptionOn)","No Supply:" ..region_name);

			if SupplyConsumptionOn then
				RemoveSuppliesBasic(region_name, supply_consumption, SupplyConsumptionOn, owner);
				AgricultureBuildingDamage(region_id, 50, Agriculture_Building_List);
			--	AgricultureBuildingDamage(region_id, 30, cattle_buildings_list);
				return;
			end;
		end;

	-- Foraging
	elseif regional_supplies < global_supply_variables.supply_values_table["looted_region"] then
		scripting.game_interface:apply_effect_bundle_to_characters_force(Foraging_4, cqi,-1);
		LogSupply( "SupplyForaging()","Low Regional Supply: " ..region_name.. " : "..regional_supplies);

		if SupplyConsumptionOn then
			RemoveSuppliesBasic(region_name, supply_consumption, SupplyConsumptionOn, owner);
			AgricultureBuildingDamage(region_id, 70,Agriculture_Building_List);
			--AgricultureBuildingDamage(region_id, 50, cattle_buildings_list);
			return;
		end;

	elseif regional_supplies < global_supply_variables.supply_values_table["foraged_region"] then
		scripting.game_interface:apply_effect_bundle_to_characters_force(Foraging_3, cqi,-1);
		LogSupply("SupplyForaging()","Medium, Regional Supply for: "..region_name.. " : "..regional_supplies);

		if SupplyConsumptionOn then
			RemoveSuppliesBasic(region_name, supply_consumption, SupplyConsumptionOn, owner);
			--AgricultureBuildingDamage(region_id, 70, cattle_buildings_list);
			return;
		end;

	elseif regional_supplies < global_supply_variables.supply_values_table["fertile_region"] then
		scripting.game_interface:apply_effect_bundle_to_characters_force(Foraging_2, cqi,-1);
		LogSupply("SupplyForaging()","Good Regional Supply for:  "..region_name.. " : "..regional_supplies);

		if SupplyConsumptionOn
		then RemoveSuppliesBasic(region_name, supply_consumption, SupplyConsumptionOn, owner);
			return;
		end;
	else
		LogSupply("SupplyForaging()","Very High regional supply for: " ..region_name.. " : "..regional_supplies);
		scripting.game_interface:apply_effect_bundle_to_characters_force(Foraging_1, cqi,-1);
		RemoveSuppliesBasic(region_name, supply_consumption, SupplyConsumptionOn, owner);
	end;
end;

-- ***** SUPPLY LINE BLOCKED ***** --
function SupplyLineBlocked(RegionName, x, y, radius, EnemyFactionKeys)

	local bool = false;
	LogSupply("SupplyLineNotBlocked(RegionName, x, y, radius, EnemyFactionKeys)", "Start SupplyLineNotBlocked", false, false);

	for _,i in pairs(EnemyFactionKeys)
	do
		local EnemyFaction = i;
		local faction = scripting.game_interface:model():world():faction_by_key(EnemyFaction);
		local forces = faction:military_force_list():num_items();

		LogSupply("SupplyLineNotBlocked(RegionName, x, y, radius, EnemyFactionKeys)","Current Enemy Faction: "..EnemyFaction, false, false);

		for i = 0, forces - 1
		do
			local force = faction:military_force_list():item_at(i);

			if force:is_army() and force:has_general() and force:general_character():has_region()
			then
				local ForceRegionName = force:general_character():region():name();

				if ForceRegionName == RegionName
				then
					if distance_2D(force:general_character():logical_position_x(), force:general_character():logical_position_y(), x, y) < radius
					then
						LogSupply("SupplyLineNotBlocked(RegionName, x, y, radius, EnemyFactionKeys)", "supply line is blocked", false, false)
						bool = true;
					end;
				else
					LogSupply("SupplyLineNotBlocked(RegionName, x, y, radius, EnemyFactionKeys)", "supply line not blocked", false, false)
					bool = false;

				end;
			end;
		end;
	end;
	return bool;
end;


-- ***** SUPPLY NEAR ENEMY FLEET ***** --
-- Returns if enemy fleet is close to object

function SupplyNearEnemyFleet(x, y, radius, subject_faction_name, EnemyFactionKeys)

	local bool = false;
	LogSupply("SupplyNearEnemyFleet(x, y, radius, subject_faction_name)", "Start SupplyNearEnemyFleet");

	for _,i in pairs(EnemyFactionKeys)
	do
		local EnemyFaction = i;

		if EnemyFaction ~= subject_faction_name
		then

			local faction = scripting.game_interface:model():world():faction_by_key(EnemyFaction);
			local forces = faction:military_force_list():num_items();

			LogSupply("SupplyNearEnemyFleet(x, y, radius, subject_faction_name)","Current Enemy Faction: "..EnemyFaction);

			for i = 0, forces - 1
			do
				local force = faction:military_force_list():item_at(i);

				if force:is_navy()
				and force:has_general()
				and force:general_character():turns_at_sea() >= 1
				and distance_2D(force:general_character():logical_position_x(), force:general_character():logical_position_y(), x, y) < radius
				then
					bool = true;
				end;
			end;
		end;
	end;
	return bool;
end;


-- ***** TAB: ALLY DIPLOMATIC TREATY TYPES ***** --
--Version 3.0. last edit 30.01.2022--
-- Global should always start with Upercase
-- added current_treaty_giving_soft_military_access_turns for friendly supplies
Ally_diplomatic_treaty_types =
	{
		"current_treaty_vassal_of_player",
		"current_treaty_client_of_player",
		"current_treaty_defensive_alliance",
		"current_treaty_military_alliance",
		"current_treaty_giving_soft_military_access_turns",
"current_treaty_trade_agreement"
	};

-- ***** SUPPLY GET FACTION TREATIES ***** --
--Version 3.0. last edit 30.01.2022--
-- fixed logging for enemy factions
function SupplyGetFactionTreaties(treaty_details)

	local AlliedFactionKeys = {};
	local EnemyFactionKeys = {};

	for faction, details in pairs(treaty_details) do
		LogSupply("SupplyGetFactionTreaties(treaty_details)","faction: "..tostring(faction));

		for k, treaty in ipairs(details) do
			LogSupply("SupplyGetFactionTreaties(treaty_details)","treaty_details: "..tostring(treaty));

			if contains(treaty, Ally_diplomatic_treaty_types) then
				table.insert(AlliedFactionKeys, tostring(faction));
				LogSupply("SupplyGetFactionTreaties(treaty_details)","Ally Faction Added: "..tostring(faction));
			elseif treaty == "current_treaty_at_war" then
				table.insert(EnemyFactionKeys, tostring(faction));
				LogSupply("SupplyGetFactionTreaties(treaty_details)","War Faction Added: "..tostring(faction));
			end;
		end;
	end;
	return AlliedFactionKeys, EnemyFactionKeys
end;

-- ***** SUPPLY LINE REQUIREMENTS ***** --

function SupplyLineRequirements(adjacent_region, region_name, faction_name, EnemyFactionKeys)

	LogSupply("SupplyLineRequirements(adjacent_region, region_name, faction_name, EnemyFactionKeys)","Start SupplyLineRequirements")
	local bool = false;

	if adjacent_region:garrison_residence():region():public_order() > global_supply_variables.supply_values_table["public_order"]
	and not SupplyLineBlocked(region_name, adjacent_region:settlement():logical_position_x(), adjacent_region:settlement():logical_position_y(), global_supply_variables.supply_values_table["radius_enemy_army"], EnemyFactionKeys)
	and Is_Winter_In_Alps(region_name) == false
	and Desert_Attrition(faction_name, region_name) == false
	then
		bool = true;
	end;
	return bool;
end;

-- ***** Build Supply Lines ***** --
--Version 3.0. last edit 30.01.2022--
-- fixed missing local var

function BuildSupplyLines(region_name, army, curr_char, char_faction, AlliedFactionKeys, EnemyFactionKeys, home_region)
-- worst thing is that we can run circles within the adjacent region checks, we need to prevent this by saving each checked region
	LogSupply("BuildSupplyLines()","Start BuildSupplyLines: "..tostring(region_name).. " ".. tostring(army)  .. " ".. tostring(curr_char).." ".. tostring(char_faction).. " ".. tostring(AlliedFactionKeys).. " ".. tostring(EnemyFactionKeys).. " ".. tostring(home_region));

	local supply_line = false;
	local supply_line_1  = false;
	local supply_line_2  = false;
	local supply_line_3 = false;
	local adjacent_region_name_1 = "";
	local adjacent_region_name_2 = "";
	local adjacent_region_name_3 = "";
	local supply_line_region_name_1 = "";
	local supply_line_region_name_2 = "";
	local supply_line_region_name_3 = "";
	local adjacent_list_1 = {};
	local adjacent_list_2 = {};
	local adjacent_list_3 = {};

	-- Region check 1.
	for i = 0, curr_char:region():adjacent_region_list():num_items() - 1
		do
			local adjacent_region = curr_char:region():adjacent_region_list():item_at(i)
			local adjacent_region_faction = adjacent_region:garrison_residence():faction():name()
			LogSupply("BuildSupplyLines()","adjacent_region_faction: "..adjacent_region_faction);

			adjacent_region_name_1 = adjacent_region:name()
			LogSupply("BuildSupplyLines()","Searching for Supply Depot in Region 1: "..adjacent_region_name_1);

		if (char_faction == adjacent_region_faction
		or contains(adjacent_region_faction, AlliedFactionKeys))
		and SupplyLineRequirements(adjacent_region, adjacent_region_name_1, char_faction, EnemyFactionKeys)
			then
				table.insert(adjacent_list_1, tostring(adjacent_region_name_1))
				LogSupply("BuildSupplyLines()","Logistic Center/Home Region 1 checking supplies: " ..adjacent_region_name_1);
		end;

		if char_faction == adjacent_region_faction
		and (adjacent_region == home_region or Region_has_Building_by_list(adjacent_region, Tier_I_Depot_List))
		and Supply_Region_Table[adjacent_region_name_1] >= global_supply_variables.supply_values_table["devastated_region"]
			then
				supply_line = true;
				supply_line_1 = true;
				supply_line_region_name_1 = adjacent_region_name_1;
				LogSupply("BuildSupplyLines()","Logistic Center/Home Region at -> Region 1: " ..adjacent_region_name_1);
			break
		end;
	end;

	LogSupply("BuildSupplyLines()","End Supply Line function 1");
	-- Region check 2.

	if supply_line_1 == false
		then
			for i = 1, #adjacent_list_1
				do
					adjacent_region_name_1 = adjacent_list_1[i]
					local adjacent_region = scripting.game_interface:model():world():region_manager():region_by_key(adjacent_region_name_1)
					LogSupply("BuildSupplyLines()","Starting Region for Supply Depot in adjacent region 2: " ..adjacent_region_name_1);

					for h = 0, adjacent_region:adjacent_region_list():num_items() - 1
						do
							local two_adjacent_region = adjacent_region:adjacent_region_list():item_at(h)
							local two_adjacent_region_faction = two_adjacent_region:garrison_residence():faction():name()
							adjacent_region_name_2 = two_adjacent_region:name()
							LogSupply("BuildSupplyLines()","Searching for Supply Depot in Region 2"..adjacent_region_name_2);

							if (char_faction == two_adjacent_region_faction
							or contains(two_adjacent_region_faction, AlliedFactionKeys))
							and not contains(adjacent_region_name_2, adjacent_list_1)
							and SupplyLineRequirements(two_adjacent_region, adjacent_region_name_2, char_faction, EnemyFactionKeys)
							then
								table.insert(adjacent_list_2, tostring(adjacent_region_name_2))
							end;

							if char_faction == two_adjacent_region_faction
							and Region_has_Building_by_list(two_adjacent_region, Tier_II_Depot_List)
							and Supply_Region_Table[adjacent_region_name_2] >= global_supply_variables.supply_values_table["devastated_region"]
							then
								supply_line = true;
								supply_line_2 = true;
								supply_line_region_name_2 = two_adjacent_region:name();

								LogSupply("BuildSupplyLines()","Logistic Center/Home Region at Region 2" ..adjacent_region_name_2);
								break
							end;
						end;
					end;
					LogSupply("BuildSupplyLines()","End Supply Line function 2");
				end;

				-- Region check 3.
				if supply_line_1 == false
				and supply_line_2 == false
				then

					for i = 1, #adjacent_list_1
					do
						adjacent_region_name_1 = adjacent_list_1[i]
						local adjacent_region = scripting.game_interface:model():world():region_manager():region_by_key(adjacent_region_name_1)

						for h = 0, adjacent_region:adjacent_region_list():num_items() - 1
						do
							local two_adjacent_region = adjacent_region:adjacent_region_list():item_at(h)
							adjacent_region_name_2 = two_adjacent_region:name()

							if contains(adjacent_region_name_2, adjacent_list_2)
							then

								for k = 0, two_adjacent_region:adjacent_region_list():num_items() - 1
								do
									local three_adjacent_region = two_adjacent_region:adjacent_region_list():item_at(k)
									local three_adjacent_region_faction = three_adjacent_region:garrison_residence():faction():name()
									adjacent_region_name_3 = three_adjacent_region:name()
									LogSupply("BuildSupplyLines()","Searching for Supply Depot in Region 3"..adjacent_region_name_3)

									if char_faction == three_adjacent_region_faction
									and region_name ~= adjacent_region_name_3
									and not contains(adjacent_region_name_3, adjacent_list_3)
									and not contains(adjacent_region_name_3, adjacent_list_2)
									and not contains(adjacent_region_name_3, adjacent_list_1)
									and Region_has_Building_by_list(three_adjacent_region, Tier_III_Depot_List)
									and SupplyLineRequirements(three_adjacent_region, adjacent_region_name_3, char_faction, EnemyFactionKeys)
									then

										LogSupply("BuildSupplyLines()","Logistic Center/Home Region 3 checking supplies" ..adjacent_region_name_3)

										if Supply_Region_Table[adjacent_region_name_3] >=global_supply_variables.supply_values_table["devastated_region"]
										then
											supply_line = true;
											supply_line_3 = true;
											supply_line_region_name_3 = three_adjacent_region:name();

											LogSupply("BuildSupplyLines()","Logistic Center/Home Region at Region 3" ..adjacent_region_name_3);
											table.insert(adjacent_list_3, tostring(adjacent_region_name_3));
											LogSupply("BuildSupplyLines()","Added to adjacent region List 3" ..adjacent_region_name_3);
											break
										end;

										if supply_line == false
										and not contains(adjacent_region_name_3, adjacent_list_3)
										then
											LogSupply("BuildSupplyLines()","Logistic Center too far away Last region name:" ..adjacent_region_name_3);
											table.insert(adjacent_list_3, tostring(adjacent_region_name_3));
											LogSupply("BuildSupplyLines()","Added to adjacent region List 3" ..adjacent_region_name_3);
										end;
									end;
								end;
							end;
						end;
					end;
					LogSupply("BuildSupplyLines()","End Supply Line function 3");
				end;
				return supply_line, supply_line_1, supply_line_2, supply_line_3, supply_line_region_name_1, supply_line_region_name_2, supply_line_region_name_3
			end;


function CivHomeRegionSupply(curr_char, region_name, home_region, army)
		local bool = false
		LogSupply("CivHomeRegionSupply()","Start Open Market Capital for: "..region_name.." Command Queue Index: "..army)
	if curr_char:region() == home_region then
		LogSupply("CivHomeRegionSupply()","Applied Effect Army Open Market Capital: "..region_name.." Command Queue Index: "..army)
		bool = true
	end
	return bool
end

function civ_own_regions_open_market(curr_char, region_name, region_id, army, x, y)
	-- Step. 2a check if open market
	local bool = false
	if curr_char:faction():state_religion() == region_id:majority_religion()
	and region_id:garrison_residence():region():public_order() > global_supply_variables.supply_values_table["public_order"]
	and distance_2D(region_id:settlement():logical_position_x(), region_id:settlement():logical_position_y(), x, y) < global_supply_variables.supply_values_table["radius_friendly"]
	then bool = true
	LogSupply("civ_own_regions_open_market()","Applied Effect Army open market in region: "..region_name.." Command Queue Index: "..army)
	end
	return bool
end

function civ_own_regions_forced_local_supply(curr_char, region_name, region_id, army, x, y)
-- Step. 2b check if forced local supply
	local bool = false
	LogSupply("civ_own_regions_forced_local_supply()","Start Army forced local supply in region for: "..region_name.." Command Queue Index: "..army)
	if distance_2D(curr_char:region():settlement():logical_position_x(), curr_char:region():settlement():logical_position_y(), x, y) < global_supply_variables.supply_values_table["radius_friendly"]
	then bool = true
	LogSupply("civ_own_regions_forced_local_supply()","Applied Effect Army forced local supply in region: "..region_name.." Command Queue Index: "..army)
	end
	return bool
end


function civ_own_regions_local_suppy_line(curr_char, region_name, region_id, army, char_faction, EnemyFactionKeys)
-- Step. 2c check local suppy line
	LogSupply("civ_own_regions_local_suppy_line()","Start Army local supply line in region for: "..region_name.." Command Queue Index: "..army)
	local bool = false
	if not SupplyLineBlocked(region_name, region_id:settlement():logical_position_x(), region_id:settlement():logical_position_y() , global_supply_variables.supply_values_table["radius_enemy_army"], EnemyFactionKeys)
	and Is_Winter_In_Alps(region_name) == false
	and Desert_Attrition(char_faction, region_name) == false
	then bool = true
	LogSupply("civ_own_regions_local_suppy_line()","Applied Effect Army local supply line in region: " ..curr_char:region():name().."Command Queue Index: "..army)
	end
	return bool
end

function civ_seaport_supply(region_id, army, char_faction, EnemyFactionKeys)
-- seaport in local region?
LogSupply("civ_seaport_supply()","Start Seaport Supply for: "..army);
local bool = false
	if Region_has_Building_by_list(region_id, Trade_Port_List)
	and not SupplyNearEnemyFleet(region_id:settlement():logical_position_x(), region_id:settlement():logical_position_y() , global_supply_variables.supply_values_table["radius_enemy_fleet"], char_faction, EnemyFactionKeys)
	then bool = true
		LogSupply("civ_seaport_supply()","Seaport Supply for: "..army);
	end;
	return bool
end

function civ_fleet_to_army_supply(region_name, army, x, y, char_faction, EnemyFactionKeys, curr_char)
-- Fleet to army supply with supply ships
	LogSupply("civ_fleet_to_army_supply()","Start Fleet close to army in region for: "..region_name.." Command Queue Index: "..army);
	local bool = false
	local char_list = curr_char:faction():character_list()

	for l = 0, char_list:num_items() - 1 do
		local naval_char = char_list:item_at(l)
		local fleet = naval_char:cqi()

		if char_is_general_with_navy(naval_char)
		and naval_char:cqi() ~= curr_char:cqi()
		and distance_2D(naval_char:logical_position_x(), naval_char:logical_position_y(), x, y) < global_supply_variables.supply_values_table["radius_fleet"]
		and Unit_Is_In_Army(naval_char, supply_ship_list)
		and not SupplyNearEnemyFleet(curr_char:logical_position_x(), curr_char:logical_position_y(), global_supply_variables.supply_values_table["radius_enemy_fleet"], char_faction, EnemyFactionKeys)
		and naval_char:turns_at_sea() <= 8
		then bool = true
			LogSupply("civ_fleet_to_army_supply()","Fleet close to army -> supply established "..region_name.." Command Queue Index: "..army)
			break
		end
	end
	return bool
end


function FleetToTransportArmySupply(curr_char, x, y)
	local bool = false
	if curr_char:faction():is_human() == true
	then
		local char_list = curr_char:faction():character_list()

		for l = 0, char_list:num_items() - 1
		do
			local naval_char = char_list:item_at(l)
			local fleet = naval_char:cqi()

			if char_is_general_with_navy(naval_char)
			and naval_char:cqi() ~= curr_char:cqi()
			and distance_2D(naval_char:logical_position_x(), naval_char:logical_position_y(), x, y) < global_supply_variables.supply_values_table["radius_transport"]
			and Unit_Is_In_Army(naval_char, supply_ship_list)
			and naval_char:turns_at_sea() <= 8
			then
				bool = true
			end;
		end;
	end;
	return bool
end;


-- ***** SUPPLY TRANSPORT SHIPS FOR CHAR ***** --
-- Transport ships

function SupplyTransportShipsforChar(curr_char, AvailableFood)

	LogSupply("SupplyTransportShips(curr_char)","Start SupplyTransportShips");

	local army = curr_char:cqi()
	local x = curr_char:logical_position_x()
	local y = curr_char:logical_position_y()
	local SupplyCosts = 0;
	local naval_supply_ship = false

	--RemoveBundle(army, supply_bundle_list);
	LogSupply("SupplyTransportShips(curr_char)","Done: removed all effect bundles for: "..army);

	if curr_char:in_port()
	and curr_char:turns_in_own_regions() == 0
	then
		SupplyCosts = SupplyTransportFleetReadyToTakeOff(curr_char)
		return SupplyCosts
	end;

	local effect_bundle = "none"
	if FleetToTransportArmySupply(curr_char, x, y) then
		if curr_char:has_region() then effect_bundle = "Army_from_Fleet_Supply"
		 else effect_bundle = "Transport_from_Fleet_Supply"
		end;
		scripting.game_interface:apply_effect_bundle_to_characters_force(tostring(effect_bundle), army,-1);
		--	scripting.game_interface:apply_effect_bundle_to_characters_force("Army_from_Fleet_Supply", army,-1);
		SupplyCosts = 2;
		LogSupply("SupplyTransportShips(curr_char)","Supply Fleet close to Transport Fleet -> supply established");
		naval_supply_ship = true;
		return SupplyCosts;
	end;

	--barb transport immunity near town
	--lets check out every region that faction has
	for factionRegions = 0, curr_char:faction():region_list():num_items() -1 do
		local char_faction_region = curr_char:faction():region_list():item_at(factionRegions)
		--local char_faction_region_name = char_faction_region:name()

		if curr_char:faction():is_human() == true
		and curr_char:faction():culture() == "rom_Barbarian"
		and naval_supply_ship == false
		and curr_char:has_garrison_residence() == false
		and distance_2D(char_faction_region:settlement():logical_position_x(), char_faction_region:settlement():logical_position_y(), x, y) <= 25
		then
			scripting.game_interface:apply_effect_bundle_to_characters_force("Sea_Sickness_Player_Barb", army,-1); LogSupply("SupplyTransportships (curr_char)", "Barbarian transport near port -> attrition immunity");
			SupplyCosts = 1;
			return SupplyCosts;
		end;
	end;

	--attrition transport sea sickness and AI
	if curr_char:faction():is_human() == true
	and naval_supply_ship == false
	and curr_char:has_garrison_residence() == false
	then
		scripting.game_interface:apply_effect_bundle_to_characters_force("Sea_Sickness_Player", army,-1);
		LogSupply("SupplyTransportships (curr_char)", "No Supply Fleet close to Transport Fleet -> No supplies established");
		return SupplyCosts;

	elseif curr_char:faction():is_human() == false
	and curr_char:has_garrison_residence() == false
	then
		scripting.game_interface:apply_effect_bundle_to_characters_force("Sea_sickness_AI", army, -1);
		LogSupply("SupplyTransportships (curr_char)", "No Supply Fleet close to Transport Fleet -> No supplies established");
		return SupplyCosts;
	end;
end;


-- ***** SUPPLY TRANSPORT FLEET READY TO TAKE OFF ***** --

function SupplyTransportFleetReadyToTakeOff(curr_char)

	local GlobalSupplies = 0;
	local army = curr_char:cqi()

	--RemoveBundle(army, supply_bundle_list);
	LogSupply("SupplyTransportFleetReadyToTakeOff(curr_char)","Done: removed all effect bundles for: "..army);

	if curr_char:faction():culture() == "rom_Barbarian" then
		scripting.game_interface:apply_effect_bundle_to_characters_force("Navy_in_port", army,-1);
	else
		scripting.game_interface:apply_effect_bundle_to_characters_force("CIV_Navy_in_port", army,-1);
		GlobalSupplies = 2;
		return GlobalSupplies;
	end;
end;


-- ***** SUPPLY NAVAL FOR CHAR ***** --
-- Fleets

function SupplyNavalforChar(curr_char)
	LogSupply("SupplyNavalforChar(curr_char)","Start naval Supply Function: "..curr_char:get_forename())

	local army = curr_char:cqi()
	local turns_at_sea = curr_char:turns_at_sea()
	local SupplyCosts = 0;

	if curr_char:has_garrison_residence() then
		SupplyCosts = SupplyAdmiralFleetReadyToTakeOff(curr_char)
		return SupplyCosts;
	end;

	if turns_at_sea == 0 then
		turns_at_sea = 1;
	end;

	if curr_char:military_force():unit_list():num_items() >= 2
		and curr_char:has_garrison_residence() == false
		and turns_at_sea <= 8
		and turns_at_sea > 0

		then LogSupply("SupplyNavalforChar(curr_char)","Remove naval effect bundles for: "..army);
			--RemoveBundle(army, naval_effect_bundles)
			scripting.game_interface:apply_effect_bundle_to_characters_force("Navy_Supply_"..turns_at_sea, army,-1)
		 return SupplyCosts;

	elseif (curr_char:faction():is_human() == false
		and (activate_attrition_for_ai == false or activate_naval_attrition_for_ai == false))
		and (char_is_general_with_navy(curr_char))
		and turns_at_sea  > 8
		and curr_char:has_military_force() == true
		and curr_char:military_force():unit_list():num_items() >= 2

		then LogSupply("SupplyNavalforChar(curr_char)","Remove naval effect bundles for: "..army);
			--RemoveBundle(army, naval_effect_bundles)
			scripting.game_interface:apply_effect_bundle_to_characters_force("Navy_Supply_8", army,-1)
		 return SupplyCosts;

	elseif (curr_char:faction():is_human() == true or (activate_attrition_for_ai == true
		and activate_naval_attrition_for_ai == true))
		and (char_is_general_with_navy(curr_char))
		and turns_at_sea > 8
		and curr_char:has_military_force() == true
		and curr_char:military_force():unit_list():num_items() >= 2

		then LogSupply("SupplyNavalforChar(curr_char)","Remove naval effect bundles for: "..army);
			--RemoveBundle(army, naval_effect_bundles)
			scripting.game_interface:apply_effect_bundle_to_characters_force("No_Supply_Navy", army,-1)
		 return SupplyCosts;
	end;
end;

-- ***** SUPPLY ADMIRAL FLEET READY TO TAKE OFF ***** --
function SupplyAdmiralFleetReadyToTakeOff(curr_char)

	local SupplyCosts = 0;
	local army = curr_char:cqi()

	LogSupply("SupplyAdmiralFleetReadyToTakeOff(curr_char)","Remove naval effect bundles for: "..army)
	RemoveBundle(army, naval_effect_bundles)
	LogSupply("SupplyAdmiralFleetReadyToTakeOff(curr_char)","add Navy_in_port"..army)

	if curr_char:faction():culture() == "rom_Barbarian" then
		scripting.game_interface:apply_effect_bundle_to_characters_force("Navy_in_port", army,-1)
		SupplyCosts = 2;
	else scripting.game_interface:apply_effect_bundle_to_characters_force("CIV_Navy_in_port", army,-1)
		SupplyCosts = 2;
	end;
	return SupplyCosts;
end;

-- ***** BaggageTrainAmmoBonus ***** --
function BaggageTrainAmmoBonus(faction)

	LogSupply("BaggageTrainAmmoBonus(faction)","Start BaggageTrainAmmoBonus")

	if faction:is_human() then

		for char = 0, faction:character_list():num_items() - 1
		 do local curr_char = faction:character_list():item_at(char)
			local army = curr_char:cqi()

			scripting.game_interface:remove_effect_bundle_from_characters_force("Baggage_Train_Ammo_Bonus", army)

			if curr_char:character_type("general")
			and curr_char:has_military_force()
			and curr_char:has_region()
			and Unit_Is_In_Army(curr_char, Baggage_train_list)

			then scripting.game_interface:apply_effect_bundle_to_characters_force("Baggage_Train_Ammo_Bonus", army,-1)
			LogSupply("BaggageTrainAmmoBonus(faction)","Add baggage train ammo bonus to "..army)
			end
		end
	end
	LogSupply("BaggageTrainAmmoBonus(faction)","BaggageTrainAmmoBonus completed")
end;

function BaggageTrainAmmoBonusChar(context)

	LogSupply("BaggageTrainAmmoBonusChar(context)","Start BaggageTrainAmmoBonusChar")

	local character = context:character()
	local faction = character:faction()
	local cqi = character:cqi()

	if faction:is_human() and not CampaignUI.IsMultiplayer()
		then scripting.game_interface:remove_effect_bundle_from_characters_force("Baggage_Train_Ammo_Bonus", cqi)

		if character:character_type("general")
		and character:has_military_force()
		and character:has_region()
		and Unit_Is_In_Army(character, Baggage_train_list)

			then scripting.game_interface:apply_effect_bundle_to_characters_force("Baggage_Train_Ammo_Bonus", cqi,-1)
		end
	end
	LogSupply("BaggageTrainAmmoBonusChar(context)","End BaggageTrainAmmoBonusChar")
end

function CivAlliedSupply(region_id, HasMinSupplies, curr_char, AlliedFactionKeys)
	local bool = false
	if curr_char:region():garrison_residence():faction():name() ~= curr_char:faction():name()
	and not region_id:garrison_residence():faction():has_food_shortage()
	and not region_id:garrison_residence():is_under_siege() then
		if contains(curr_char:region():garrison_residence():faction():name(), AlliedFactionKeys)
			and HasMinSupplies then
			bool = true
		end
	end
	return bool
end;
--Version 3.0. last edit 30.01.2022--
-- added missing curr_char variable
function WinterAttritionCheck(isAI, curr_char, turns_in_region, supply_usage)
	local effect_bundle = "none"
	local supply_value_from_table = "none"
	-- differ between player and AI
	if isAI then
		if turns_in_region <= global_supply_variables.supply_values_table["ai_civ_immune_to_attrition_turns"] then
			effect_bundle = "Baggage_Train_Winter";
			supply_value_from_table = supply_usage.."_civ_Baggage_train";
		elseif activate_attrition_for_ai == true and activate_seasonal_attrition_for_ai == true then
			effect_bundle = "Supply_Cut_Winter";
			supply_value_from_table = supply_usage.."_civ_foreign_foraging";
		end;
	elseif not isAI then
		if Unit_Is_In_Army(curr_char, Baggage_train_list)
		and turns_in_region < global_supply_variables.supply_values_table["player_civ_Baggage_train_turns"] then
			effect_bundle = "Baggage_Train_Winter";
			supply_value_from_table = supply_usage.."_civ_Baggage_train";
		else
			effect_bundle = "Supply_Cut_Winter";
			supply_value_from_table = supply_usage.."_civ_foreign_foraging";
		end;
	end;
  return effect_bundle, supply_value_from_table
end;
--Version 3.0. last edit 30.01.2022--
-- added missing curr_char variable
function SummerAttritionCheck(isAI, curr_char, turns_in_region, supply_usage)
	local effect_bundle = "none"
	local supply_value_from_table = "none"
	-- differ between player and AI
	if isAI then
		if turns_in_region <= global_supply_variables.supply_values_table["ai_civ_immune_to_attrition_turns"] then
			effect_bundle = "Baggage_Train_Summer";
			supply_value_from_table = supply_usage.."_civ_Baggage_train";
		elseif activate_attrition_for_ai == true and activate_seasonal_attrition_for_ai == true then
			effect_bundle = "Supply_Cut_Summer";
			supply_value_from_table = supply_usage.."_civ_foreign_foraging";
		end;
	elseif not isAI then
		if Unit_Is_In_Army(curr_char, Baggage_train_list)
		and turns_in_region < global_supply_variables.supply_values_table["player_civ_Baggage_train_turns"] then
			effect_bundle = "Baggage_Train_Summer";
			supply_value_from_table = supply_usage.."_civ_Baggage_train";
		else
			effect_bundle = "Supply_Cut_Summer";
			supply_value_from_table = supply_usage.."_civ_foreign_foraging";
		end;
	end;
  return effect_bundle, supply_value_from_table
end;

--Version 3.0. last edit 30.01.2022--
-- added logging and added missing function back into the game
-- renamed function to AgricultureBuildingDamage from agriculture_building_damage
function AgricultureBuildingDamage(region, number, list)
	LogSupply("AgricultureBuildingDamage()","Start AgricultureBuildingDamage in region: "..region:name())
	for building_name = 0,region:slot_list():num_items() - 1 do
		local slot = region:slot_list():item_at(building_name);
		local argiculture_buidling_name = slot:building():name()
		local regionname = region:name()
		if slot:has_building()
		and contains (slot:building():name(), list)
			then scripting.game_interface:instant_set_building_health_percent(regionname, argiculture_buidling_name, number);
			LogSupply("AgricultureBuildingDamage()","Building: "..argiculture_buidling_name.." damaged")
		end;
	end;
end;

