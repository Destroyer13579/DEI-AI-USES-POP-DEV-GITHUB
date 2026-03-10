---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
-- AI auto resolve bonus script for Divide et Impera  
-- Created by Litharion
-- Last Updated: 18/03/2018
--
-- Modified: AI Uses Population submod - Balanced major faction bonuses
--
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

---------------------------------------------------------------------------------------

-- USER TUNING (easy knobs)

-- Major faction bonus strength when fighting minors
-- Original DEI used 5.0 / 0.1 
-- we use much gentler values for dynamic campaigns
local MAJOR_WIN_CHANCE = 0.60      -- 60% win chance for major (was 5.0 in DEI)
local MINOR_WIN_CHANCE = 0.45      -- 45% win chance for minor (was 0.1 in DEI)
local MAJOR_LOSS_MOD = 0.85        -- major takes 85% normal losses (was 0.1 in DEI)
local MINOR_LOSS_MOD = 1.15        -- minor takes 115% normal losses (was 5.0 in DEI)

-- Rome vs other major bonus (slight edge, not overwhelming)
local ROME_VS_MAJOR_WIN = 0.55     -- Rome gets 55% vs other majors (was 0.7 in DEI)
local OTHER_VS_ROME_WIN = 0.50     -- Others get 50% vs Rome (was 0.3 in DEI)

-- Player settings
local ENABLE_PLAYER_BIAS = true
local PLAYER_BIAS_STRENGTH = 0.30  -- Bias toward AI when human involved


-- Ppeniding battle, AUTORESOLVER BONUSES

function GetPlayerFactions()
  local player_factions = {};
  local faction_list = scripting.game_interface:model():world():faction_list();
  for i = 0, faction_list:num_items() - 1 do
    local curr_faction = faction_list:item_at(i);
    if (curr_faction:is_human() == true) then
      table.insert(player_factions, curr_faction);
    end
  end
  return player_factions;
end;

function CheckIfFactionIsPlayersAlly(players, faction)
  local l = false
  for i,value in pairs(players) do
    if (l == false) and (value:allied_with(faction)==true) then 
      l = true
    end
  end
  return l
end

function CheckIfPlayerIsNearFaction(players, force)
  local l = false
  local force_general = force:general_character()
  local radius = 20
  for i,value in pairs(players) do
    local player_force_list = value:military_force_list()
    local j = 0
    while (l == false) and (j<player_force_list:num_items()) do
      local player_character = player_force_list:item_at(j):general_character()
      local distance = distance_2D(force_general:logical_position_x(), force_general:logical_position_y(), player_character:logical_position_x(), player_character:logical_position_y())
      l = (distance < radius)
      j = j+1
    end
  end
  return l
end

-- Check if faction is a major power
function IsMajorFaction(faction_name)
  local majors = {
    -- Rome and variants
    ["rom_rome"] = true,
    ["gaul_rome"] = true,
    ["pun_rome"] = true,
    ["emp_antony"] = true,
    ["emp_lepidus"] = true,
    ["emp_octavian"] = true,
    -- Carthage
    ["rom_carthage"] = true,
    ["pun_carthage"] = true,
    ["inv_carthage"] = true,
    -- Hellenistic
    ["rom_seleucid"] = true,
    ["rom_ptolemaics"] = true,
    ["rom_macedon"] = true,
    ["pel_makedon"] = true,
    ["rom_epirus"] = true,
    -- Eastern
    ["rom_parthia"] = true,
    ["emp_parthia"] = true,
    ["rom_pontus"] = true,
    ["rom_baktria"] = true,
    ["rom_armenia"] = true,
    --barbs
    ["inv_boii"] = true,
    ["inv_insubres"] = true,
    ["inv_senones"] = true,
    ["inv_cenomani"] = true,
    -- Other
    ["pel_korkyra"] = true,
  }
  return majors[faction_name] or false
end

-- Check if faction is Rome specifically (for Rome vs Major bonus)
function IsRome(faction_name)
  local rome_factions = {
    ["rom_rome"] = true,
    ["gaul_rome"] = true,
    ["pun_rome"] = true,
    ["emp_antony"] = true,
    ["emp_lepidus"] = true,
    ["emp_octavian"] = true,
  }
  return rome_factions[faction_name] or false
end


local function OnPendingBattle(context)
  Log("pending battle between:"..context:pending_battle():attacker():faction():name().." v "..context:pending_battle():defender():faction():name())
  
  local attacking_faction = context:pending_battle():attacker():faction()
  local defending_faction = context:pending_battle():defender():faction()
  local attacker_name = attacking_faction:name()
  local defender_name = defending_faction:name()
  
  local attacker_is_human = attacking_faction:is_human()
  local defender_is_human = defending_faction:is_human()
  
  -------------------------------------------------------------------------
  -- HUMAN VS AI: Bias toward AI to encourage manual battles
  -------------------------------------------------------------------------
  if attacker_is_human or defender_is_human then
    if ENABLE_PLAYER_BIAS then
      local base = 0.5
      local shift = PLAYER_BIAS_STRENGTH
      
      if attacker_is_human and not defender_is_human then
        -- Human attacking AI
        local a_win = base - shift
        local d_win = base + shift
        scripting.game_interface:modify_next_autoresolve_battle(a_win, d_win, 1.1, 0.9, false)
        Log("Human attacker vs AI defender: biased toward AI")
      elseif not attacker_is_human and defender_is_human then
        -- AI attacking human
        local a_win = base + shift
        local d_win = base - shift
        scripting.game_interface:modify_next_autoresolve_battle(a_win, d_win, 0.9, 1.1, false)
        Log("AI attacker vs human defender: biased toward AI")
      end
    end
    return
  end
  
  -------------------------------------------------------------------------
  -- AI VS AI: Apply balanced major faction bonuses
  -------------------------------------------------------------------------
  local attacker_is_major = IsMajorFaction(attacker_name)
  local defender_is_major = IsMajorFaction(defender_name)
  local attacker_is_rome = IsRome(attacker_name)
  local defender_is_rome = IsRome(defender_name)
  
  -- Major vs Minor
  if attacker_is_major and not defender_is_major then
    Log("Major ("..attacker_name..") attacking minor ("..defender_name..")")
    local player_factions = GetPlayerFactions()
    local ally_involved = CheckIfFactionIsPlayersAlly(player_factions, defending_faction)
    
    if ally_involved == false then
      local player_nearby = CheckIfPlayerIsNearFaction(player_factions, context:pending_battle():defender():military_force())
      if player_nearby == false then
        scripting.game_interface:modify_next_autoresolve_battle(MAJOR_WIN_CHANCE, MINOR_WIN_CHANCE, MAJOR_LOSS_MOD, MINOR_LOSS_MOD, false)
        Log("Applied major attacker bonus: "..tostring(MAJOR_WIN_CHANCE).." vs "..tostring(MINOR_WIN_CHANCE))
      end
    end
    return
  end
  
  -- Minor vs Major
  if not attacker_is_major and defender_is_major then
    Log("Minor ("..attacker_name..") attacking major ("..defender_name..")")
    local player_factions = GetPlayerFactions()
    local ally_involved = CheckIfFactionIsPlayersAlly(player_factions, attacking_faction)
    
    if ally_involved == false then
      local player_nearby = CheckIfPlayerIsNearFaction(player_factions, context:pending_battle():attacker():military_force())
      if player_nearby == false then
        scripting.game_interface:modify_next_autoresolve_battle(MINOR_WIN_CHANCE, MAJOR_WIN_CHANCE, MINOR_LOSS_MOD, MAJOR_LOSS_MOD, false)
        Log("Applied major defender bonus: "..tostring(MINOR_WIN_CHANCE).." vs "..tostring(MAJOR_WIN_CHANCE))
      end
    end
    return
  end
  
  -- Major vs Major (Rome gets slight edge)
  if attacker_is_major and defender_is_major then
    if attacker_is_rome and not defender_is_rome then
      scripting.game_interface:modify_next_autoresolve_battle(ROME_VS_MAJOR_WIN, OTHER_VS_ROME_WIN, 0.95, 1.05, false)
      Log("Rome attacking major: slight Rome bonus")
    elseif defender_is_rome and not attacker_is_rome then
      scripting.game_interface:modify_next_autoresolve_battle(OTHER_VS_ROME_WIN, ROME_VS_MAJOR_WIN, 1.05, 0.95, false)
      Log("Major attacking Rome: slight Rome bonus")
    else
      Log("Major vs Major (non-Rome): no bonus applied")
    end
    return
  end
  
  -- Minor vs Minor: no modification
  Log("Minor vs Minor: no bonus applied")
end

scripting.AddEventCallBack("PendingBattle", OnPendingBattle);
