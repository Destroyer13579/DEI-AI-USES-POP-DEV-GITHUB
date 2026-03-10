
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
-- Grand Campaign Scripts for Divide et Impera  
-- Created by Litharion
-- Last Updated: 16/03/2018

-- The content of the script belongs to the orginial Author and as such cannot
-- be used elsewhere without express consent.
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------

-- Make sure escalation triggers when Rome and Carthage are at war faction declares war

-- Make the script a module one
module(..., package.seeall);

-- Used to have the object library able to see the variables in this new environment
_G.main_env = getfenv(1);

-- Load libraries
scripting = require "lua_scripts.EpisodicScripting";  
require "DeI_utility_functions";

-- Variables
AICarthageRomeEscalationTriggered = false;
AIRomeCarthageEscalationTriggered = false;
AICarthageRomeEscalationLevel = 0;
AIRomeCarthageEscalationLevel = 0;
carthage_army_2 = false;
carthage_army_3 = false;
roman_counter = 0;
upgrade_advisor_shown = {upgrade_advisor = false};
seleucid_army_1 = false;
seleucid_army_2 = false;
seleucid_army_3 = false;
seleucid_army_4 = false;
seleucid_army_5 = false;


-- Submod toggle


DISABLE_SCRIPTED_WARS = true;



-- FactionCampaignScripts Listener --


-- loading setup everytime the game enters the campaign map
local function OnWorldCreatedCampaign(context)
	AddCampaignListener();
	Log("OnWorldCreatedCampaign(context)", "Campaign script world created", true, true);
end;

function AddCampaignListener()
  Log("OnWorldCreatedCampaign()", "#### Adding Campaign Listeners ####", false, false);
  local turn_num = scripting.game_interface:model():turn_number()

  cm:add_listener(
	"FactionTurnStart_RomeDefense",
	"FactionTurnStart",
	function(context)
		local faction = context:faction();
		return faction:name() == "rom_rome" and not faction:is_human();
	end,
	function(context)
		--RomeArmyScript(context, turn_num);
		-- RomeCarthageEscalation(context) -- disabled: no scripted wars
		Log("RomeArmyScript done")
	end,
	true
  );

  cm:add_listener(
	"FactionTurnStart_CarthageDefense",
	"FactionTurnStart",
	function(context)
		local faction = context:faction();
		return faction:name() == "rom_carthage" and not faction:is_human();
	end,
	function(context)
		--CarthageArmyScript(context, turn_num);
		-- CarthageRomeEscalation(context) -- disabled: no scripted wars
		Log("CarthageArmyScript done");
	end,
	true
  );
  cm:add_listener(
	"FactionTurnStart_Seleucid_Army",
	"FactionTurnStart",
	function(context)
		local faction = context:faction();
		return faction:name() == "rom_seleucid" and not faction:is_human();
	end,
	function(context)
		--SeleucidArmyScript(context, turn_num);
		Log("SeleucidArmyScript done");
	end,
	true
  );
end;

scripting.AddEventCallBack("WorldCreated", OnWorldCreatedCampaign); 

--===============================
-- Historical City Information --
--===============================

region_intros_played = {
		["emp_africa_carthago"] = 0, 
		["emp_sicily_syracuse"] = 0, 
		["emp_achaia_athenae"] = 0, 
		["emp_achaia_sparta"] = 0, 
		["emp_aegyptos_alexandria"] = 0, 
		["emp_macedonia_thessalonica"] = 0, 
		["emp_syria_antioch"] = 0, 
		["emp_latium_roma"] = 0, 
		--["rom_parthia_astauene"] = 0, 
		["emp_asia_rhodos"] = 0, 
		--["rom_persis_parsa"] = 0,
		["emp_asia_pergamum"] = 0,
		["emp_mesopotamia_ctesiphon"] = 0,
		["emp_bosporus_panticapaeum"] = 0, 
		["emp_narbonensis_massilia"] = 0, 
		["emp_judea_jerusalem"] = 0, 
		["emp_pretanic_isles_eilodon"] = 0,
		["emp_pannonia_singidun"] = 0, 
		["emp_macedonia_apollonia"] = 0,
		["emp_galatia_et_cappadocia_ancyra"] = 0,
		--["rom_ponto_caspia_cimmeria"] = 0,
		["emp_corsica_et_sardinia_caralis"] = 0,
		["emp_raetia_et_noricum_noreia"] = 0,
		["emp_libya_cyrene"] = 0,
};

local function OnSettlementSelected(context)
	if not CampaignUI.IsMultiplayer() then
	  local region_name = context:garrison_residence():region()
		for i,v in pairs(region_intros_played) do
			if i == region_name:name() then
				if v == 0 then 
				  region_intros_played[i] = 1;
				  effect.advance_contextual_advice_thread("GC.Region.Intro." ..region_name:name(),  1, context);
				end;
			end;
		end;
	end;
end;

--==============================================================
-- Upgrade Advisor
--==============================================================

local function Upgrades(context)
	if not upgrade_advisor_shown.upgrade_advisor 
	  and context:character():faction():is_human() == true
	  and (context:character():faction():culture() == "rom_Roman" 
	  or context:character():faction():culture() == "rom_Hellenistic"
	  or context:character():faction():subculture() == "sc_rom_celtiberian"
	  or context:character():faction():subculture() == "sc_rom_daco_thracian")
		then effect.advance_contextual_advice_thread("RR.Roman.Reforms", 1, context);
		  upgrade_advisor_shown.upgrade_advisor = true;
	end;
end;


--message_event_text_text_sicily_global_rome	With Roman armies marching into Sicily, the relationship between Rome and Carthage has deteriorated into open warfare. Carthage will respond by quickly mustering a force of their own to repel the Roman expedition.	
--message_event_text_text_syracuse_global	Carthage and Syracuse are at or on the brink of war, in an attempt to gain control over the island of Sicily. A small Carthaginian expeditionary force has already set foot on the island. This will rouse the intense interest of the Roman Republic.	
--message_event_text_text_sicily_over	Carthaginian forces were decisively beaten in Lilybaion. The Carthaginians have lost their foothold on the island, and reorganize their defense near Carthage's coastline, only a small journey away from Lilybaion.	
--message_event_text_text_sicily_global_carthage	Carthage is gaining the upper hand in Sicily. Syrakousai might fall, granting Carthage complete control over the island of Sicily.	
--message_event_text_text_sicily_global_carthage2	The city of Syrakousai has fallen to the Carthaginians. With the threat of a Punic Sicily on its doorstep, Roma now views their former allies in Carthage as enemies. War has begun.	

--custom_event_173			sicily_global_rome
--custom_event_174			syracuse_global?????
--custom_event_175			sicily_over
--custom_event_176			sicily_global_carthage
--custom_event_179			sicily_global_carthage2

--============================
-- Rome Carthage Escalation -- 
--============================
-- Player is not Rome


--============================
-- Carthage Rome Escalation -- 
--============================
-- Player is not Carthage


--===================================
-- Carthage AI Army Defense Script -- 
--===================================



-----------------------------------------------------------
--------------Seleucid army script
----------------------------------------------------------



--===========================================================
-- Save/Load
--===========================================================
local function Save_Values(context)
scripting.game_interface:save_named_value("AICarthageRomeEscalationTriggered", AICarthageRomeEscalationTriggered, context);
scripting.game_interface:save_named_value("AIRomeCarthageEscalationTriggered", AIRomeCarthageEscalationTriggered, context);
scripting.game_interface:save_named_value("AICarthageRomeEscalationLevel", AICarthageRomeEscalationLevel, context);
scripting.game_interface:save_named_value("AIRomeCarthageEscalationLevel", AIRomeCarthageEscalationLevel, context);
  scripting.game_interface:save_named_value("roman_counter", roman_counter, context);
  scripting.game_interface:save_named_value("carthage_army_2", carthage_army_2, context);
  scripting.game_interface:save_named_value("carthage_army_3", carthage_army_3, context);
    scripting.game_interface:save_named_value("seleucid_army_1", seleucid_army_1, context);
	  scripting.game_interface:save_named_value("seleucid_army_2", seleucid_army_2, context);
	    scripting.game_interface:save_named_value("seleucid_army_3", seleucid_army_3, context);
		  scripting.game_interface:save_named_value("seleucid_army_4", seleucid_army_4, context);
		    scripting.game_interface:save_named_value("seleucid_army_5", seleucid_army_5, context);
  scripting.game_interface:save_named_value ("upgrade_advisor", upgrade_advisor_shown.upgrade_advisor, context);
  for i,value in pairs(region_intros_played) do
    scripting.game_interface:save_named_value("region_intros_played"..i, value, context)
  end;
end;

local function Load_Values(context)
AICarthageRomeEscalationTriggered = scripting.game_interface:load_named_value("AICarthageRomeEscalationTriggered", false, context);
AIRomeCarthageEscalationTriggered = scripting.game_interface:load_named_value("AIRomeCarthageEscalationTriggered", false, context);
AICarthageRomeEscalationLevel = scripting.game_interface:load_named_value("AICarthageRomeEscalationLevel", 0, context);
AIRomeCarthageEscalationLevel = scripting.game_interface:load_named_value("AIRomeCarthageEscalationLevel", 0, context);
  roman_counter = scripting.game_interface:load_named_value("roman_counter", 0, context);
  carthage_army_2 = scripting.game_interface:load_named_value("carthage_army_2", false, context);
    carthage_army_3 = scripting.game_interface:load_named_value("carthage_army_3", false, context);
	    seleucid_army_1 = scripting.game_interface:load_named_value("seleucid_army_1", false, context);
		    seleucid_army_2 = scripting.game_interface:load_named_value("seleucid_army_2", false, context);
			    seleucid_army_3 = scripting.game_interface:load_named_value("seleucid_army_3", false, context);
				    seleucid_army_4 = scripting.game_interface:load_named_value("seleucid_army_4", false, context);
					    seleucid_army_5 = scripting.game_interface:load_named_value("seleucid_army_5", false, context);
  upgrade_advisor_shown.upgrade_advisor = scripting.game_interface:load_named_value("upgrade_advisor", false, context);
  for i,value in pairs(region_intros_played) do
    region_intros_played[i] = scripting.game_interface:load_named_value("region_intros_played"..i, 0, context)
  end;
end;

---------------------------------------------------------------------------------------------------------------------------------
scripting.AddEventCallBack("LoadingGame", Load_Values);
scripting.AddEventCallBack("SavingGame", Save_Values);
scripting.AddEventCallBack("SettlementSelected", OnSettlementSelected);
scripting.AddEventCallBack("CharacterSelected", Upgrades);
