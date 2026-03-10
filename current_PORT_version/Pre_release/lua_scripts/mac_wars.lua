
---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
-- 
-- Created by Dresden
-- Last Updated: July 26

---------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------
-- Disabled by submod 
-- Make the script a module one
module(..., package.seeall);

-- Used to have the object library able to see the variables in this new environment
_G.main_env = getfenv(1);

-- Load libraries
scripting = require "lua_scripts.EpisodicScripting";  
require "DeI_utility_functions";

--===============================================================
-- Spawns
--===============================================================
function Turn()
	return scripting.game_interface:model():turn_number()
end




--scripting.AddEventCallBack("FactionTurnStart", Macedon_Army_Spawn);
--scripting.AddEventCallBack("FactionTurnStart", Roman_Army_Spawn);
