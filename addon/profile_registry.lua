-- ============================================================
-- profile_registry.lua — Central registry for leveling profiles.
--
-- A profile is a Lua table describing a zone, level range,
-- kill targets, patrol waypoints, quests, and rest thresholds.
--
-- Profiles self-register by calling:
--   GB_Profiles.Register(profileTable)
--
-- The leveling bot loads a profile with:
--   GB_Profiles.Load("Westfall 10-15")
--
-- Profile table format:
-- {
--   name        = "Westfall 10-15",      -- unique display name
--   zone        = "Westfall",            -- zone name (GetZoneText)
--   levelRange  = { 10, 15 },            -- min/max player level
--
--   killTargets = {                      -- mobs to grind
--     { entry = 450, name = "Harvest Golem" },
--     ...
--   },
--
--   -- Optional: patrol path while scanning for mobs.
--   -- List of { x, y } world coordinates.
--   patrolPath  = { { x=…, y=… }, … },
--
--   -- Optional: quests to pick up, complete, and turn in.
--   quests = {
--     {
--       id   = 168,
--       name = "The Forgotten Heirloom",
--       objectives = {
--         { type="kill",    entry=453,       count=10 },
--         { type="collect", itemName="Lost Talisman", count=1 },
--       },
--       acceptNPC = { name="Farmer Saldean", x=…, y=… },  -- nil = already in log
--       turnInNPC = { name="Farmer Saldean", x=…, y=… },
--     },
--   },
--
--   -- Ability rotation: list of abilities to use in combat in priority order.
--   -- Each entry: { name=spellName, minMana=0, minRange=0, maxRange=30 }
--   rotation = {
--     { name="Fireball",   minMana=55,  minRange=5, maxRange=35 },
--     { name="Fire Blast", minMana=40,  minRange=0, maxRange=20 },
--   },
--
--   -- HP/mana rest thresholds (%)
--   restHP   = 45,   resumeHP = 80,
--   restMP   = 20,   resumeMP = 70,
-- }
-- ============================================================

GB_Profiles = {}

local registry = {}          -- { [name] = profileTable }
local activeProfile = nil    -- currently loaded profile

-- ---- Register a profile ------------------------------------
function GB_Profiles.Register(profile)
    if not profile or not profile.name then
        GB_Utils.Print("[Profiles] Cannot register profile without a name!")
        return
    end
    registry[profile.name] = profile
    GB_Utils.Debug("[Profiles] Registered: " .. profile.name)
end

-- ---- Load (activate) a profile by name ---------------------
function GB_Profiles.Load(name)
    local p = registry[name]
    if not p then
        GB_Utils.Print("[Profiles] Unknown profile: " .. tostring(name))
        GB_Utils.Print("[Profiles] Available: " .. GB_Profiles.ListNames())
        return false
    end
    activeProfile = p
    GB_Utils.Print("[Profiles] Loaded profile: " .. p.name
        .. " (lv " .. (p.levelRange and (p.levelRange[1].."-"..p.levelRange[2]) or "?") .. ")")
    return true
end

-- ---- Get the active profile --------------------------------
function GB_Profiles.Active()
    return activeProfile
end

-- ---- List all registered profile names (sorted) -----------
function GB_Profiles.ListNames()
    local names = {}
    for k in pairs(registry) do table.insert(names, k) end
    table.sort(names)
    return table.concat(names, ", ")
end

-- ---- Validate a profile table (returns error string or nil) -
function GB_Profiles.Validate(p)
    if type(p) ~= "table"              then return "not a table"           end
    if type(p.name) ~= "string"        then return "missing name"          end
    if type(p.killTargets) ~= "table"  then return "missing killTargets"   end
    if #p.killTargets == 0             then return "killTargets is empty"   end
    return nil   -- valid
end
