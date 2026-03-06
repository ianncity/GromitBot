-- ============================================================
-- fishing.lua — Full fishing bot state machine
-- ============================================================
--
-- States:
--   IDLE        → wait for bot to be enabled
--   EQUIP       → equip fishing rod if not already equipped
--   CAST        → cast Fishing spell
--   WAIT_BOBBER → wait for bobber splash (dynamic flag OR polling)
--   REACT       → simulated human reaction delay before clicking bobber
--   LOOT        → right-click bobber to loot
--   RECAST_WAIT → Gaussian-distributed delay before recasting
--   CHECK_MAIL  → bags full, find/open mailbox, mail items
--
-- Anti-detection improvements:
--   • Gaussian reaction time: 0.3–2.5 s after splash before loot
--   • Gaussian recast delay centered at 1.8 s (σ 0.4 s)
--   • ~3 % chance of "missed click" → recast immediately
--   • ~4 % chance of "distracted" pause: 6–18 s before recast
--   • Cast timeout itself varies ±8 s around a 28 s mean
-- ============================================================

GB_Fishing = {}

local STATE = {
    IDLE        = "IDLE",
    EQUIP       = "EQUIP",
    CAST        = "CAST",
    WAIT_BOBBER = "WAIT_BOBBER",
    REACT       = "REACT",    -- human reaction delay after splash detected
    LOOT        = "LOOT",
    RECAST_WAIT = "RECAST_WAIT",
    CHECK_MAIL  = "CHECK_MAIL",
}

local state        = STATE.IDLE
local stateTime    = 0           -- time we entered current state
local recastDelay  = 0
local reactUntil   = 0           -- timestamp for end of reaction delay
local bobberGuid   = nil
local castTimeout  = 28          -- base seconds to wait for a bite
local thisCastTimeout = 28       -- per-cast timeout (varied each cast)
local equipCheck   = false
local missedClicks = 0           -- streak counter (reset on success)

-- Forward declaration so helper functions below can reference SetState
-- before it is formally defined.
local SetState

-- Gaussian helpers (forwarded from GB_Utils for readability)
local function GR(mean, sd) return GB_Utils.GaussRand(mean, sd) end
local function GI(lo, hi)   return GB_Utils.GaussInterval(lo, hi) end

-- ---- Fishing rod detection ---------------------------------
local ROD_NAMES = {
    "Fishing Pole", "Strong Fishing Pole", "Darkwood Fishing Pole",
    "Big Iron Fishing Pole", "Blump Family Fishing Pole",
    "Nat Pagle's Extreme Angler FC-5000", "Arcanite Fishing Pole",
    "Seth's Graphite Fishing Pole", "Mastercraft Kalu'ak Fishing Pole",
}
local ROD_SET = GB_Utils.Set(ROD_NAMES)

local function IsEquippedFishingRod()
    local link = GetInventoryItemLink("player", 16)  -- main hand slot = 16
    if not link then return false end
    local name = link:match("%[(.-)%]")
    return name and (ROD_SET[name] or name:find("[Ff]ishing") ~= nil)
end

local function EquipFishingRod()
    for bag = 0, 4 do
        local n = GetContainerNumSlots(bag)
        for slot = 1, (n or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = link:match("%[(.-)%]")
                if name and (ROD_SET[name] or name:find("[Ff]ishing") ~= nil) then
                    PickupContainerItem(bag, slot)
                    PickupInventoryItem(16)  -- equip to main hand
                    GB_Utils.Debug("Equipping fishing rod: " .. name)
                    return true
                end
            end
        end
    end
    GB_Utils.Print("No fishing rod found in bags!")
    return false
end

-- ---- Bobber splash detection using memory read --------------
local function IsBobberSplashed()
    if not GB_FindFishingBobber then return false end
    local guidLo, guidHi, x, y, z, splashed = GB_FindFishingBobber()
    if guidLo and splashed and splashed == 1 then
        bobberGuid = guidLo
        return true
    end
    return false
end

-- ---- Interact with bobber (right-click via GUID) -----------
local function LootBobber()
    if not bobberGuid then
        GB_Utils.Debug("No bobber GUID stored — skipping loot")
        return
    end
    if SuperWoW_InteractObject then
        SuperWoW_InteractObject(bobberGuid)
    else
        RunMacroText("/target Fishing Bobber\n/interact 1")
    end
    bobberGuid = nil
end

-- ---- Begin a reaction-delay then move to LOOT --------------
-- Simulates the human noticing the bobber splash and clicking.
local function StartReact()
    -- Gaussian reaction time: μ=0.9 s, σ=0.45 s, clamped to [0.25, 2.8]
    local react = GR(0.9, 0.45)
    react = math.max(0.25, math.min(2.8, react))
    reactUntil = GetTime() + react
    SetState(STATE.REACT)
    GB_Utils.Debug(string.format("Reaction delay: %.2f s", react))
end

-- ---- Compute the recast delay for this cycle ---------------
-- Occasional "distracted" pause models the player glancing away.
local function SampleRecastDelay()
    -- Base: Gaussian μ=1.8 s, σ=0.4 s  →  typical 1.0–2.6 s
    local base = GR(1.8, 0.4)
    base = math.max(0.8, math.min(3.5, base))
    -- 4 % chance of a longer "distracted" pause (6–18 s)
    if math.random() < 0.04 then
        base = GI(6, 18)
        GB_Utils.Debug(string.format("Distracted pause: %.1f s", base))
    end
    return base
end

-- ---- Sample per-cast timeout (varies ±8 s around 28 s) -----
local function SampleCastTimeout()
    return math.max(18, math.min(42, GR(castTimeout, 4)))
end

-- ---- State transitions (satisfies forward declaration above) ----
SetState = function(s)
    state     = s
    stateTime = GetTime()
    GB_Utils.Debug("Fishing: → " .. s)
end

-- ---- External entry point ----------------------------------
function GB_Fishing.Start()
    thisCastTimeout = SampleCastTimeout()
    SetState(STATE.EQUIP)
    equipCheck = false
end

function GB_Fishing.Stop()
    SetState(STATE.IDLE)
    SpellStopCasting()
end

function GB_Fishing.IsRunning()
    return state ~= STATE.IDLE
end

-- ---- Main tick — called every ~0.1 s from GromitBot.lua ----
function GB_Fishing.Tick()
    local now = GetTime()

    -- -------- Inventory check (highest priority) -------------
    if state ~= STATE.IDLE and state ~= STATE.CHECK_MAIL then
        if GB_Inventory.ShouldMail() and not GB_Inventory.mailPending then
            GB_Fishing.Stop()
            GB_Inventory.StartAutoMail()
            SetState(STATE.CHECK_MAIL)
            return
        end
    end

    -- -------- State machine ----------------------------------
    if state == STATE.IDLE then
        return

    elseif state == STATE.CHECK_MAIL then
        GB_Inventory.HandleMail()
        if not GB_Inventory.mailPending then
            SetState(STATE.EQUIP)  -- resume fishing after mail
        end

    elseif state == STATE.EQUIP then
        if IsEquippedFishingRod() then
            SetState(STATE.CAST)
        elseif not equipCheck then
            equipCheck = true
            if EquipFishingRod() then
                -- Wait ~1 s for equip animation
                GB_Utils.After(1.0, function()
                    if state == STATE.EQUIP then SetState(STATE.CAST) end
                end)
            else
                SetState(STATE.IDLE)  -- no rod; give up
            end
        end

    elseif state == STATE.CAST then
        if GB_IsCasting and GB_IsCasting() then
            thisCastTimeout = SampleCastTimeout()
            SetState(STATE.WAIT_BOBBER)
        else
            -- Cast fishing
            CastSpellByName("Fishing")
            -- Small Gaussian delay before confirming WAIT_BOBBER
            local castLag = math.max(0.3, math.min(1.2, GR(0.55, 0.15)))
            GB_Utils.After(castLag, function()
                if state == STATE.CAST then
                    thisCastTimeout = SampleCastTimeout()
                    SetState(STATE.WAIT_BOBBER)
                end
            end)
        end

    elseif state == STATE.WAIT_BOBBER then
        -- Timeout: recast if no bite within per-cast timeout
        if now - stateTime > thisCastTimeout then
            GB_Utils.Debug("Cast timeout — recasting")
            SetState(STATE.RECAST_WAIT)
            recastDelay = GetTime() + SampleRecastDelay()
            return
        end
        -- Poll every tick for bobber splash (event-based fallback)
        if IsBobberSplashed() then
            StartReact()   -- add human reaction delay before looting
        end

    elseif state == STATE.REACT then
        -- Wait for reaction delay to elapse, then attempt loot
        if now >= reactUntil then
            -- ~3 % chance of "missed click" — recast instead
            if math.random() < 0.03 and missedClicks < 2 then
                missedClicks = missedClicks + 1
                GB_Utils.Debug("Missed bobber click — recasting")
                SetState(STATE.RECAST_WAIT)
                recastDelay = GetTime() + math.max(0.5, GR(0.9, 0.2))
            else
                missedClicks = 0
                SetState(STATE.LOOT)
            end
        end

    elseif state == STATE.LOOT then
        LootBobber()
        -- AutoLoot is handled by LOOT_OPENED in GromitBot.lua.
        SetState(STATE.RECAST_WAIT)
        recastDelay = GetTime() + SampleRecastDelay()

    elseif state == STATE.RECAST_WAIT then
        if now >= recastDelay then
            equipCheck = false
            SetState(STATE.EQUIP)          -- re-check rod each cycle
        end
    end
end

-- ---- UNIT_SPELLCAST_SUCCEEDED hook -------------------------
-- Triggered when fishing cast lands (CLEU or UNIT_SPELLCAST_*)
function GB_Fishing.OnSpellCast(spellName)
    if spellName == "Fishing" and state == STATE.CAST then
        SetState(STATE.WAIT_BOBBER)
    end
end

-- ---- BOBBER_SPLASH event (SuperWoW custom event) -----------
function GB_Fishing.OnBobberSplash(guid)
    if state == STATE.WAIT_BOBBER then
        bobberGuid = guid
        StartReact()   -- reaction delay before loot
    end
end
