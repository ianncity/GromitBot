-- ============================================================
-- human_behavior.lua — Anti-detection humanisation layer:
--   • Gaussian-distributed camera turns (yaw + pitch)
--   • Random jumps with enforced minimum gap
--   • Position wanders (returns to home after)
--   • Random emotes & target scanning
--   • Occasional sit/stand pauses
--   • Camera pitch (vertical look) variation
--   • "Distracted" micro-break system (random longer pauses)
--   • Session-level AFK break scheduling
-- ============================================================

GB_Human = {}

local homeX, homeY, homeZ    = nil, nil, nil
local lastJump                = 0
local nextTurnAt              = 0
local nextWiggleAt            = 0
local nextEmoteAt             = 0
local nextScanAt              = 0
local nextPitchAt             = 0
local isWiggling              = false

-- Nearby player awareness — tracks names seen recently so we react
-- more visibly to a player we haven't seen before (mimicking curiosity).
local nearbyPlayerCache = {}   -- { [name] = { seenAt = time, count = n } }

-- AFK / session break state
local sessionStartTime        = nil
local nextBreakAt             = nil
local isOnBreak               = false
local breakEndAt              = nil

-- ---- Use shared Gaussian helpers ---------------------------
local GaussRand = GB_Utils.GaussRand

-- ---- Sample next interval with natural variance ------------
-- Uses Gaussian centred at midpoint of [lo, hi].
local function NextInterval(lo, hi)
    local mid = (lo + hi) * 0.5
    local sd  = (hi - lo) * 0.18   -- ~34 % of range as one sigma
    return math.max(lo, math.min(hi, GaussRand(mid, sd)))
end

-- ---- Initialise home position on bot start -----------------
function GB_Human.SetHome()
    if GB_GetPlayerPos then
        homeX, homeY, homeZ = GB_GetPlayerPos()
        sessionStartTime = GetTime()
        GB_Human.ScheduleNextBreak()
        GB_Utils.Debug(string.format("Home set to %.1f, %.1f, %.1f", homeX, homeY, homeZ))
    end
end

-- ---- Schedule the next AFK break ---------------------------
function GB_Human.ScheduleNextBreak()
    local cfg = GromitBot_GetConfig()
    if not cfg.humanBreaksEnabled then return end
    local lo = cfg.humanBreakInterval[1] or 2700   -- 45 min
    local hi = cfg.humanBreakInterval[2] or 5400   -- 90 min
    nextBreakAt = GetTime() + NextInterval(lo, hi)
    GB_Utils.Debug(string.format("Next AFK break in %.0f s", nextBreakAt - GetTime()))
end

-- ---- Is the bot currently on an AFK break? -----------------
function GB_Human.IsOnBreak()
    return isOnBreak
end

-- ---- Force-cancel an in-progress AFK break -----------------
function GB_Human.CancelBreak()
    if not isOnBreak then return end
    isOnBreak  = false
    breakEndAt = nil
    DoEmote("STAND")
    GB_Utils.Print("[AFK] Break cancelled.")
    GB_Human.ScheduleNextBreak()
end

-- ---- Random camera yaw turn --------------------------------
local function RandomCameraYaw()
    local cfg   = GromitBot_GetConfig()
    -- Use Gaussian: most turns are small, occasional larger swings
    local maxAmt = cfg.humanTurnAmount or 0.15
    local delta  = GaussRand(0, maxAmt * 0.5)
    delta = math.max(-maxAmt, math.min(maxAmt, delta))

    if Camera_SetYaw then
        Camera_SetYaw(delta)
    elseif delta > 0 then
        TurnRightStart()
        GB_Utils.After(math.abs(delta) * 0.25, function() TurnRightStop() end)
    else
        TurnLeftStart()
        GB_Utils.After(math.abs(delta) * 0.25, function() TurnLeftStop() end)
    end
end

-- ---- Random camera pitch (look up/down) --------------------
local function RandomCameraPitch()
    local cfg = GromitBot_GetConfig()
    if not cfg.humanPitchEnabled then return end
    -- Subtle vertical drift: ±10 degrees
    local maxPitch = cfg.humanPitchAmount or 0.12   -- radians
    local delta    = GaussRand(0, maxPitch * 0.4)
    delta = math.max(-maxPitch, math.min(maxPitch, delta))
    if Camera_SetPitch then
        Camera_SetPitch(delta)
    end
end

-- ---- Random jump -------------------------------------------
local function DoRandomJump()
    JumpOrAscendStart()
    GB_Utils.After(0.08 + math.random() * 0.05, function() JumpOrAscendStop() end)
end

-- ---- Random emote ------------------------------------------
local EMOTES = {
    "STRETCH", "YAWN", "SCRATCH", "BORED", "FIDGET",
    "WAVE", "NOD", "SHRUG", "SIT", "STAND",
    "ROAR", "CHEER", "LAUGH", "SIGH", "CURIOUS",
}
local function DoRandomEmote()
    local cfg = GromitBot_GetConfig()
    if not cfg.humanEmotesEnabled then return end
    local emote = EMOTES[math.random(#EMOTES)]
    -- SIT / STAND are special: sit for a brief moment then stand
    if emote == "SIT" then
        DoEmote("SIT")
        local sitDur = GaussRand(4.0, 1.5)
        sitDur = math.max(2.0, math.min(8.0, sitDur))
        GB_Utils.After(sitDur, function() DoEmote("STAND") end)
    else
        DoEmote(emote)
    end
    GB_Utils.Debug("Emote: " .. emote)
end

-- ---- Position wiggle: wander then return home --------------
local function StartWiggle()
    if not homeX then return end
    local cfg = GromitBot_GetConfig()
    local r   = cfg.humanWiggleRadius

    -- Gaussian radius — usually small, occasionally wider
    local angle  = GB_Utils.RandFloat(0, 2 * math.pi)
    local radius = math.abs(GaussRand(0, r * 0.4))
    radius = math.max(0.5, math.min(r, radius))

    local tx = homeX + math.cos(angle) * radius
    local ty = homeY + math.sin(angle) * radius

    isWiggling = true

    if MoveToPosition then
        local _, _, pz = GB_GetPlayerPos and GB_GetPlayerPos() or homeX, homeY, homeZ
        MoveToPosition(tx, ty, pz or homeZ)

        local returnDelay = GaussRand(2.2, 0.5)
        returnDelay = math.max(1.0, math.min(4.0, returnDelay))
        GB_Utils.After(returnDelay, function()
            if isWiggling then
                MoveToPosition(homeX, homeY, homeZ)
                GB_Utils.After(GaussRand(2.0, 0.4), function()
                    isWiggling = false
                end)
            end
        end)
    else
        MoveForwardStart()
        GB_Utils.After(GaussRand(0.4, 0.1), function()
            MoveForwardStop()
            isWiggling = false
        end)
    end
end

-- ---- AFK break: stop bot, idle for a random duration -------
local function StartAFKBreak()
    local cfg    = GromitBot_GetConfig()
    local lo     = cfg.humanBreakDuration[1] or 180   -- 3 min
    local hi     = cfg.humanBreakDuration[2] or 900   -- 15 min
    local dur    = NextInterval(lo, hi)

    isOnBreak  = true
    breakEndAt = GetTime() + dur

    -- Stop all bots
    if GB_Fishing   then GB_Fishing.Stop()   end
    if GB_Herbalism then GB_Herbalism.Stop() end
    if GB_Leveling  then GB_Leveling.Stop()  end

    -- Sit down for the break
    GB_Utils.After(GaussRand(2.0, 0.8), function() DoEmote("SIT") end)

    GB_Utils.Print(string.format("[AFK] Break for %.0f s — resuming after.", dur))
    GB_Utils.Debug(string.format("AFK break: %.0f s", dur))
end

-- ---- End AFK break and resume the bot ----------------------
local function EndAFKBreak()
    isOnBreak = false
    DoEmote("STAND")
    local cfg = GromitBot_GetConfig()
    GB_Utils.After(GaussRand(3.0, 1.0), function()
        if cfg.mode == "fishing"   and GB_Fishing   then
            GB_Human.SetHome()
            GB_Fishing.Start()
        elseif cfg.mode == "herbalism" and GB_Herbalism then
            GB_Human.SetHome()
            GB_Herbalism.Start()
        elseif cfg.mode == "leveling" and GB_Leveling then
            GB_Human.SetHome()
            GB_Leveling.Start()
        end
        GB_Utils.Print("[AFK] Break ended — resuming bot.")
    end)
    GB_Human.ScheduleNextBreak()
end

-- ---- Random target scan — with player-awareness -----------
-- Alternates targeting friends/enemies so we notice hostile
-- players approaching, not just friendly ones.
-- Tracks "new" players and reacts with visible curiosity.
local function DoRandomTargetScan()
    local cfg = GromitBot_GetConfig()
    if not cfg.humanTargetScanEnabled then return end
    local now = GetTime()

    -- Broaden scan: sometimes check for enemies/hostile players too
    if math.random() < 0.55 then
        TargetNearestFriend()
    else
        TargetNearestEnemy()
    end

    if UnitExists and UnitExists("target")
       and UnitIsPlayer and UnitIsPlayer("target") then
        local name = UnitName("target") or ""
        local data = nearbyPlayerCache[name]
        if not data then
            -- First time noticing this player — react with visible curiosity
            nearbyPlayerCache[name] = { seenAt = now, count = 1 }
            local roll = math.random()
            if roll < 0.30 then
                DoEmote("WAVE")
            elseif roll < 0.55 then
                DoEmote("NOD")
            end
            -- Hold target longer — a real player would study a newcomer
            GB_Utils.After(GaussRand(4.0, 1.0), function() ClearTarget() end)
            GB_Utils.Debug("Noticed new nearby player: " .. name)
        else
            -- Seen before — brief recognition glance then dismiss
            data.seenAt = now
            data.count  = data.count + 1
            GB_Utils.After(GaussRand(1.5, 0.5), function() ClearTarget() end)
        end
    else
        -- No player in view — clear immediately
        GB_Utils.After(0.3, function() ClearTarget() end)
    end
    GB_Utils.Debug("Target scan")
end

-- ---- Main tick (~0.5 s) ------------------------------------
function GB_Human.Tick()
    local cfg = GromitBot_GetConfig()
    local now = GetTime()

    -- ---- AFK break management -------------------------------
    if cfg.humanBreaksEnabled then
        if isOnBreak then
            if breakEndAt and now >= breakEndAt then
                EndAFKBreak()
            end
            return  -- suppress all other human actions during break
        elseif nextBreakAt and now >= nextBreakAt then
            StartAFKBreak()
            return
        end
    end

    -- ---- Random camera yaw turn -----------------------------
    if now >= nextTurnAt then
        RandomCameraYaw()
        local lo = cfg.humanTurnInterval[1] or 4
        local hi = cfg.humanTurnInterval[2] or 10
        nextTurnAt = now + NextInterval(lo, hi)
    end

    -- ---- Random camera pitch --------------------------------
    if now >= nextPitchAt then
        RandomCameraPitch()
        nextPitchAt = now + NextInterval(8, 22)
    end

    -- ---- Random jump (with minimum gap + Gaussian spacing) --
    if now - lastJump > (cfg.humanJumpMinGap or 4.0) then
        -- Poisson-like: test once per tick with correct average rate
        local tickRate    = 0.5
        local avgInterval = 1.0 / (cfg.humanJumpChance or 0.08)
        local prob        = tickRate / avgInterval
        if math.random() < prob then
            DoRandomJump()
            lastJump = now
        end
    end

    -- ---- Random emote ---------------------------------------
    if now >= nextEmoteAt then
        DoRandomEmote()
        local lo = cfg.humanEmoteInterval[1] or 45
        local hi = cfg.humanEmoteInterval[2] or 120
        nextEmoteAt = now + NextInterval(lo, hi)
    end

    -- ---- Random target scan ---------------------------------
    if now >= nextScanAt then
        DoRandomTargetScan()
        local lo = cfg.humanScanInterval[1] or 30
        local hi = cfg.humanScanInterval[2] or 90
        nextScanAt = now + NextInterval(lo, hi)
        -- Prune player cache: forget players not seen for 5 minutes
        for name, data in pairs(nearbyPlayerCache) do
            if now - data.seenAt > 300 then
                nearbyPlayerCache[name] = nil
            end
        end
    end

    -- ---- Position wiggle ------------------------------------
    if not isWiggling and now >= nextWiggleAt then
        local mode = cfg.mode
        local doWiggle = false
        -- Don't wiggle while the bot is standing still to type a reply
        if not (GB_Chat and GB_Chat.IsTyping()) then
            if mode == "fishing"   and GB_Fishing   and GB_Fishing.IsRunning()   then doWiggle = true end
            if mode == "herbalism" and GB_Herbalism and GB_Herbalism.IsRunning() then doWiggle = true end
        end

        if doWiggle then StartWiggle() end

        local lo = cfg.humanWiggleInterval[1] or 8
        local hi = cfg.humanWiggleInterval[2] or 20
        nextWiggleAt = now + NextInterval(lo, hi)
    end
end
