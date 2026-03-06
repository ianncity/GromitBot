-- ============================================================
-- herbalism.lua — Full herbalism bot state machine
-- ============================================================
--
-- States:
--   IDLE          → not running
--   SCAN          → activate Find Herbs, look for nearest node
--   PATHFIND      → move toward herb node using navmesh waypoints
--   INTERACT      → right-click herb node (interact)
--   LOOT          → wait for/auto-loot the herb node
--   COOLDOWN      → brief pause before next scan
--   CHECK_MAIL    → bags full, mail items
-- ============================================================

GB_Herbalism = {}

local STATE = {
    IDLE       = "IDLE",
    NOTICE     = "NOTICE",    -- brief reaction pause after spotting a node
    SCAN       = "SCAN",
    PATHFIND   = "PATHFIND",
    INTERACT   = "INTERACT",
    LOOT       = "LOOT",
    COOLDOWN   = "COOLDOWN",
    CHECK_MAIL = "CHECK_MAIL",
}

local state               = STATE.IDLE
local stateTime           = 0
local targetNode          = nil   -- {guid, x, y, z, entry}
local waypoints           = {}    -- list of {x,y} waypoints from navmesh
local wpIdx               = 0
local interactSent        = false
local combatCooldownUntil = 0     -- absolute time: don't resume farming before this
local REACH_DIST   = 4.5   -- yards to consider "at node"
local SCAN_RANGE   = 100   -- yards (visual range)

-- ---- Curved path builder -----------------------------------
-- Adds a Gaussian-distributed lateral arc plus per-step micro-jitter
-- so paths are never perfectly straight, defeating straight-line detection.
local function BuildCurvedPath(sx, sy, ex, ey)
    local path   = {}
    local dx, dy = ex - sx, ey - sy
    local dist   = math.sqrt(dx * dx + dy * dy)
    local steps  = math.max(2, math.floor(dist / 2))
    -- Unit normal perpendicular to the path direction
    local len    = math.max(dist, 0.01)
    local nx, ny = -dy / len, dx / len
    -- Smooth arc: Gaussian peak offset capped at ±15 % of path length
    local peakOff = GB_Utils.GaussRand(0, dist * 0.07)
    peakOff = math.max(-dist * 0.15, math.min(dist * 0.15, peakOff))
    for i = 1, steps do
        local t       = i / steps
        local lateral = peakOff * math.sin(t * math.pi)
        -- Per-step micro-jitter keeps individual segments irregular
        local wx = sx + dx * t + nx * lateral + GB_Utils.GaussRand(0, 0.25)
        local wy = sy + dy * t + ny * lateral + GB_Utils.GaussRand(0, 0.25)
        table.insert(path, { x = wx, y = wy })
    end
    return path
end

-- ---- State helpers -----------------------------------------
local function SetState(s)
    state     = s
    stateTime = GetTime()
    GB_Utils.Debug("Herbalism: → " .. s)
end

-- ---- Find Herbs activation ---------------------------------
local function EnsureHerbTracking()
    -- Check if Find Herbs is active; if not, cast it.
    -- We use UnitBuff scanning or just cast regardless (idempotent).
    CastSpellByName("Find Herbs")
end

-- ---- Interact with game object by guid ---------------------
local function InteractNode(guid)
    if SuperWoW_InteractObject then
        SuperWoW_InteractObject(guid)
    else
        -- Targeting by name as fallback (less reliable)
        RunMacroText("/target Silverleaf\n/interact 1")
    end
end

-- ---- Auto-loot all slots -----------------------------------
local function AutoLootAll()
    for i = 1, GetNumLootItems() do
        LootSlot(i)
    end
    CloseLoot()
end

-- ---- Movement helper (vanilla uses keyboard emulation) -----
-- SuperWoW exposes MoveToPosition(x, y, z) — use that if available,
-- otherwise simulate keypress movement toward next waypoint.
local moveFrame     = nil
local MOVE_SPEED    = 7.0     -- yards per second (run speed)
local WP_REACH_DIST = 3.0

local function StopMoving()
    if MoveToPosition then MoveToPosition(0, 0, 0, 0) end  -- cancel
    -- Release movement keys
    RunMacroText("/stopcasting")
end

local function StepToward(tx, ty)
    local px, py, pz = GB_GetPlayerPos and GB_GetPlayerPos() or 0, 0, 0
    if GB_GetPlayerPos then
        px, py, pz = GB_GetPlayerPos()
    end
    local dx, dy = tx - px, ty - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < WP_REACH_DIST then return true end  -- reached this waypoint

    -- Calculate facing angle
    local angle = math.atan2(dy, dx)

    if MoveToPosition then
        -- SuperWoW CTM helper
        MoveToPosition(tx, ty, pz)
    else
        -- Keyboard: set facing then press forward
        local facing = GB_GetPlayerFacing and GB_GetPlayerFacing() or 0
        local diff = angle - facing
        -- Wrap diff to [-pi, pi]
        while diff >  math.pi do diff = diff - 2 * math.pi end
        while diff < -math.pi do diff = diff + 2 * math.pi end
        -- Small rotation
        if math.abs(diff) > 0.05 then
            MoveAndStrafeStart(diff > 0 and "STRAFELEFT" or "STRAFERIGHT")
        else
            MoveAndStrafeStop("STRAFELEFT")
            MoveAndStrafeStop("STRAFERIGHT")
        end
        MoveForwardStart()
    end
    return false
end

-- ---- External API ------------------------------------------
function GB_Herbalism.Start()
    EnsureHerbTracking()
    SetState(STATE.SCAN)
end

function GB_Herbalism.Stop()
    SetState(STATE.IDLE)
    StopMoving()
end

function GB_Herbalism.IsRunning()
    return state ~= STATE.IDLE
end

-- ---- Main tick (~0.1 s) ------------------------------------
function GB_Herbalism.Tick()
    local now = GetTime()

    -- Freeze movement while the chat LLM is composing a reply
    if GB_Chat and GB_Chat.IsTyping() then return end

    -- -------- Inventory check --------------------------------
    if state ~= STATE.IDLE and state ~= STATE.CHECK_MAIL then
        if GB_Inventory.ShouldMail() and not GB_Inventory.mailPending then
            GB_Herbalism.Stop()
            GB_Inventory.StartAutoMail()
            SetState(STATE.CHECK_MAIL)
            return
        end
    end

    if state == STATE.IDLE then
        return

    elseif state == STATE.CHECK_MAIL then
        GB_Inventory.HandleMail()
        if not GB_Inventory.mailPending then
            SetState(STATE.SCAN)
        end

    elseif state == STATE.SCAN then
        if not GB_FindNearestHerb then
            GB_Utils.Debug("GB_FindNearestHerb not available — DLL not loaded?")
            SetState(STATE.COOLDOWN)
            return
        end
        local guidLo, hx, hy, hz, entry, dist = GB_FindNearestHerb()
        if not guidLo then
            GB_Utils.Debug("No herb nodes in range — cooling down")
            SetState(STATE.COOLDOWN)
            return
        end
        targetNode = { guid = guidLo, x = hx, y = hy, z = hz, entry = entry }
        GB_Utils.Debug(string.format("Found herb entry %d at %.1f yards", entry, dist))
        -- Transition through NOTICE: simulate the player "seeing" the node
        -- on the minimap before committing to a direction change.
        SetState(STATE.NOTICE)

    elseif state == STATE.NOTICE then
        -- Gaussian-sampled reaction pause (0.3 – 1.4 s) before pathing.
        -- Eliminates the instant back-turn that reveals bot movement.
        local noticeDur = math.max(0.3, math.min(1.4,
            GB_Utils.GaussRand(0.65, 0.28)))
        if now - stateTime < noticeDur then return end
        if not targetNode then SetState(STATE.SCAN); return end
        local px, py, pz = 0, 0, 0
        if GB_GetPlayerPos then px, py, pz = GB_GetPlayerPos() end
        waypoints = BuildCurvedPath(px, py, targetNode.x, targetNode.y)
        wpIdx = 1
        interactSent = false
        SetState(STATE.PATHFIND)

    elseif state == STATE.PATHFIND then
        if not targetNode then SetState(STATE.SCAN); return end
        local px, py, pz = GB_GetPlayerPos()
        local nodeDist = GB_Utils.Dist2D(px, py, targetNode.x, targetNode.y)

        if nodeDist <= REACH_DIST then
            StopMoving()
            SetState(STATE.INTERACT)
            return
        end

        -- Navigate waypoints
        if wpIdx > #waypoints then
            -- We have waypoints but still far — rescan
            SetState(STATE.SCAN)
            return
        end

        local wp = waypoints[wpIdx]
        local reached = StepToward(wp.x, wp.y)
        if reached then wpIdx = wpIdx + 1 end

        -- Timeout protection
        if now - stateTime > 60 then
            GB_Utils.Debug("Pathfind timeout — rescanning")
            StopMoving()
            SetState(STATE.SCAN)
        end

    elseif state == STATE.INTERACT then
        if not interactSent then
            interactSent = true
            InteractNode(targetNode.guid)
        end
        -- If loot window opened, transition
        if LootFrame and LootFrame:IsShown() then
            SetState(STATE.LOOT)
        elseif now - stateTime > 5 then
            -- Node may have been harvested by another player; rescan
            GB_Utils.Debug("Interact timeout — rescanning")
            SetState(STATE.SCAN)
        end

    elseif state == STATE.LOOT then
        AutoLootAll()
        targetNode = nil
        SetState(STATE.COOLDOWN)

    elseif state == STATE.COOLDOWN then
        -- Respect combat-imposed pause before resuming farming
        local ready = (now - stateTime > 1.5) and (now >= combatCooldownUntil)
        if ready then
            SetState(STATE.SCAN)
        end
    end
end

-- ---- Loot ready event hook ---------------------------------
function GB_Herbalism.OnLootOpened()
    if state == STATE.INTERACT then
        SetState(STATE.LOOT)
    end
end

-- ---- Combat hook: called when player enters combat ---------
-- Stops farming and backs away briefly so the bot doesn't just
-- stand frozen in place (the #1 tell from player-reported observations).
function GB_Herbalism.OnEnterCombat()
    if state == STATE.IDLE then return end
    StopMoving()
    -- Brief back-step mimics a surprised player's instinctive recoil
    MoveBackwardStart()
    local fleeDur = math.max(1.0, math.min(3.5,
        GB_Utils.GaussRand(2.0, 0.6)))
    GB_Utils.After(fleeDur, function() MoveBackwardStop() end)
    -- Extended cooldown: don't resume farming until well after combat ends
    combatCooldownUntil = GetTime() + math.max(8, math.min(22,
        GB_Utils.GaussRand(14, 4)))
    SetState(STATE.COOLDOWN)
    GB_Utils.Debug("[Herbalism] Combat detected — pausing farming")
end
