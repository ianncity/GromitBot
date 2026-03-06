-- ============================================================
-- leveling.lua — Leveling bot state machine
-- ============================================================
--
-- States:
--   IDLE         → not running
--   REST         → sitting and eating/drinking to recover HP/mana
--   PATROL       → walking patrol path waypoints between mob scans
--   SCAN_MOB     → searching for a kill-list mob in range
--   APPROACH     → moving toward target mob before pulling
--   PULL         → initiating combat (move into range + attack)
--   COMBAT       → in combat: execute ability rotation
--   LOOT_MOB     → looting fresh corpse after kill
--   CHECK_QUEST  → evaluate quest log objectives after a kill/collect
--   QUEST_TRAVEL → navigating to a quest turn-in or accept NPC
--   TURN_IN      → interacting with NPC to turn in a quest
--   ACCEPT_QUEST → interacting with NPC to accept new quests
--   CHECK_MAIL   → bags full, delegate to GB_Inventory
--
-- Requires DLL exports (same pattern as herbalism.lua):
--   GB_FindNearestMob(entryList)
--     → guidLo, x, y, z, entry, dist, name
--   GB_GetPlayerPos() → x, y, z
--   GB_GetPlayerHealth() → hp, maxhp
--   GB_GetPlayerMana()  → mana, maxmana
--   GB_GetPlayerLevel() → level
-- ============================================================

GB_Leveling = {}

local STATE = {
    IDLE         = "IDLE",
    REST         = "REST",
    PATROL       = "PATROL",
    SCAN_MOB     = "SCAN_MOB",
    APPROACH     = "APPROACH",
    PULL         = "PULL",
    COMBAT       = "COMBAT",
    LOOT_MOB     = "LOOT_MOB",
    CHECK_QUEST  = "CHECK_QUEST",
    QUEST_TRAVEL = "QUEST_TRAVEL",
    TURN_IN      = "TURN_IN",
    ACCEPT_QUEST = "ACCEPT_QUEST",
    CHECK_MAIL   = "CHECK_MAIL",
}

local state        = STATE.IDLE
local stateTime    = 0

-- Current target mob
local targetMob    = nil   -- { guid, x, y, z, entry, name }
local targetDead   = false
local lootAttempts = 0

-- Patrol
local patrolIdx    = 1

-- Quest travel
local questTravelNPC = nil  -- NPC we are navigating toward
local questTravelIdx = 0    -- waypoint index within straight-line path
local questTravelWPs = {}
local questTravelMode = nil  -- "turnin" | "accept"

-- Combat
local lastAbilityTime = 0
local pullTimeout     = 8    -- s — give up pull if nothing happens
local combatTimeout   = 30   -- s — emergency break out of stuck combat
local lootedCorpses   = {}   -- guid set to avoid reloot

-- NPC interaction
local npcInteractSent = false
local npcInteractTime = 0

-- Movement
local PULL_RANGE    = 25.0   -- yards — stop and attack from here if ranged
local MELEE_RANGE   =  3.5   -- yards — considered in melee
local REACH_MOB     =  4.0   -- yards — close enough to loot / interact
local REACH_WP      =  3.0
local MOVE_SPEED    =  7.0   -- yards/s

-- Gaussian helpers
local function GR(m, s) return GB_Utils.GaussRand(m, s) end
local function GI(lo, hi) return GB_Utils.GaussInterval(lo, hi) end

-- ---- Forward declaration so helpers can call SetState ------
local SetState

-- ===========================================================
-- State helpers
-- ===========================================================

SetState = function(s)
    state     = s
    stateTime = GetTime()
    GB_Utils.Debug("[Leveling] → " .. s)
end

-- ---- Player stats ------------------------------------------
local function PlayerHP()
    if GB_GetPlayerHealth then
        local hp, max = GB_GetPlayerHealth()
        if max and max > 0 then return hp / max * 100 end
    end
    local hp  = UnitHealth("player")    or 1
    local max = UnitHealthMax("player") or 1
    return hp / max * 100
end

local function PlayerMP()
    if GB_GetPlayerMana then
        local mp, max = GB_GetPlayerMana()
        if max and max > 0 then return mp / max * 100 end
    end
    local mp  = UnitMana("player")    or 100
    local max = UnitManaMax("player") or 100
    if max == 0 then return 100 end
    return mp / max * 100
end

local function PlayerLevel()
    if GB_GetPlayerLevel then return GB_GetPlayerLevel() end
    return UnitLevel("player") or 1
end

-- ---- Rest threshold check ----------------------------------
local function NeedsRest(profile)
    local hp = PlayerHP()
    local mp = PlayerMP()
    local restHP = (profile and profile.restHP)  or 45
    local restMP = (profile and profile.restMP)  or 20
    -- Only rest for mana if player has a mana bar
    local hasMana = (UnitManaMax("player") or 0) > 0
    return hp < restHP or (hasMana and mp < restMP)
end

local function RestComplete(profile)
    local hp = PlayerHP()
    local mp = PlayerMP()
    local rHP = (profile and profile.resumeHP) or 80
    local rMP = (profile and profile.resumeMP) or 70
    local hasMana = (UnitManaMax("player") or 0) > 0
    if hp < rHP then return false end
    if hasMana and mp < rMP then return false end
    return true
end

-- ---- Build straight-line waypoints -------------------------
local function BuildPath(sx, sy, ex, ey)
    local path = {}
    local dx, dy = ex - sx, ey - sy
    local dist   = math.sqrt(dx * dx + dy * dy)
    local steps  = math.max(1, math.floor(dist / 3))
    for i = 1, steps do
        local t = i / steps
        table.insert(path, { x = sx + dx * t, y = sy + dy * t })
    end
    return path
end

-- ---- Step toward a world-coordinate point ------------------
-- Returns true if we have arrived within REACH_WP yards.
local function StepToward(tx, ty)
    local px, py, pz = 0, 0, 0
    if GB_GetPlayerPos then px, py, pz = GB_GetPlayerPos() end
    local dx   = tx - px
    local dy   = ty - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= REACH_WP then return true end

    if MoveToPosition then
        MoveToPosition(tx, ty, pz)
    else
        MoveForwardStart()
    end
    return false
end

-- ---- Stop all movement -------------------------------------
local function StopMoving()
    if MoveToPosition then MoveToPosition(0, 0, 0, 0) end
    MoveForwardStop()
end

-- ============================================================
-- Combat / ability helpers
-- ============================================================

-- ---- Check if the player is currently in combat ----------
local function InCombat()
    return UnitAffectingCombat and UnitAffectingCombat("player")
end

-- ---- Target the mob by GUID and begin auto-attack ---------
local function PullMob(mob)
    if SuperWoW_TargetUnit then
        SuperWoW_TargetUnit(mob.guid)
    else
        -- Fallback: target by name
        TargetByName(mob.name or "")
    end
    -- Small reaction delay before actually attacking
    local delay = math.max(0.2, math.min(1.0, GR(0.45, 0.15)))
    GB_Utils.After(delay, function()
        AttackTarget()
    end)
end

-- ---- Execute the profile's rotation once ------------------
-- Returns true if an ability was used this tick.
local function ExecuteRotation(profile)
    if not profile or not profile.rotation then return false end
    local now = GetTime()
    -- Don't spam abilities — Gaussian cast rhythm
    local minGap = GR(0.6, 0.15)
    if now - lastAbilityTime < minGap then return false end

    local mana = PlayerMP()
    for _, ab in ipairs(profile.rotation) do
        local minMana = ab.minMana or 0
        local pct     = (UnitManaMax("player") or 100) > 0
                        and (minMana / (UnitManaMax("player") or 100) * 100) or 0

        if mana >= pct or UnitManaMax("player") == 0 then
            -- (Simple range check via target distance — full impl needs DLL)
            local ok, err = pcall(CastSpellByName, ab.name)
            if ok then
                lastAbilityTime = now
                GB_Utils.Debug("[Combat] Cast: " .. ab.name)
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- Quest helpers
-- ============================================================

-- ---- Return profile quests that are in our log and complete -
local function CompletedQuests(profile)
    if not profile or not profile.quests then return {} end
    local done = {}
    local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for qi = 1, n do
        local title, _, _, complete = GetQuestLogTitle(qi)
        if title and complete then
            for _, pq in ipairs(profile.quests) do
                if pq.name and pq.name == title then
                    table.insert(done, pq)
                end
            end
        end
    end
    return done
end

-- ---- Return the first profile quest not yet in our log ----
local function NextQuestToAccept(profile)
    if not profile or not profile.quests then return nil end
    local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    local inLog = {}
    for qi = 1, n do
        local title = GetQuestLogTitle(qi)
        if title then inLog[title] = true end
    end
    for _, pq in ipairs(profile.quests) do
        if pq.acceptNPC and not inLog[pq.name] then
            return pq
        end
    end
    return nil
end

-- ---- Check if all kill objectives for a quest are met ------
-- (We cross-reference with the actual quest log.)
local function QuestKillObjectiveMet(questName, entry)
    local n = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for qi = 1, n do
        local title, _, _, complete = GetQuestLogTitle(qi)
        if title == questName then
            if complete then return true end
            -- Check individual objectives
            local nObj = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(qi) or 0
            for oi = 1, nObj do
                local text, otype, finished = GetQuestLogLeaderBoard(oi, qi)
                if finished then return true end
            end
        end
    end
    return false
end

-- ============================================================
-- External API
-- ============================================================

function GB_Leveling.Start(profileName)
    local profile = GB_Profiles.Active()
    if profileName then
        if not GB_Profiles.Load(profileName) then return end
        profile = GB_Profiles.Active()
    end
    if not profile then
        GB_Utils.Print("[Leveling] No profile loaded. Use /gbot profile <name>")
        return
    end
    lootedCorpses = {}
    patrolIdx     = 1
    SetState(STATE.PATROL)
    GB_Utils.Print("[Leveling] Started with profile: " .. profile.name)
end

function GB_Leveling.Stop()
    StopMoving()
    SetState(STATE.IDLE)
end

function GB_Leveling.IsRunning()
    return state ~= STATE.IDLE
end

-- ---- Hot-swap profile without full restart ----------------
-- Gracefully stops current state, loads new profile, and resumes.
function GB_Leveling.SwapProfile(name)
    local wasRunning = state ~= STATE.IDLE
    StopMoving()
    if not GB_Profiles.Load(name) then return false end
    lootedCorpses  = {}
    patrolIdx      = 1
    questTravelNPC = nil
    targetMob      = nil
    if wasRunning then
        SetState(STATE.PATROL)
        GB_Utils.Print("[Leveling] Hot-swapped profile to: " .. name)
    else
        SetState(STATE.IDLE)
    end
    return true
end

-- ============================================================
-- Main tick (~0.1 s)
-- ============================================================

function GB_Leveling.Tick()
    local profile = GB_Profiles.Active()
    local now     = GetTime()

    -- ---- On AFK break: do nothing --------------------------
    if GB_Human and GB_Human.IsOnBreak() then return end

    -- ---- Inventory overflow: delegate to mail system -------
    if state ~= STATE.IDLE and state ~= STATE.CHECK_MAIL then
        if GB_Inventory.ShouldMail() and not GB_Inventory.mailPending then
            StopMoving()
            GB_Inventory.StartAutoMail()
            SetState(STATE.CHECK_MAIL)
            return
        end
    end

    if state == STATE.IDLE then
        return

    -- ================================================================
    elseif state == STATE.CHECK_MAIL then
        GB_Inventory.HandleMail()
        if not GB_Inventory.mailPending then
            SetState(STATE.PATROL)
        end

    -- ================================================================
    elseif state == STATE.REST then
        -- Auto-stand and resume when recovered
        if RestComplete(profile) then
            DoEmote("STAND")
            -- Small delay before resuming (natural movement startup)
            GB_Utils.After(GR(1.2, 0.4), function()
                if state == STATE.REST then
                    SetState(STATE.PATROL)
                end
            end)
        end
        -- Periodically attempt to eat/drink if items available
        if now - stateTime > 3.0 then
            GB_Utils.Debug("[Rest] Waiting for HP/mana...")
            stateTime = now   -- reset timer so we don't spam
        end

    -- ================================================================
    elseif state == STATE.PATROL then
        if not profile then return end

        -- Check if we should rest first
        if NeedsRest(profile) and not InCombat() then
            StopMoving()
            -- Try to use food/drink
            GB_Utils.After(GR(0.4, 0.1), function()
                DoEmote("SIT")
                -- Use first food/drink from bags (macro-based; DLL handles ideally)
                CastSpellByName("Drink")
                CastSpellByName("Eat")
            end)
            SetState(STATE.REST)
            return
        end

        -- Check for completable quests before grinding further
        if profile.quests then
            local done = CompletedQuests(profile)
            if #done > 0 then
                questTravelNPC  = done[1].turnInNPC
                questTravelMode = "turnin"
                questTravelIdx  = 0
                questTravelWPs  = {}
                SetState(STATE.QUEST_TRAVEL)
                return
            end
            -- Check for quests to accept
            local toAccept = NextQuestToAccept(profile)
            if toAccept then
                questTravelNPC  = toAccept.acceptNPC
                questTravelMode = "accept"
                questTravelIdx  = 0
                questTravelWPs  = {}
                SetState(STATE.QUEST_TRAVEL)
                return
            end
        end

        -- Walk patrol path while scanning for mobs
        local path = profile.patrolPath
        if path and #path > 0 then
            local wp = path[patrolIdx]
            local arrived = StepToward(wp.x, wp.y)
            if arrived then
                patrolIdx = (patrolIdx % #path) + 1
            end
        end

        -- Scan for mobs every tick regardless of patrol position
        SetState(STATE.SCAN_MOB)

    -- ================================================================
    elseif state == STATE.SCAN_MOB then
        if not profile then SetState(STATE.PATROL); return end

        -- Build entry list from kill targets
        local entries = {}
        for _, kt in ipairs(profile.killTargets) do
            table.insert(entries, kt.entry)
        end

        local guidLo, mx, my, mz, entry, dist, mname

        if GB_FindNearestMob then
            guidLo, mx, my, mz, entry, dist, mname = GB_FindNearestMob(entries)
        end

        if not guidLo then
            -- No mob found — resume patrol
            SetState(STATE.PATROL)
            return
        end

        -- Skip already looted (dead) mobs
        if lootedCorpses[guidLo] then
            SetState(STATE.PATROL)
            return
        end

        targetMob  = { guid = guidLo, x = mx, y = my, z = mz,
                       entry = entry, name = mname or "Mob" }
        targetDead = false
        GB_Utils.Debug(string.format("[Scan] Found %s (entry %d) at %.1f yds",
            targetMob.name, entry, dist or 0))
        SetState(STATE.APPROACH)

    -- ================================================================
    elseif state == STATE.APPROACH then
        if not targetMob then SetState(STATE.SCAN_MOB); return end

        local px, py = 0, 0
        if GB_GetPlayerPos then
            local x, y = GB_GetPlayerPos()
            px, py = x, y
        end
        local dist = GB_Utils.Dist2D(px, py, targetMob.x, targetMob.y)

        -- Use PULL_RANGE if profile has ranged abilities, else close to melee
        local hasRanged = false
        if profile and profile.rotation then
            for _, ab in ipairs(profile.rotation) do
                if (ab.maxRange or 0) > 5 then hasRanged = true; break end
            end
        end
        local stopDist = hasRanged and PULL_RANGE or (MELEE_RANGE + 1.0)

        if dist <= stopDist then
            StopMoving()
            SetState(STATE.PULL)
            return
        end

        -- Move toward mob (slight Gaussian offset so path isn't perfectly straight)
        local jitterX = GR(0, 0.5)
        local jitterY = GR(0, 0.5)
        StepToward(targetMob.x + jitterX, targetMob.y + jitterY)

        -- Timeout: mob may have moved or been taken by another player
        if now - stateTime > 15 then
            GB_Utils.Debug("[Approach] Timeout — rescanning")
            StopMoving()
            targetMob = nil
            SetState(STATE.PATROL)
        end

    -- ================================================================
    elseif state == STATE.PULL then
        if not targetMob then SetState(STATE.SCAN_MOB); return end
        PullMob(targetMob)
        SetState(STATE.COMBAT)

    -- ================================================================
    elseif state == STATE.COMBAT then
        -- Safety: if target dead or gone, move to loot
        if UnitIsDead and UnitIsDead("target") then
            StopMoving()
            targetDead = true
            lootAttempts = 0
            -- Short Gaussian pause before looting — natural feel
            local lootDelay = math.max(0.5, math.min(2.5, GR(1.0, 0.35)))
            GB_Utils.After(lootDelay, function()
                if state == STATE.COMBAT then
                    SetState(STATE.LOOT_MOB)
                end
            end)
            return
        end

        -- Combat timeout guard — if we've been in combat too long, bail
        if now - stateTime > combatTimeout then
            GB_Utils.Debug("[Combat] Timeout — retreating to patrol")
            StopMoving()
            SpellStopCasting()
            ClearTarget()
            targetMob = nil
            SetState(STATE.PATROL)
            return
        end

        -- Execute ability rotation with natural Gaussian timing
        if not ExecuteRotation(profile) then
            -- No ability used — ensure auto-attack is on
            if not (UnitAffectingCombat and UnitAffectingCombat("player")) then
                -- Re-initiate if we somehow dropped combat
                AttackTarget()
            end
        end

        -- Need to rest after combat ends?
        if not InCombat() and not (UnitIsDead and UnitIsDead("target")) then
            if NeedsRest(profile) then
                SetState(STATE.REST)
            else
                SetState(STATE.PATROL)
            end
        end

    -- ================================================================
    elseif state == STATE.LOOT_MOB then
        if not targetMob then SetState(STATE.PATROL); return end

        -- Move to corpse if needed
        local px, py = 0, 0
        if GB_GetPlayerPos then
            local x, y = GB_GetPlayerPos()
            px, py = x, y
        end
        local dist = GB_Utils.Dist2D(px, py, targetMob.x, targetMob.y)

        if dist > REACH_MOB then
            StepToward(targetMob.x, targetMob.y)
            if now - stateTime > 8 then
                -- Can't reach corpse — give up
                targetMob = nil
                SetState(STATE.CHECK_QUEST)
            end
            return
        end

        -- Attempt to loot
        if lootAttempts == 0 then
            if SuperWoW_InteractObject then
                SuperWoW_InteractObject(targetMob.guid)
            else
                RunMacroText("/loot")
            end
            lootAttempts = 1
        end

        -- LootFrame opened → auto-loot handled by LOOT_OPENED event
        -- Mark as looted so we don't return to this corpse
        lootedCorpses[targetMob.guid] = true
        targetMob = nil

        -- Check if rest needed between kills — with small Gaussian evaluation delay
        GB_Utils.After(GR(0.6, 0.2), function()
            if state == STATE.LOOT_MOB then
                SetState(STATE.CHECK_QUEST)
            end
        end)

    -- ================================================================
    elseif state == STATE.CHECK_QUEST then
        -- Very cheap check — just re-enter patrol; patrol handles quest logic
        SetState(STATE.PATROL)

    -- ================================================================
    elseif state == STATE.QUEST_TRAVEL then
        if not questTravelNPC then SetState(STATE.PATROL); return end

        -- Build waypoints on first entry
        if #questTravelWPs == 0 then
            local px, py = 0, 0
            if GB_GetPlayerPos then
                local x, y = GB_GetPlayerPos()
                px, py = x, y
            end
            questTravelWPs = BuildPath(px, py, questTravelNPC.x, questTravelNPC.y)
            questTravelIdx = 1
        end

        -- Check arrival at NPC
        local px, py = 0, 0
        if GB_GetPlayerPos then
            local x, y = GB_GetPlayerPos()
            px, py = x, y
        end
        local distToNPC = GB_Utils.Dist2D(px, py, questTravelNPC.x, questTravelNPC.y)

        if distToNPC <= REACH_MOB then
            StopMoving()
            npcInteractSent = false
            npcInteractTime = now
            if questTravelMode == "turnin" then
                SetState(STATE.TURN_IN)
            else
                SetState(STATE.ACCEPT_QUEST)
            end
            return
        end

        -- Walk waypoints
        if questTravelIdx <= #questTravelWPs then
            local wp = questTravelWPs[questTravelIdx]
            local arrived = StepToward(wp.x, wp.y)
            if arrived then questTravelIdx = questTravelIdx + 1 end
        else
            -- Ran out of waypoints but not close enough — step directly
            StepToward(questTravelNPC.x, questTravelNPC.y)
        end

        -- Travel timeout guard
        if now - stateTime > 120 then
            GB_Utils.Debug("[QuestTravel] Timeout — returning to patrol")
            StopMoving()
            questTravelNPC = nil
            SetState(STATE.PATROL)
        end

    -- ================================================================
    elseif state == STATE.TURN_IN then
        if not npcInteractSent then
            npcInteractSent = true
            if questTravelNPC and questTravelNPC.name then
                TargetByName(questTravelNPC.name)
            end
            GB_Utils.After(GR(0.6, 0.2), function()
                InteractUnit("target")
            end)
        end

        -- After 4 s assume NPC gossip/quest window may be open
        if now - npcInteractTime > 4.0 then
            -- Attempt quest completion for any active and complete quests
            if QuestFrameCompleteQuestButton and QuestFrameCompleteQuestButton:IsShown() then
                -- Choose best reward (index 1 by default; profiles can override)
                local rewardIdx = (questTravelNPC and questTravelNPC.rewardChoice) or 1
                if GetNumQuestChoices and GetNumQuestChoices() > 0 then
                    GetQuestReward(rewardIdx)
                else
                    CompleteQuest()
                end
                GB_Utils.Print("[Quest] Turned in quest!")
            end
            -- Timeout guard
            if now - npcInteractTime > 10.0 then
                ClearTarget()
                questTravelNPC  = nil
                questTravelMode = nil
                npcInteractSent = false
                SetState(STATE.PATROL)
            end
        end

    -- ================================================================
    elseif state == STATE.ACCEPT_QUEST then
        if not npcInteractSent then
            npcInteractSent = true
            if questTravelNPC and questTravelNPC.name then
                TargetByName(questTravelNPC.name)
            end
            GB_Utils.After(GR(0.6, 0.2), function()
                InteractUnit("target")
            end)
        end

        -- After 3 s attempt to accept all available quests at this NPC
        if now - npcInteractTime > 3.0 then
            local nAvail = GetNumAvailableQuests and GetNumAvailableQuests() or 0
            for qi = 1, nAvail do
                SelectQuest(qi)
                GB_Utils.After(qi * GR(0.5, 0.1), function()
                    AcceptQuest()
                    GB_Utils.Print("[Quest] Accepted quest " .. qi)
                end)
            end
            -- Timeout guard
            if now - npcInteractTime > 8.0 then
                ClearTarget()
                questTravelNPC  = nil
                questTravelMode = nil
                npcInteractSent = false
                SetState(STATE.PATROL)
            end
        end
    end
end

-- ============================================================
-- Event hooks (called from GromitBot.lua OnEvent)
-- ============================================================

function GB_Leveling.OnLootOpened()
    -- Auto-loot handled centrally in GromitBot.lua LOOT_OPENED handler;
    -- transition loot state forward if we were looting.
    if state == STATE.LOOT_MOB then
        SetState(STATE.CHECK_QUEST)
    end
end

function GB_Leveling.OnUnitDied(unitToken)
    -- If our current target mob just died from a non-player kill (rare),
    -- record it and prepare to loot.
    if unitToken == "target" and targetMob then
        if state == STATE.COMBAT or state == STATE.APPROACH then
            targetDead = true
        end
    end
end

function GB_Leveling.OnEnterCombat()
    -- If we were patrolling and got pulled into combat, pivot to COMBAT state.
    if state == STATE.PATROL or state == STATE.SCAN_MOB then
        GB_Utils.Debug("[Leveling] Unexpected combat — pivoting to COMBAT state")
        SetState(STATE.COMBAT)
    end
end
