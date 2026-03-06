-- ============================================================
-- human_behavior.lua — Random humanisation while bot runs:
--   • Occasional jumps while running
--   • Frequent small camera turns
--   • Slight position wanders (always returns to home)
-- ============================================================

GB_Human = {}

local homeX, homeY, homeZ = nil, nil, nil
local lastJump       = 0
local lastTurn       = 0
local lastWiggle     = 0
local nextTurnAt     = 0
local nextWiggleAt   = 0
local isWiggling     = false
local wiggleTarget   = nil
local wiggleStarted  = 0

-- ---- Initialise home position on bot start -----------------
function GB_Human.SetHome()
    if GB_GetPlayerPos then
        homeX, homeY, homeZ = GB_GetPlayerPos()
        GB_Utils.Debug(string.format("Home set to %.1f, %.1f, %.1f", homeX, homeY, homeZ))
    end
end

-- ---- Random camera turn ------------------------------------
local function RandomCameraYaw()
    local cfg   = GromitBot_GetConfig()
    local delta = GB_Utils.RandFloat(-cfg.humanTurnAmount, cfg.humanTurnAmount)

    -- WoW 1.12 camera control
    -- TurnLeftStart / TurnRightStart require held keypress; we instead
    -- use SetView (available via SuperWoW or just rotate the facing).
    if Camera_SetYaw then
        Camera_SetYaw(delta)
    else
        -- Emulate via player facing for small cosmetic jitter
        -- This slightly alters movement direction; keep delta small.
        if delta > 0 then
            TurnRightStart()
            GB_Utils.After(math.abs(delta) * 0.3, function() TurnRightStop() end)
        else
            TurnLeftStart()
            GB_Utils.After(math.abs(delta) * 0.3, function() TurnLeftStop() end)
        end
    end
end

-- ---- Random jump -------------------------------------------
local function DoRandomJump()
    JumpOrAscendStart()
    GB_Utils.After(0.1, function() JumpOrAscendStop() end)
end

-- ---- Wiggle: move to a random nearby point then return -----
local function StartWiggle()
    if not homeX then return end
    local cfg = GromitBot_GetConfig()
    local r   = cfg.humanWiggleRadius

    local angle  = GB_Utils.RandFloat(0, 2 * math.pi)
    local radius = GB_Utils.RandFloat(0.5, r)
    local tx = homeX + math.cos(angle) * radius
    local ty = homeY + math.sin(angle) * radius

    wiggleTarget = { x = tx, y = ty }
    isWiggling   = true
    wiggleStarted = GetTime()

    if MoveToPosition then
        local px, py, pz = GB_GetPlayerPos()
        MoveToPosition(tx, ty, pz)

        -- After 2 s return home
        GB_Utils.After(2.0, function()
            if isWiggling then
                MoveToPosition(homeX, homeY, homeZ)
                GB_Utils.After(2.0, function()
                    isWiggling = false
                end)
            end
        end)
    else
        -- Fallback: just do a waddling forward-backward move
        MoveForwardStart()
        GB_Utils.After(0.4, function()
            MoveForwardStop()
            isWiggling = false
        end)
    end
end

-- ---- Main tick (~0.5 s for human behavior) -----------------
function GB_Human.Tick()
    local cfg = GromitBot_GetConfig()
    local now = GetTime()

    -- ---- Random camera turn ---------------------------------
    if now >= nextTurnAt then
        RandomCameraYaw()
        local lo = cfg.humanTurnInterval[1] or 4
        local hi = cfg.humanTurnInterval[2] or 10
        nextTurnAt = now + GB_Utils.RandFloat(lo, hi)
    end

    -- ---- Random jump (while running only) -------------------
    if math.random() < cfg.humanJumpChance * 0.5 then  -- per tick (0.5 s)
        if now - lastJump > 3.0 then
            DoRandomJump()
            lastJump = now
        end
    end

    -- ---- Position wiggle (fishing: while waiting for bobber only) --
    if not isWiggling and now >= nextWiggleAt then
        -- Only wiggle during fishing WAIT_BOBBER or herbalism PATHFIND
        local bot = GromitBot_GetConfig().mode
        local doWiggle = false
        if bot == "fishing"   and GB_Fishing   and GB_Fishing.IsRunning()   then doWiggle = true end
        if bot == "herbalism" and GB_Herbalism and GB_Herbalism.IsRunning() then doWiggle = true end

        if doWiggle then
            StartWiggle()
        end

        local lo = cfg.humanWiggleInterval[1] or 8
        local hi = cfg.humanWiggleInterval[2] or 20
        nextWiggleAt = now + GB_Utils.RandFloat(lo, hi)
    end
end
