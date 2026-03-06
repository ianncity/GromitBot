-- ============================================================
-- inventory.lua — Bag fullness tracking and auto-mail system
-- ============================================================

GB_Inventory = {}

-- ---- Count total and free bag slots ------------------------
-- Bags: 0 = backpack (16 slots), 1-4 = equipped bags
function GB_Inventory.GetSlotCounts()
    local total = 0
    local free  = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            total = total + numSlots
            free  = free  + GetContainerNumFreeSlots(bag)
        end
    end
    return total, free
end

-- Returns fullness percent (0-100).
function GB_Inventory.GetFullnessPct()
    local total, free = GB_Inventory.GetSlotCounts()
    if total == 0 then return 0 end
    return GB_Utils.Round((total - free) / total * 100, 1)
end

-- Returns true when we should trigger auto-mail.
function GB_Inventory.ShouldMail()
    local cfg = GromitBot_GetConfig()
    return GB_Inventory.GetFullnessPct() >= cfg.mailThreshold
end

-- ============================================================
-- Auto-mail system
-- Opens the mailbox, addresses the mail, attaches all items
-- that are not soulbound/equipped, sends, then closes.
--
-- Requires the player to be standing at a mailbox and have
-- already right-clicked it (MAIL_SHOW event fires).
-- ============================================================

local MAIL_STATE_IDLE    = 0
local MAIL_STATE_WAIT    = 1  -- waiting for mailbox open
local MAIL_STATE_ATTACH  = 2  -- attaching items
local MAIL_STATE_SEND    = 3  -- clicking Send
local MAIL_STATE_DONE    = 4

GB_Inventory.mailState   = MAIL_STATE_IDLE
GB_Inventory.mailPending = false

local attachedSlots = {}   -- {bag, slot} pairs queued for attachment
local attachIdx     = 0
local sendDelay     = 0

-- Items to skip (keep on player)
local KEEP_ITEMS = GB_Utils.Set({
    -- Add item names that should never be mailed if desired
})

-- Soulbound check — we can only detect via itemLink quality/name
-- A simpler heuristic: skip equipped items and fishing rod.
local function ShouldMailItem(bag, slot)
    local texture, count, _, quality = GetContainerItemInfo(bag, slot)
    if not texture then return false end
    -- Never mail quest items (quality = 5 in 1.12 is artifact, 4 = epic…)
    -- Quest items have no auction value; simplest filter: skip grey (0)
    -- and items in KEEP_ITEMS set by name.
    local link = GetContainerItemLink(bag, slot)
    if not link then return false end
    local name = link:match("%[(.-)%]")
    if name and KEEP_ITEMS[name] then return false end
    return true
end

local function CollectMailableItems()
    attachedSlots = {}
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, (numSlots or 0) do
            if ShouldMailItem(bag, slot) then
                table.insert(attachedSlots, { bag = bag, slot = slot })
            end
        end
    end
end

-- Start the mail process — call when player is at mailbox.
function GB_Inventory.StartAutoMail()
    if GB_Inventory.mailState ~= MAIL_STATE_IDLE then return end
    local cfg = GromitBot_GetConfig()
    GB_Utils.Print("Bags at " .. GB_Inventory.GetFullnessPct() .. "% — starting auto-mail to " .. cfg.mailTarget)
    GB_Inventory.mailState   = MAIL_STATE_WAIT
    GB_Inventory.mailPending = true
    -- The actual mailbox interaction happens in HandleMail() called by events
end

-- Called each frame / on appropriate events.
function GB_Inventory.HandleMail()
    local cfg = GromitBot_GetConfig()
    local state = GB_Inventory.mailState

    if state == MAIL_STATE_WAIT then
        -- Wait for SendMailFrame to be visible (player opened mailbox)
        if SendMailFrame and SendMailFrame:IsShown() then
            CollectMailableItems()
            attachIdx = 0
            -- Pre-fill recipient and subject
            SendMailNameEditBox:SetText(cfg.mailTarget)
            SendMailSubjectEditBox:SetText("GromitBot Loot")
            GB_Inventory.mailState = MAIL_STATE_ATTACH
        end

    elseif state == MAIL_STATE_ATTACH then
        -- Attach one item per HandleMail call (WoW rate-limits CClickItem)
        attachIdx = attachIdx + 1
        if attachIdx > #attachedSlots then
            GB_Inventory.mailState = MAIL_STATE_SEND
            sendDelay = GetTime() + 0.5  -- short pause before send
            return
        end
        local slot = attachedSlots[attachIdx]
        -- PickupContainerItem + DropItemOnUnit doesn't work for mail;
        -- instead we use ClickItemButton which attaches to mail frame.
        local btn = getglobal("SendMailAttachment" .. (attachIdx))
        if btn then
            PickupContainerItem(slot.bag, slot.slot)
            ClickSendMailItemButton()
        end

    elseif state == MAIL_STATE_SEND then
        if GetTime() >= sendDelay then
            SendMail()
            GB_Inventory.mailState = MAIL_STATE_DONE
        end

    elseif state == MAIL_STATE_DONE then
        CloseMail()
        GB_Inventory.mailState   = MAIL_STATE_IDLE
        GB_Inventory.mailPending = false
        GB_Utils.Print("Auto-mail complete.")
    end
end

-- Reset if mail window closed unexpectedly
function GB_Inventory.OnMailClosed()
    if GB_Inventory.mailState ~= MAIL_STATE_DONE then
        GB_Inventory.mailState   = MAIL_STATE_IDLE
        GB_Inventory.mailPending = false
    end
end
