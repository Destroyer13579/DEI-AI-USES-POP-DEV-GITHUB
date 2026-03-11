# DEI AI Overhaul Submod — Code Reference Guide

## Overview

This is a submod for **Divide et Impera** (Total War: Rome 2). It overhauls AI behavior across economy, diplomacy, auto-resolve battles, population mechanics, public order, and army supply logistics. The mod is authored primarily by **Litharion**, with contributions from **Magnar**, **Causeless**, **Dresden**, and **Destroyer** (with Claude AI assistance on the coalition system).

All Lua scripts live under `current_PORT_version/Pre_release/lua_scripts/` and use the Rome 2 scripting API via `EpisodicScripting` and the `cm` (campaign manager) global.

---

## Script-by-Script Breakdown

### 1. `gc_scripts.lua` — Grand Campaign Scripts

**Purpose:** Main campaign event orchestrator. Sets up listeners for faction turn events and handles historical flavor.

**Key systems:**
- **Rome/Carthage/Seleucid escalation** — Originally scripted wars between these factions. Currently **disabled** (`DISABLE_SCRIPTED_WARS = true`). The army spawn functions (`RomeArmyScript`, `CarthageArmyScript`, `SeleucidArmyScript`) are commented out in the listeners.
- **Historical city intros** — When a player selects certain famous settlements (Rome, Carthage, Athens, Sparta, Alexandria, etc.), a one-time contextual advice thread fires. Tracked in `region_intros_played` table.
- **Upgrade advisor** — Shows a reform notification when a human player selects a character from Roman, Hellenistic, Celtiberian, or Daco-Thracian cultures. Fires once per campaign.
- **Save/Load** — Persists all state variables (escalation levels, army flags, region intro states) via `save_named_value`/`load_named_value`.

**Event callbacks:**
| Event | Handler |
|---|---|
| `WorldCreated` | `OnWorldCreatedCampaign` — registers all listeners |
| `SettlementSelected` | `OnSettlementSelected` — historical city intros |
| `CharacterSelected` | `Upgrades` — reform advisor |
| `SavingGame` / `LoadingGame` | `Save_Values` / `Load_Values` |

---

### 2. `gc_first_turn_setup.lua` — First Turn Setup

**Purpose:** Runs once on `NewCampaignStarted`. Configures starting diplomatic stances and grants bonus units to AI factions based on difficulty and which factions the player chose.

**Key systems:**
- **Diplomatic stance initialization** — Sets `BITTER_ENEMIES` between historical rivals (Cyrenaica↔Ptolemies, Seleucids↔Ptolemies, Epirus↔Rome, Rome↔Syracuse, Maurya↔Bactria). Sets `FRIENDLY` between Carthage and its North African neighbors (Gaetuli, Garamantia, Nasamones). Stances are only forced when neither faction is human.
- **Difficulty-scaled army grants** — Four setup functions grant extra units to AI factions when the player picks their historical rival:
  - `Pyrrhus_Setup` — Grants Epirus extra units at Brundisium when player is Rome or Syracuse. Scales from 3 base units (easy) up to 7 (legendary).
  - `RomeStart_Setup` — Grants Rome extra units at Cosentia/Beneventum when player is NOT an enemy of Rome. Scales on VH/Legendary.
  - `EgyptStart_Setup` — Grants Egypt extra units at Jerusalem when player is Seleucid.
  - `SeleucidStart_Setup` — Grants Seleucid extra units at Antioch when player is Egypt.
- **Multiplayer handling** — In MP, if both rival factions are human, only base units are granted (no difficulty scaling).

**Difficulty values:** `0` = Normal, `-1` = Hard, `-2` = Very Hard, `-3` = Legendary. In MP, forced to `-1`.

---

### 3. `money.lua` — AI Economy Balancing

**Purpose:** Replaces direct AI money injections with effect-bundle-based tax multipliers and imperium-scaled bonuses. Logs everything to `Pop_script_log.txt`.

**Key systems:**
- **Fair tax boost** (`AdjustAIEconomy`) — On every AI faction's turn start, removes and re-applies `AI_Fair_Tax_Boost` bundle. This gives AI factions a percentage-based tax income boost rather than flat cash.
- **Imperium-based bonuses** (`AdjustAIImperiumBonuses`) — Removes all old imperium bundles, then applies a single tiered bundle based on the faction's imperium level (1–6). Levels 1–4 use original `AI_Imperium_Bonus_X` bundles; levels 5–6 use new `AI_Imperium_Fair_Boost_X` bundles.
- **End-of-turn treasury logging** (`LogAITreasuryEndTurn`) — Records treasury delta between turn start and end for each AI faction, proving the actual economic impact of the applied bundles.

**Event callbacks:**
| Event | Handler |
|---|---|
| `FactionTurnStart` | `AdjustAIEconomy`, `AdjustAIImperiumBonuses` |
| `FactionTurnEnd` | `LogAITreasuryEndTurn` |

---

### 4. `auto_resolve_bonus.lua` — Auto-Resolve Battle Modifiers

**Purpose:** Modifies auto-resolve battle outcomes to give major factions an edge over minors, Rome a slight edge over other majors, and bias results against the human player (encouraging manual battles).

**Key tuning values:**
| Parameter | Value | Description |
|---|---|---|
| `MAJOR_WIN_CHANCE` | 0.60 | Major faction win chance vs minor |
| `MINOR_WIN_CHANCE` | 0.45 | Minor faction win chance vs major |
| `ROME_VS_MAJOR_WIN` | 0.55 | Rome's win chance vs other majors |
| `PLAYER_BIAS_STRENGTH` | 0.30 | How much auto-resolve favors AI when human is involved |

**Logic flow (OnPendingBattle):**
1. If human is involved → apply player bias (AI gets +0.30 win chance shift)
2. If AI Major vs AI Minor → major gets 60/45 win/loss advantage (skipped if player's ally or player army is nearby)
3. If AI Major vs AI Major → Rome gets slight 55/50 edge
4. Minor vs Minor → no modification

**Safety checks:** Won't apply major bonuses if the minor faction is the player's ally or if a player army is within 20 units distance.

---

### 5. `PublicOrder.lua` — Public Order & Faction Leader System

**Purpose:** Two systems — army-based public order penalties for the player, and faction leader personality effects.

**System A: Army Public Order Penalties (Player Only)**
- When a human player's army is in a province, it creates a public order penalty based on army size.
- The penalty scales with:
  - Number of regions the player owns in that province (fewer = harsher)
  - Whether the faction's state religion matches the region's majority religion (mismatch = harsher)
- Multipliers range from 1.2x to 1.5x, with a cap of 15–25 depending on conditions.
- Applied via numbered effect bundles (`public_1_order` through `public_30_order`).
- Navies and armies that just arrived (0 turns in own regions) also get penalized.
- A special skill check: `general_rightful_sovereign_2_patron_of_the_military` grants a garrison repression bonus.

**System B: Faction Leader Administration**
- On faction turn start, checks the faction leader's personality trait (from the Greco-Roman humors system).
- Maps traits to 6 categories: Beloved, Feared, Selfish, Disdained, Engaged, Reserved.
- Each applies a different faction-wide effect bundle (e.g., `dei_faction_leader_beloved`).
- Beloved, Feared, and Engaged leaders also remove `political_instability`.
- When a faction leader dies, `political_instability` is applied for 6 turns.
- The faction leader's army gets a `your_faction_leader` effect bundle.

**Event callbacks:**
| Event | Handler |
|---|---|
| `CharacterTurnEnd` | `PublicOrderFleets`, `PublicOrderApply` |
| `CharacterSelected` | `PublicOrderDisplay` |
| `CharacterLeavesGarrison` | `PublicOrderRemove` |
| `CharacterEntersGarrison` | `PublicOrderApply` |
| `CharacterTurnStart` | `PublicOrderApply` |
| `FactionTurnStart` | `FactionLeaderCapital` |
| `CharacterBecomesFactionLeader` | `FactionLeaderDies` |

---

### 6. `smart_diplomacy.lua` — Distance War Blocking, Cascading Peace & Coalitions

**Purpose:** Three interconnected AI diplomacy systems. This is the most complex script in the mod.

**System A: Distance War Blocking**
- Prevents AI factions from declaring war on the human player if their closest settlements are more than 100 units apart (`WAR_DISTANCE_THRESHOLD`).
- Uses `force_diplomacy` to block/enable war declarations.
- Recalculated every turn per faction.
- Coalition war overrides can bypass the distance block.

**System B: Cascading Peace**
- When an AI overlord makes peace, it cascades down to its client states/vassals.
- If `CASCADE_FROM_ALLIES` is true (currently false), it also cascades from military/defensive allies.
- Uses `cm:force_make_peace()` to enforce peace.

**System C: Coalition System**
- AI factions form coalitions against rapidly expanding factions (including the player).
- **Threat scoring:** Each faction accumulates threat based on:
  - Growth rate relative to world average (weighted by `THREAT_GROWTH_WEIGHT = 15`)
  - Territory size relative to world average (weighted by `THREAT_SIZE_WEIGHT = 10`)
  - Threat decays by 15% per turn (`THREAT_DECAY`)
- **Thresholds:** Mild threat at score 50, Severe at 80.
- **Formation rules:**
  - Minimum 7 regions to be a target (`COALITION_MIN_REGIONS`)
  - Not before turn 10 (`COALITION_MIN_TURN`)
  - Members must be neighbors (or extended neighbors for severe threats)
  - Members can't be at war with each other
  - Members must be geographically close to each other (within 2x distance threshold)
  - Members can't be allied/vassal of the target
  - Max 1 coalition vs player, max 2 AI-vs-AI coalitions
  - 10-turn cooldown after dissolution
- **War mechanics:**
  - All coalition members simultaneously declare war on the target
  - Peace is locked for 5 turns (AI target) or 11 turns (player target)
  - Coalition dissolves when half or more members achieve peace or are destroyed
- **UI notifications:** Custom message events (950, 951, 952) with dynamic text injection showing coalition members, progress toward dissolution, and peace lock timers.
- **Save/Load:** Full serialization of snapshots, cooldowns, threat scores, and active coalitions.

**Event callbacks:**
| Event | Handler |
|---|---|
| `WorldCreated` | `OnNewCampaign` |
| `LoadingGame` | `OnLoad` |
| `SavingGame` | `OnSave` |
| `FactionTurnStart` | `OnFactionTurn` — runs distance check, coalition evaluation, cascading peace, UI notifications |

---

### 7. `population.lua` — Population System (People of Rome 2 / p++)

**Purpose:** The largest script (~11,700 lines). Implements a full population simulation with 4 social classes per region, immigration, recruitment costs, economic effects, and a UI overlay. Also contains the **AI diplomacy peace-seeking** system.

**Population classes per region:**
1. Noble (upper class)
2. Middle class (citizens)
3. Lower class (poor)
4. Foreign class

**Key systems:**
- **Region population growth** (`RegionPopGrowth`) — Each turn, adjusts all 4 population classes based on modifiers from external config tables (`population_modifiers`, `population_tables`). Growth is bounded by `min_pop_size` and `max_pop_size`.
- **Immigration** (`FactionImmigration`) — Population flows between regions within a faction based on factors from `population_immigration` config.
- **Region occupation effects** (`SetRegionOccupied`) — When a region is captured:
  - If looted + same culture: all classes quartered, foreigners = sum/4
  - If looted + different culture: foreigners = sum/2, citizens reset to 1
  - If occupied + same culture: citizens halved, foreigners = sum of all
  - If occupied + different culture: foreigners = total sum, citizens reset to 10/20/40
- **Foreign population ratio** — Faction-wide public order bundles based on the ratio of foreign to total population (thresholds at 50%, 60%, 70%, 80%, 90%).
- **Recruitment population costs** — Recruiting units deducts from the appropriate population class. Tracked via `recruitmentOrders` and `army_size_cqi` tables.
- **UI overlay** — Custom tooltips showing population breakdown per region, class names, growth projections.
- **Campaign support** — Handles Grand Campaign, Caesar in Gaul, Wrath of Sparta, Hannibal at the Gates, and Rise of the Republic.

**AI Diplomacy Peace-Seeking (embedded in population.lua):**
- Factions in `AI_DIPLOMACY_FACTIONS` table (~150+ factions) can seek peace.
- Peace chance increases when:
  - Faction is in 4+ wars (`AI_DIPLOMACY_WAR_THRESHOLD`)
  - Treasury is below 5,000 (`AI_DIPLOMACY_TREASURY_DESPERATE`)
  - Army losses cause war weariness (10 per lost army, caps at 50)
- Peace chance decreases when:
  - Faction has war momentum (captured regions from the enemy)
  - Treasury is above 50,000 (`AI_DIPLOMACY_TREASURY_RICH`)
- After peace, war declarations are disabled for 7 turns (`AI_PEACE_PROTECTION_DURATION`).
- War momentum tracks region captures per war, decays by 0.2 per turn.

**Event callbacks:**
| Event | Handler |
|---|---|
| `WorldCreated` | `OnWorldCreatedPop` |
| `SavingGame` / `LoadingGame` | `OnSavingGamePop` / `OnLoadingGamePop` |
| `RegionTurnStart` | `OnRegionTurnStartPop` — population growth |
| `CharacterTurnStart` | `OnCharacterTurnStartPop` — enemy presence flags, region bundles |
| `CharacterLootedSettlement` | `OnCharacterLootedSettlementPop` |
| `GarrisonOccupiedEvent` | `OnGarrisonOccupiedEventPop` — triggers occupation logic |
| `FactionTurnStart` | `OnFactionTurnStartPop` — foreign ratio bundles, region ownership tracking |
| `CharacterCompletedBattle` | `OnCharacterCompletedBattlePop` — battle flag |

---

### 8. `supply_system.lua` + `supply_system_functions.lua` — Army Supply System

**Purpose:** A comprehensive logistics system where armies must be supplied from nearby friendly regions, supply depots, or fleets. Unsupplied armies suffer attrition.

**Culture-based supply paths:**
- **Civilized** (`SupplyCIVstart`) — Roman, Hellenistic, Eastern factions. Most complex supply chain.
- **Barbarian** (`SupplyBARstart`) — Celtic, Germanic, etc. Simpler supply model.
- **Nomadic** (`SupplyNOMADICstart`) — Steppe factions. Most self-sufficient.

**Supply resolution order (Civilized example):**
1. Home region (capital) → automatic supply
2. Owned region with open market (same religion, good public order, near settlement)
3. Owned region with forced local supply (near settlement)
4. Owned region with local supply line (no enemy blocking)
5. Seaport supply (trade port, no enemy fleet nearby)
6. Fleet-to-army supply (supply ships within range)
7. Supply line from depot (1–3 regions away, requires logistics buildings)
8. Allied supply (in allied territory, not under siege)
9. Seasonal attrition checks (winter in Alps, summer in deserts)
10. Foraging (degrades region supplies, damages agriculture buildings)
11. No supply → attrition

**Supply line mechanics:**
- Supply lines extend up to 3 regions from a logistics depot.
- Each tier requires progressively better depot buildings (`Tier_I_Depot_List`, `Tier_II_Depot_List`, `Tier_III_Depot_List`).
- Lines are blocked by enemy armies within a radius.
- Alpine passes close in winter; deserts cause attrition in summer (unless faction is desert-native).

**Naval supply:**
- Fleets have a turns-at-sea counter (up to 8 turns before attrition).
- Transport fleets suffer sea sickness unless a supply fleet is nearby.
- Barbarian transports get immunity near friendly ports.
- Baggage trains provide ammo bonuses and extend supply duration.

**Global food costs:**
- Each army's supply draws from a global food pool.
- Effect bundles (`Faction_Army_Supply_X`) represent the faction-wide logistics overhead.

**Key functions in `supply_system_functions.lua`:**
| Function | Purpose |
|---|---|
| `SupplyFactionisBAR/CIV/NOMADIC` | Culture classification |
| `SupplyCharisTransportFleet/Admiral` | Character type detection |
| `SupplyArmySize` | Calculates supply points (elephants +4, cavalry +1) |
| `BuildSupplyLines` | Pathfinds through up to 3 adjacent regions for depot connections |
| `SupplyForaging` | Degrades region supplies, applies tiered foraging bundles |
| `SupplyLineBlocked` | Checks if enemy armies are blocking a supply route |
| `AgricultureBuildingDamage` | Damages farm buildings when foraging in devastated regions |

---

### 9. `mac_wars.lua` — Macedonian Wars (Disabled)

**Purpose:** Originally spawned scripted armies for Macedon and Rome. Currently **disabled** — all spawn callbacks are commented out. The file is essentially a stub.

---

## Shared Patterns

**Module system:** Every script uses `module(..., package.seeall)` and `_G.main_env = getfenv(1)` to create isolated module environments while maintaining access to globals.

**Event system:** All scripts register callbacks via `scripting.AddEventCallBack(eventName, handler)` or `cm:add_listener()`. Common events:
- `WorldCreated` — initialization
- `FactionTurnStart` / `FactionTurnEnd` — per-faction logic
- `CharacterTurnStart` / `CharacterTurnEnd` — per-character logic
- `SavingGame` / `LoadingGame` — persistence

**Logging:** Multiple log files:
- `Pop_script_log.txt` — population and money systems
- `Smart_Diplomacy_Log.txt` — diplomacy and coalitions
- `PoR2_Growth_Log.txt` — detailed population growth
- `Debug_script_log.txt` — debug output

**Effect bundles:** The primary mechanism for applying gameplay effects. Applied/removed via `apply_effect_bundle` (faction-wide) or `apply_effect_bundle_to_characters_force` (army-specific).

---

## External Dependencies (not in this repo)

These are referenced via `require` but live in the base DEI mod:
- `DeI_utility_functions` — shared helpers (`contains`, `char_is_general_with_army`, `char_is_general_with_navy`, `distance_2D`, `getTurn`, etc.)
- `script._lib.manpower.*` — population config tables (modifiers, tables, UI, economics, immigration, units)
- `script._lib.supply_system.supply_system_values` — supply system config values
- `lua_scripts.supply_system_script_header` — supply system constants and table definitions
- `lua_scripts.EpisodicScripting` — Rome 2's scripting bridge

---

## DB Tables (TSV files)

Located under `current_PORT_version/Pre_release/db/`:
- `cai_personalities_*` — AI personality definitions and budget allocations
- `cai_variables_tables` — AI behavior tuning variables
- `campaign_ai_*` — AI manager behavior and personality junction tables
- `cdir_unit_balances_tables` — unit balance overrides
- `effect_bundles_*` — effect bundle definitions (faction traits, politics)
- `message_events_*` — custom message event definitions (for coalition UI, etc.)

---

## Performance Optimizations Applied

### Optimization #1: Hash Set Conversion (O(n) → O(1) lookups)

**Problem:** The `contains()` function performs linear O(n) scans on arrays. Many of these arrays are static (region lists, faction lists) that never change after load. In hot paths that run every faction turn for every army, this adds up significantly.

**Solution:** Introduced `to_set()` / `set_contains()` utility functions that convert arrays to hash sets `{[value]=true}` with caching by table identity. Repeated calls to `to_set()` on the same source array return the cached set instantly.

**Files modified:**

**`supply_system_functions.lua`:**
- Added `to_set()`, `set_contains()`, and `_set_cache` at top of file
- `SupplyFactionisNOMADIC()` — `nomadic_factions_table` → set lookup
- `Is_Desert_Faction()` — `desert_factions_list_table` → set lookup
- `Is_Winter_In_Alps()` — `alpine_regions_table` → set lookup
- `Desert_Attrition()` — `desert_regions_table` → set lookup
- `Ally_diplomatic_treaty_types` — added pre-computed `Ally_diplomatic_treaty_types_set` hash table
- `SupplyGetFactionTreaties()` — `AlliedFactionKeys` now returned as a hash set `{[faction_key]=true}` instead of an array. `EnemyFactionKeys` stays as an array (iterated in `SupplyLineBlocked`/`SupplyNearEnemyFleet`)
- `BuildSupplyLines()` — `adjacent_list_1/2/3` converted from arrays to hash sets. Uses `list[name] = true` for insert and `list[name]` for membership check. Iteration changed from `for i = 1, #list` to `for name, _ in pairs(list)`
- `AgricultureBuildingDamage()` — `Agriculture_Building_List` → set lookup via `to_set(list)`
- `CivAlliedSupply()` — direct hash lookup on `AlliedFactionKeys` set

**`supply_system.lua`:**
- All `contains(region_name, global_supply_variables.winter_regions_table)` → `set_contains(to_set(...))`
- All `contains(region_name, global_supply_variables.alpine_regions_table)` → `set_contains(to_set(...))`
- All `contains(region_name, global_supply_variables.summer_regions_table)` → `set_contains(to_set(...))`
- All `contains(region_name, global_supply_variables.desert_regions_table)` → `set_contains(to_set(...))`
- `contains(faction_name, global_supply_variables.winter_factions_list_table)` → `set_contains(to_set(...))`
- UI fertility checks: `low_fertile_regions_table`, `normal_regions_table`, `fertile_regions_table`, `very_fertile_regions_table` → `set_contains(to_set(...))`
- All `AlliedFactionKeys` checks → direct hash lookup (since it's now a set)

**`population.lua`:**
- `Contains()` function rewritten to use internal `pop_to_set()` with its own `_pop_set_cache`. All callers (`FactionImmigration`, `regionHasPort`) automatically benefit from O(1) lookups without code changes at call sites.


### Optimization #2: Hoist Building/Tech Iteration Out of Class Loop in `RegionPopGrowth`

**Problem:** `RegionPopGrowth()` runs a `for i = 1, 4` loop (one per social class). Inside that loop, it iterates all building slots and all researched technologies to compute growth bonuses. Since the buildings and techs are the same for all 4 classes, this means the slot/tech iteration runs 4x unnecessarily — the only difference is which index `[i]` is read from the bonus table.

**Solution:** Hoist both iterations (tech table + building slots) above the class loop. Walk them once, accumulating per-class bonuses into `hoisted_tech_bonus[1..4]` and `hoisted_building_bonus[1..4]`. Inside the class loop, just add the pre-computed values.

**Impact:** For a region with 8 building slots and 20 researched techs, this eliminates ~84 redundant iterations per region per turn. Across 100+ regions, that's significant.

**File:** `population.lua` — `RegionPopGrowth()` function

### Optimization #3: Bundle-Change Tracking in `money.lua`

**Problem:** `AdjustAIImperiumBonuses()` removes 13 effect bundles and applies 1 every turn for every AI faction, even when the imperium level hasn't changed (which is most turns). `AdjustAIEconomy()` removes and re-applies the same permanent tax bundle every turn. Each `remove_effect_bundle` / `apply_effect_bundle` is a game API call with overhead.

**Solution:** 
- Track `ai_last_imperium_bundle[factionName]` — only swap bundles when the desired bundle differs from what's already applied. On first run after load, do the full 13-bundle cleanup (handles legacy/stale bundles), then only remove the single old bundle on subsequent changes.
- Track `ai_tax_bundle_applied[factionName]` — the tax bundle is permanent (duration 0), so apply it once and skip on subsequent turns.

**Impact:** Reduces API calls from ~14 per AI faction per turn to 0 in the common case (no imperium change). On first run after load, still does the full cleanup for safety.

**File:** `money.lua` — `AdjustAIEconomy()` and `AdjustAIImperiumBonuses()`


### Optimization #4: Release-Mode Logging (No-Op Overrides)

**Problem:** Even when logging flags (`isLogAllowed`, `isLogPopAllowed`) are `false`, every `LogSupply("func_name", "message: "..variable)` call still evaluates its string concatenation arguments before calling the function. With 211 `LogSupply` calls in the supply system (running per-army per-faction per-turn), 42 `LogPop` calls in `RegionPopGrowth` (per-region per-turn), and 260 `PopLog` calls, this is significant wasted work.

**Solution:** When logging is disabled, replace the log functions with empty no-ops (`function() end`) immediately after their definition. This means Lua resolves the function call to an empty body — while string concat at call sites still technically runs, the function dispatch and all internal logic (file I/O, formatting, timestamps) is completely eliminated.

**Files modified:**

- `supply_system_functions.lua` — Added `SUPPLY_LOG_ENABLED = false` flag. When false, shadows the global `LogSupply` with `function() end` after the require.
- `supply_system.lua` — Same pattern: after `require "lua_scripts.supply_system_script_header"`, overrides `LogSupply` with a no-op when `SUPPLY_LOG_ENABLED = false`.
- `population.lua` — After defining `LogPop`, `PopLog`, `Debug`, and `Log`, each is replaced with a no-op when its respective flag is false. Uses pre-declared `_LogPop_noop` / `_PopLog_noop` / `_Debug_noop` locals.
- `money.lua` — Added `MONEY_LOG_ENABLED = false` with early return in `pop_log()`.

**To re-enable logging:** Set the relevant flag to `true`:
- `SUPPLY_LOG_ENABLED` in `supply_system_functions.lua` and `supply_system.lua`
- `isLogAllowed` / `isLogPopAllowed` in `population.lua`
- `MONEY_LOG_ENABLED` in `money.lua`


### Optimization #5: Per-Faction Tech Bonus Cache in `population.lua`

**Problem:** `RegionPopGrowth()` is called via `RegionTurnStart` for every region. Inside it, the tech iteration (`has_technology()` for every tech in `tech_pop_growth_own_culture_table` / `tech_pop_growth_foreign_culture_table`) produces identical results for all regions owned by the same faction within the same turn. For a faction with 20 regions and 30 techs in each table, that's ~1200 redundant `has_technology()` API calls per turn.

**Solution:** Added `GetFactionTechBonuses(faction)` which computes and caches `{own={0,0,0,0}, foreign={0,0,0,0}}` per faction name. Cache is invalidated each turn via turn number comparison. `RegionPopGrowth` now reads from the cache instead of iterating techs.

**Impact:** Reduces `has_technology()` calls from O(regions × techs) to O(techs) per faction per turn.

### Optimization #6: Province Capital Helper Function

**Problem:** The 13-call `building_superchain_exists()` check for province capitals is copy-pasted in 3 places: `RegionPopGrowth`, `FactionImmigration`, and `UIRegionPopGrowth`. Each is 13 API calls.

**Solution:** Extracted to `IsProvinceCapital(region)` which iterates a static `_province_capital_superchains` table and short-circuits on first match. All 3 call sites now use the helper. This is primarily a maintainability win (single source of truth), with a minor perf benefit from short-circuit evaluation (average case hits on the first few checks).

### Optimization #7: Foreigner Bundle Tracking in `OnFactionTurnStartPop`

**Problem:** Every turn, for every faction, `OnFactionTurnStartPop` removes 5 foreigner bundles and applies 1 based on the foreign population ratio. The ratio rarely changes between turns, so most of this is wasted API calls.

**Solution:** Added `_last_foreigner_bundle[factionName]` tracking. Only swaps bundles when the desired bundle differs from what's already applied. On first run after load, does the full 5-bundle cleanup for safety.

**File:** `population.lua`
