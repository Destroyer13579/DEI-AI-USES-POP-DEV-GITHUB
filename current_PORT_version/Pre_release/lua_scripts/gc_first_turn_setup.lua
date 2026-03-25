
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
-- Grand Campaign Setup Scripts for Divide et Impera  
-- Created by Litharion
-- Last Updated: 16/03/2018

-- The content of the script belongs to the orginial Author and as such cannot
-- be used elsewhere without express consent.
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

-- Make the script a module one
module(..., package.seeall);

-- Used to have the object library able to see the variables in this new environment
_G.main_env = getfenv(1);

-- Load libraries
scripting = require "lua_scripts.EpisodicScripting";  
require "DeI_utility_functions";

--===============================================================
-- Set default diplomatic relations for Bactria and Maurya 1.2
--===============================================================

local function gc_FirstTurnSetup(context)
  Log("gc_FirstTurnSetup","Start");
  local player_factions = GetPlayerFactionsbyName();

	-- add additional units depending on player factions
	gc_faction_setups(player_factions)
	Log("gc_FirstTurnSetup", "gc_faction_setups done");

	-- spawn cyrene army
	--scripting.game_interface:create_force ("rom_cyrenaica", "Afr_Elephants,Gre_Light_Hoplites_Cyrene,Gre_Light_Hoplites_Cyrene,AOR_17_Egyptian_Archers,Gre_Citizen_Cav_Cyrene,Gre_Hoplites_Cyrene,Gre_Hoplites_Cyrene,Gre_Light_Peltasts,Gre_Light_Peltasts,Gre_Citizen_Cav_Cyrene", "emp_libya_cyrene", 437, 222, "Cyrene_AI_army_3", true); 

	-- set starting diplomatic relations for every campaign
	scripting.game_interface:force_change_cai_faction_personality("rom_cyrenaica", "minor_eastern_alternative");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_cyrenaica", "rom_ptolemaics", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_ptolemaics", "rom_cyrenaica", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_cyrenaica", "rom_ptolemaics", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");	 
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_seleucid", "rom_ptolemaics", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_ptolemaics", "rom_seleucid", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_seleucid", "rom_ptolemaics", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_epirus", "rom_rome", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_rome", "rom_epirus", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_carthage", "rom_rome", "CAI_STRATEGIC_STANCE_NEUTRAL");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_rome", "rom_carthage", "CAI_STRATEGIC_STANCE_NEUTRAL");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_rome", "rom_syracuse", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
	scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_syracuse", "rom_rome", "CAI_STRATEGIC_STANCE_NEUTRAL");

	if not contains("rom_maurya", player_factions) and not contains("rom_baktria", player_factions) then
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_maurya", "rom_baktria", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_baktria", "rom_maurya", "CAI_STRATEGIC_STANCE_BITTER_ENEMIES");
		Log("gc_FirstTurnSetup", "Maurya and Bactria hate eachother");
	end;

	if not contains("rom_carthage", player_factions) and not contains("rom_cyrenaica", player_factions) then
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_carthage", "rom_cyrenaica", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_carthage", "rom_cyrenaica", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_cyrenaica", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_cyrenaica", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
	end;
	if not contains("rom_carthage", player_factions) and not contains("rom_gaetuli", player_factions) then
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_carthage", "rom_gaetuli", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_carthage", "rom_gaetuli", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_gaetuli", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_gaetuli", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
	end;
	if not contains("rom_carthage", player_factions) and not contains("rom_garamantia", player_factions) then
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_carthage", "rom_garamantia", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_carthage", "rom_garamantia", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_garamantia", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_garamantia", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
	end;
	if not contains("rom_carthage", player_factions) and not contains("rom_nasamones", player_factions) then
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_carthage", "rom_nasamones", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_carthage", "rom_nasamones", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_promote_specified_stance_towards_target_faction("rom_nasamones", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
		scripting.game_interface:cai_strategic_stance_manager_block_all_stances_but_that_specified_towards_target_faction("rom_nasamones", "rom_carthage", "CAI_STRATEGIC_STANCE_FRIENDLY");
	end;
end;

function gc_faction_setups(player_factions)
  Log("gc_faction_setups", "Start");
  
  local is_multiplayer = scripting.game_interface:model():is_multiplayer(); -- CampaignUI.IsMultiplayer();
  Log("gc_faction_setups", "Campaign is Multiplayer: "..tostring(is_multiplayer));
  
  local difficulty = scripting.game_interface:model():difficulty_level();
  Log("gc_faction_setups", "difficulty level "..tostring(difficulty));

	if is_multiplayer then difficulty = -1 end;
	-- start all functions for each faction
	Pyrrhus_Setup(player_factions, is_multiplayer, difficulty);
	RomeStart_Setup(player_factions, is_multiplayer, difficulty);
	EgyptStart_Setup(player_factions, is_multiplayer, difficulty);
	SeleucidStart_Setup(player_factions, is_multiplayer, difficulty);
end;

--===============================================================
-- Set Pyrrhus starting army based on difficulty -- 
--===============================================================

function Pyrrhus_Setup(player_factions, is_multiplayer, difficulty)

	if contains("rom_rome", player_factions) then
	  Log("Pyrrhus_Setup", "Rome is a player faction");
		if is_multiplayer and contains("rom_epirus", player_factions) then
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_lucanian_hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Cav");
		 return;
		else
		-- add additonal units, we always add at least 3 if rome is a player
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_lucanian_hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Cav");
			-- add more units if higher difficulty than easy
			if difficulty == 0 then -- normal
			  --scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			elseif difficulty == -1 then -- hard
			 -- scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Italy_Taurisci_Axemen");
			elseif difficulty == -2 then -- very hard
			--  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Italy_Taurisci_Axemen");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
			elseif difficulty == -3 then -- legendary
			 -- scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Italy_Taurisci_Axemen");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Cav");
			end; 
		end;
	end;

	if contains("rom_syracuse", player_factions) then
	  Log("Pyrrhus_Setup", "Syracuse is a player faction");
		if is_multiplayer and contains("rom_epirus", player_factions) then
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_lucanian_hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Cav");
		 return;
		else
		  -- add additonal units, we always add at least 3 if Syracuse is a player
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_lucanian_hoplites");
		  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Cav");
		  -- add more units if higher difficulty than easy
			if difficulty == 0 then 
			  --scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			elseif difficulty == -1 then 
			  --scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Italy_Taurisci_Axemen");
			elseif difficulty == -2 then 
			  --scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_lucanian_hoplites");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
			elseif difficulty == -3 then 
			  --scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Apulian_Infantry");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_lucanian_hoplites");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Hoplites");
			  scripting.game_interface:grant_unit("settlement:emp_italia_brundisium", "AOR_9_Campanian_Cav");
			end;
		end;
	end;
end;

--===============================================================
-- Set Rome starting army based on difficulty -- 
--===============================================================

function RomeStart_Setup(player_factions, is_multiplayer, difficulty)
  local enemy_to_rome = false;
	if contains("rom_epirus", player_factions) or contains("rom_syracuse", player_factions) or contains("rom_carthage", player_factions) 
	  then enemy_to_rome = true 
	  Log("RomeStart_Setup", "An Enemy to Rome is a player faction");
	end;

-- if player is not rom_syracuse, rom_carthage, rom_epirus
	if not enemy_to_rome
	  and not contains("rom_rome", player_factions)
	 then
		-- add additonal units when player is not epirus, syracuse or carthage
		scripting.game_interface:grant_unit("settlement:emp_italia_cosentia", "Rom_Equites_Extraordinarii_Early_Allied");
		scripting.game_interface:grant_unit("settlement:emp_italia_cosentia", "AOR_10_Italian_Slingers");
		scripting.game_interface:grant_unit("settlement:emp_italia_beneventum", "Rom_Equites");
		scripting.game_interface:grant_unit("settlement:emp_italia_beneventum", "Rom_Accensi_Mod");
	-- add more based on difficulty not depending on player factions to make Rome stronger from the start
		if difficulty == -2 then -- very hard
		  scripting.game_interface:grant_unit("settlement:emp_italia_cosentia", "AOR_10_Sicily_Bruttian_Infantry");
		  scripting.game_interface:grant_unit("settlement:emp_italia_cosentia", "Rom_Hastati_Early_Allied");	  
		  scripting.game_interface:grant_unit("settlement:emp_italia_beneventum", "Rom_Hastati");
		  scripting.game_interface:grant_unit("settlement:emp_italia_beneventum", "Rom_Principes");
		elseif difficulty == -3 then -- legendary
		  scripting.game_interface:grant_unit("settlement:emp_italia_cosentia", "AOR_10_Sicily_Bruttian_Infantry");
		  scripting.game_interface:grant_unit("settlement:emp_italia_cosentia", "Rom_Principes_Early_Allied");
		  scripting.game_interface:grant_unit("settlement:emp_italia_cosentia", "Rom_Hastati_Early_Allied");	  
		  scripting.game_interface:grant_unit("settlement:emp_italia_beneventum", "Rom_Hastati");
		  scripting.game_interface:grant_unit("settlement:emp_italia_beneventum", "Rom_Principes");	  
		  scripting.game_interface:grant_unit("settlement:emp_italia_beneventum", "Rom_Principes");
		end;
	end;
end;

--===============================================================
-- Set Egypt starting army if player is Seleucid -- 
--===============================================================

function EgyptStart_Setup(player_factions, is_multiplayer, difficulty)
	if contains("rom_seleucid", player_factions) then
	  Log("EgyptStart_Setup", "seleucid is a player faction");
		if is_multiplayer and contains("rom_ptolemaics", player_factions) then
		  -- add additonal units if player is seleucid
		  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Kleruchoi_Pike");
		  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Kleruchoi_Pike");
		  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Gre_Skirm_Cav"); 
		 return;
		else
		  -- add additonal units if player is seleucid
		  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Kleruchoi_Pike");
		  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Kleruchoi_Pike");
		  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Gre_Skirm_Cav"); 
			-- add more based on difficulty
			if difficulty == 0 then -- normal
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "AOR_19_Jewish_Slingers");
			elseif difficulty == -1 then -- hard
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Karian_Spear");
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "AOR_19_Jewish_Slingers");
			elseif difficulty == -2 then -- very hard
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Karian_Spear");
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Slingers");
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "AOR_19_Jewish_Slingers");
			elseif difficulty == -3 then -- legendary
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Karian_Spear");
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Slingers");
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "AOR_19_Jewish_Slingers");
			  scripting.game_interface:grant_unit("settlement:emp_judea_jerusalem", "Egy_Kleruchoi_Pike");
			end;
		end;
	end;
end;
--===============================================================
-- Set Seleucid starting army if player is Egypt -- 
--===============================================================

function SeleucidStart_Setup(player_factions, is_multiplayer, difficulty)
	if contains("rom_ptolemaics", player_factions) then
	  Log("SeleucidStart_Setup", "ptolemaics is a player faction");
		if is_multiplayer and contains("rom_seleucid", player_factions) then
		  -- add additonal units if player ptolemaics
		  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "AOR_21_Syrian_War_Elephants");
		  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "AOR_22_Mesopotamian_Archers");
		  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Bronze_Shield_Pike");
		 return;
		else
		  -- add additonal units if player ptolemaics
		  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "AOR_21_Syrian_War_Elephants");
		  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "AOR_22_Mesopotamian_Archers");
		  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Bronze_Shield_Pike"); 
			-- add more based on difficulty
			if difficulty == 0 then -- normal
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Skirm_Cav");
			elseif difficulty == -1 then -- hard
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Skirm_Cav");
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Javelinmen");
			elseif difficulty == -2 then -- very hard
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Skirm_Cav");
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Javelinmen");
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Bronze_Shield_Pike");
			elseif difficulty == -3 then -- legendary
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Skirm_Cav");
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Javelinmen");
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "Gre_Bronze_Shield_Pike");
			  scripting.game_interface:grant_unit("settlement:emp_syria_antioch", "AOR_21_Syrian_War_Elephants"); 
			end;
		end;
	end;
end;

-- make parthia stronger as well

scripting.AddEventCallBack("NewCampaignStarted", gc_FirstTurnSetup);
