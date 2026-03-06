-- ============================================================
-- fishing.lua — Full fishing bot state machine
-- ============================================================
--
-- States:
--   IDLE        → wait for bot to be enabled
--   EQUIP       → equip fishing rod if not already equipped
--   CAST        → cast Fishing spell
--   WAIT_BOBBER → wait for bobber splash (dynamic flag OR polling)
--   LOOT        → right-click bobber to loot
--   RECAST_WAIT → randomized 1.0–1.5 s delay before recasting
--   CHECK_MAIL  → bags full, find/open mailbox, mail items
-- ============================================================

GB_Fishing = {}

local STATE = {
    IDLE        = "IDLE",
    EQUIP       = "EQUIP",
    CAST        = "CAST",
    WAIT_BOBBER = "WAIT_BOBBER",
    LOOT        = "LOOT",
    RECAST_WAIT = "RECAST_WAIT",
    CHECK_MAIL  = "CHECK_MAIL",
}

local state       = STATE.IDLE
local stateTime   = 0           -- time we entered current state
local recastDelay = 0
local bobberGuid  = nil
local castTimeout = 30          -- seconds to wait for a bite before recasting
local equipCheck  = false

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
    -- SuperWoW exposes InteractUnit / ObjectManager interaction
    -- Use Lua's built-in /script approach via RunScript is unavailable,
    -- so we use the SuperWoW targeting API.
    if SuperWoW_InteractObject then
        SuperWoW_InteractObject(bobberGuid)
    else
        -- Fall back: use target + interact macro text
        RunMacroText("/target Fishing Bobber\n/interact 1")
    end
    bobberGuid = nil
end

-- ---- State transitions -------------------------------------
local function SetState(s)
    state     = s
    stateTime = GetTime()
    GB_Utils.Debug("Fishing: → " .. s)
end

-- ---- External entry point ----------------------------------
function GB_Fishing.Start()
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
            SetState(STATE.WAIT_BOBBER)
        else
            -- Cast fishing
            CastSpellByName("Fishing")
            GB_Utils.After(0.5, function()
                if state == STATE.CAST then SetState(STATE.WAIT_BOBBER) end
            end)
        end

    elseif state == STATE.WAIT_BOBBER then
        -- Timeout: recast if no bite after castTimeout seconds
        if now - stateTime > castTimeout then
            GB_Utils.Debug("Cast timeout — recasting")
            SetState(STATE.RECAST_WAIT)
            recastDelay = GetTime() + GB_Utils.RandFloat(1.0, 1.5)
            return
        end
        -- Poll every tick for bobber splash (event-based fallback)
        if IsBobberSplashed() then
            SetState(STATE.LOOT)
        end

    elseif state == STATE.LOOT then
        LootBobber()
        -- AutoLoot is handled by the LOOT_OPENED / LOOT_SLOT_CHANGED events
        -- in GromitBot.lua main frame handler.
        -- After a brief moment, set up recast
        SetState(STATE.RECAST_WAIT)
        recastDelay = GetTime() + GB_Utils.RandFloat(1.0, 1.5)

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
        SetState(STATE.LOOT)
    end
end
