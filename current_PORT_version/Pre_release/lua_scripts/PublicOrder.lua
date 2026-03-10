
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
-- Public Order Script for Divide et Impera  
-- Created by Litharion
-- Last Updated: 07/12/2017

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

public_order_effects = {
				"public_1_order",
				"public_2_order",
				"public_3_order",
				"public_4_order",
				"public_5_order",
				"public_6_order",
				"public_7_order",
				"public_8_order",
				"public_9_order",
				"public_10_order",
				"public_11_order",
				"public_12_order",
				"public_13_order",
				"public_14_order",
				"public_15_order",
				"public_16_order",
				"public_17_order",
				"public_18_order",
				"public_19_order",
				"public_20_order",
				"public_21_order",
				"public_22_order",
				"public_23_order",
				"public_24_order",
				"public_25_order",
				"public_26_order",
				"public_27_order",
				"public_28_order",
				"public_29_order",
				"public_30_order"
};

--==============================================================
-- Public Order Army Script 1.0
--===============================================================
local function PublicOrderFleets(context)
	if context:character():faction():is_human() == true 
	 and context:character():military_force():unit_list():num_items() >= 2 then
	 local faction = context:character():faction();
	 local province = context:character():garrison_residence():region():province_name();
	 local factions_regions = faction:region_list();
	 local public_order_negative = 0;
	 local matched_regions = 0;

		for i = 0, factions_regions:num_items() - 1 do
		 local region = factions_regions:item_at(i);
		 local region_name = region:province_name();

			if region_name == province then
			 matched_regions = matched_regions + 1;
			end;
		end;

	 local multiplier = 0;
	 local divisor = 1;
	 local max_public_order_negative = 25;

  if matched_regions <= 1 then 
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then multiplier = 1.3
    else multiplier = 1.5 
    end;
  elseif matched_regions == 2 then
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then multiplier = 1.2
        max_public_order_negative = 20
    else multiplier = 1.3
    end;
  elseif matched_regions > 2 then 
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then divisor = 1.35
        max_public_order_negative = 15  
    end;  
  end;

  if matched_regions < 3 then
    public_order_negative = math.ceil(context:character():military_force():unit_list():num_items()*multiplier)
  else 
    public_order_negative = math.ceil(context:character():military_force():unit_list():num_items()/divisor)
  end
   
  if public_order_negative > max_public_order_negative
    then public_order_negative = max_public_order_negative
  end;

  if context:character():has_garrison_residence() == true
    and context:character():faction():is_human() == true  
    and (char_is_general_with_navy(context:character()) or context:character():turns_in_own_regions() == 0 and char_is_general_with_army(context:character()))
   then
    local currentpublicorder = context:character():garrison_residence():region():public_order()
    local newpublicorder = currentpublicorder - public_order_negative
    local char_region = context:character():garrison_residence():region():name() 
    scripting.game_interface:set_public_order_of_province_for_region(char_region, newpublicorder); 
  end
end
end

--==============================================================
-- Apply Public Order effect bundle to character force 1.0
--===============================================================

local function PublicOrderApply(context)
if context:character():faction():is_human() == true 
and context:character():military_force():unit_list():num_items() >= 2
then 
    local faction = context:character():faction();
    local province = context:character():garrison_residence():region():province_name()
    local factions_regions = faction:region_list();
    local public_order_negative = 0;

    local matched_regions = 0;

     for i = 0, factions_regions:num_items() - 1 do
      local region = factions_regions:item_at(i);
      local region_name = region:province_name();

      if region_name == province then
        matched_regions = matched_regions + 1;
      end;
    end;

  local multiplier = 1
  local divisor = 1
  local max_public_order_negative = 25

  if matched_regions <= 1 then 
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then multiplier = 1.3
    else multiplier = 1.5 
    end;
  elseif matched_regions == 2 then
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then multiplier = 1.2
        max_public_order_negative = 20
    else multiplier = 1.3
    end;
  elseif matched_regions > 2 then 
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then divisor = 1.35
        max_public_order_negative = 15  
    end;  
  end;

  if matched_regions < 3 then
    public_order_negative = math.ceil(context:character():military_force():unit_list():num_items()*multiplier)
  else 
    public_order_negative = math.ceil(context:character():military_force():unit_list():num_items()/divisor)
  end
   
  if public_order_negative > max_public_order_negative
    then public_order_negative = max_public_order_negative
  end;

-- assign effect bundle

  if context:character():has_garrison_residence() == true
    and context:character():faction():is_human() == true  
    and ((char_is_general_with_army(context:character())) or (char_is_general_with_navy(context:character()))) 
      then 
  
      local cqi = context:character():cqi() 
  
      for i = 1, #public_order_effects do
        scripting.game_interface:remove_effect_bundle_from_characters_force(public_order_effects[i], cqi);
      end;
      scripting.game_interface:apply_effect_bundle_to_characters_force("public_"..public_order_negative.."_order", cqi, 1);
		if (context:character():has_skill("general_rightful_sovereign_2_patron_of_the_military"))
			then
			scripting.game_interface:apply_effect_bundle_to_characters_force("dei_garrison_repression_effect_bundle", cqi, 1);
			end;
	  
	end; 
	end

	end
	



--==============================================================
-- Remove Public Order effect bundle from chatacter force 1.2
--===============================================================

local function PublicOrderRemove(context)

  if context:character():faction():is_human() == true then

   local cqi = context:character():cqi() 

    for i = 1, #public_order_effects do
      scripting.game_interface:remove_effect_bundle_from_characters_force(public_order_effects[i], cqi);
    end;
	scripting.game_interface:remove_effect_bundle_from_characters_force("dei_garrison_repression_effect_bundle", cqi);
  end;
end;

--==============================================================
-- Advisor PublicOrderDisplay Public Order Penalties 1.2
--===============================================================
local function PublicOrderDisplay(context)
if context:character():military_force():unit_list():num_items() >= 2
and context:character():faction():is_human() == true 
and (char_is_general_with_navy(context:character())) 
then 
    local faction = context:character():faction();
    local province = province_from_regionname(context:character():garrison_residence():region():name());
    local factions_regions = faction:region_list();
    local max_public_order_negative = 15;
    local public_order_negative = 0;

    local matched_regions = 0;

     for i = 0, factions_regions:num_items() - 1 do
      local region = factions_regions:item_at(i);
      local region_name = region:province_name();

      if region_name == province then
        matched_regions = matched_regions + 1;
      end;
    end;

  local multiplier = 0
  local divisor = 1
  local max_public_order_negative = 25

  if matched_regions <= 1 then 
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then multiplier = 1.3
    else multiplier = 1.5 
    end;
  elseif matched_regions == 2 then
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then multiplier = 1.2
        max_public_order_negative = 20
    else multiplier = 1.3
    end;
  elseif matched_regions > 2 then 
    if context:character():faction():state_religion() == context:character():garrison_residence():region():majority_religion() 
      then divisor = 1.35
        max_public_order_negative = 15  
    end;  
  end;

  if matched_regions < 3 then
    public_order_negative = math.ceil(context:character():military_force():unit_list():num_items()*multiplier)
  else 
    public_order_negative = math.ceil(context:character():military_force():unit_list():num_items()/divisor)
  end
   
  if public_order_negative > max_public_order_negative
    then public_order_negative = max_public_order_negative
  end;
effect.advance_contextual_advice_thread("Public."..public_order_negative..".Order", 1, context);
end
end

----------------------------------------------------------------------------------------------------------------------------------------
scripting.AddEventCallBack("CharacterTurnEnd", PublicOrderFleets);
scripting.AddEventCallBack("CharacterSelected", PublicOrderDisplay);
scripting.AddEventCallBack("CharacterLeavesGarrison", PublicOrderRemove);
scripting.AddEventCallBack("CharacterEntersGarrison", PublicOrderApply);
scripting.AddEventCallBack("CharacterTurnEnd", PublicOrderApply);
scripting.AddEventCallBack("CharacterTurnStart", PublicOrderApply);
-------------------------------------------------------------------------------------------------------------------------------------------

--==========================================================================
-- Faction Leader Global Admininstration 1.2
--==========================================================================
-- faction leader trait lists add traits as strings to the specific arrays
-- adapt effects add loyalty

faction_leader_traits_beloved = {
		"r2_sp_trait_greco_roman_humors_virtuous",
		"r2_sp_trait_greco_roman_humors_blood"
};

faction_leader_traits_feared = {
		"r2_sp_trait_greco_roman_humors_borderline",
		"r2_sp_trait_greco_roman_humors_sociopath",
		"r2_sp_trait_greco_roman_humors_yellow_bile"
};

faction_leader_traits_selfish = {
		"r2_sp_trait_greco_roman_humors_egotistic",
		"r2_sp_trait_greco_roman_humors_narcissistic"
};

faction_leader_traits_disdained = {
		"r2_sp_trait_greco_roman_humors_dependent",
		"r2_sp_trait_greco_roman_humors_histrionic",
		"r2_sp_trait_greco_roman_humors_black_bile"
};

faction_leader_traits_engaged = {
		"r2_sp_trait_greco_roman_humors_magnanimous",
		"r2_sp_trait_greco_roman_humors_obsessive"
};

faction_leader_traits_reserved = {
		"r2_sp_trait_greco_roman_humors_circumspect",
		"r2_sp_trait_greco_roman_humors_phlegm",
		"r2_sp_trait_greco_roman_humors_philosophic"
};

function FactionLeaderCheckTraits(char, factionName)
-- remove old effect bundles 
  scripting.game_interface:remove_effect_bundle("faction_leader_administration_very_bad", factionName);   
  scripting.game_interface:remove_effect_bundle("faction_leader_administration_bad", factionName); 
  scripting.game_interface:remove_effect_bundle("faction_leader_administration", factionName);
  scripting.game_interface:remove_effect_bundle("faction_leader_administration_good", factionName);   
  scripting.game_interface:remove_effect_bundle("faction_leader_administration_very_good", factionName);
  scripting.game_interface:remove_effect_bundle("dei_faction_leader_beloved", factionName);   
  scripting.game_interface:remove_effect_bundle("dei_faction_leader_feared", factionName); 
  scripting.game_interface:remove_effect_bundle("dei_faction_leader_selfish", factionName);
  scripting.game_interface:remove_effect_bundle("dei_faction_leader_disdained", factionName);   
  scripting.game_interface:remove_effect_bundle("dei_faction_leader_engaged", factionName);
   scripting.game_interface:remove_effect_bundle("dei_faction_leader_reserved", factionName);

local FactionLeaderEffect = "faction_leader_administration"

for i = 1, #faction_leader_traits_beloved do
  if char:has_trait(faction_leader_traits_beloved[i])
    then FactionLeaderEffect = "dei_faction_leader_beloved";
      scripting.game_interface:apply_effect_bundle(FactionLeaderEffect, factionName, 0); 
	  scripting.game_interface:remove_effect_bundle("political_instability", factionName);
    return;
  end;
end; 

for i = 1, #faction_leader_traits_feared do
  if char:has_trait(faction_leader_traits_feared[i])
    then FactionLeaderEffect = "dei_faction_leader_feared";
      scripting.game_interface:apply_effect_bundle(FactionLeaderEffect, factionName, 0);
		scripting.game_interface:remove_effect_bundle("political_instability", factionName);
    return;
  end;
end; 

for i = 1, #faction_leader_traits_selfish do
  if char:has_trait(faction_leader_traits_selfish[i])
    then FactionLeaderEffect = "dei_faction_leader_selfish";
      scripting.game_interface:apply_effect_bundle(FactionLeaderEffect, factionName, 0);
     
    return;
  end;
end; 

for i = 1, #faction_leader_traits_disdained do
  if char:has_trait(faction_leader_traits_disdained[i])
    then FactionLeaderEffect = "dei_faction_leader_disdained";
      scripting.game_interface:apply_effect_bundle(FactionLeaderEffect, factionName, 0);
     
    return;
  end;
end; 

for i = 1, #faction_leader_traits_engaged do
  if char:has_trait(faction_leader_traits_engaged[i])
    then FactionLeaderEffect = "dei_faction_leader_engaged";
      scripting.game_interface:apply_effect_bundle(FactionLeaderEffect, factionName, 0);
	  scripting.game_interface:remove_effect_bundle("political_instability", factionName);
     
    return;
  end;
end; 

for i = 1, #faction_leader_traits_reserved do
  if char:has_trait(faction_leader_traits_reserved[i])
    then FactionLeaderEffect = "dei_faction_leader_reserved";
      scripting.game_interface:apply_effect_bundle(FactionLeaderEffect, factionName, 0);
     
    return;
  end;
end; 

-- if we got that far we will add the moderate effect
  scripting.game_interface:apply_effect_bundle(FactionLeaderEffect, factionName, 0);
  scripting.game_interface:remove_effect_bundle("political_instability", factionName);
end;


local function FactionLeaderCapital(context)
local faction = context:faction()
  if faction:is_human() then
    for char = 0, faction:character_list():num_items() - 1 do
    local curr_char = faction:character_list():item_at(char)
    local curr_cqi = curr_char:cqi()
      if curr_char:is_faction_leader() then 
       FactionLeaderInCapital(curr_char, faction:name())
      break;
      end;
    end;
  end;
end;

function FactionLeaderInCapital(char, factionName)
  if char:is_faction_leader() == true  
  then 
    FactionLeaderCheckTraits(char, factionName)
  else 
    scripting.game_interface:remove_effect_bundle("faction_leader_administration_very_bad", factionName);
    scripting.game_interface:remove_effect_bundle("faction_leader_administration_bad", factionName);
    scripting.game_interface:remove_effect_bundle("faction_leader_administration", factionName);
    scripting.game_interface:remove_effect_bundle("faction_leader_administration_good", factionName);
    scripting.game_interface:remove_effect_bundle("faction_leader_administration_very_good", factionName);
  end;
end; 

local function FactionLeaderEntersCapital(context)
  local char = context:character()
  if char:is_faction_leader() == true and char:faction():is_human() 
    then FactionLeaderInCapital(char, char:faction():name())
  end;
end;    

local function FactionLeaderDies(context)
-- only apply effect after first turn  
  turn_number = getTurn();
    if turn_number == 1 then 
     return;
    end; 

  local factionName = context:character():faction():name();
  local char = context:character();

    if char:faction():is_human() then
      scripting.game_interface:apply_effect_bundle("political_instability", factionName, 6)
    end;
end;

local function FactionLeaderStart(context)
  local char = context:character()
-- apply faction leader effect
  if char:is_faction_leader() == true
   and char:military_force():unit_list():num_items() >= 1 then
     local cqi = char:cqi()                    
    scripting.game_interface:apply_effect_bundle_to_characters_force("your_faction_leader", cqi,2);
  elseif char:military_force():unit_list():num_items() >= 1 then
      local cqi = char:cqi() 
-- remove faction leader effect
    scripting.game_interface:remove_effect_bundle_from_characters_force("your_faction_leader", cqi);
    end;
end;

-----------------------------------------------------------------------------
scripting.AddEventCallBack("FactionTurnStart", FactionLeaderCapital);
scripting.AddEventCallBack("CharacterEntersGarrison", FactionLeaderEntersCapital);
scripting.AddEventCallBack("CharacterLeavesGarrison", FactionLeaderEntersCapital);
scripting.AddEventCallBack("CharacterBecomesFactionLeader", FactionLeaderDies);
scripting.AddEventCallBack("CharacterTurnStart", FactionLeaderStart);
scripting.AddEventCallBack("CharacterTurnEnd", FactionLeaderStart);

