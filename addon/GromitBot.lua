-- ============================================================
-- GromitBot.lua — Main addon entry point
-- Handles event registration, master OnUpdate tick, and slash
-- commands.
-- ============================================================

-- ---- Version -----------------------------------------------
GROMITBOT_VERSION = "1.1.0"

-- ---- Master frame ------------------------------------------
local masterFrame = CreateFrame("Frame", "GromitBotFrame", UIParent)
masterFrame:RegisterEvent("VARIABLES_LOADED")
masterFrame:RegisterEvent("PLAYER_LOGIN")
masterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
masterFrame:RegisterEvent("LOOT_OPENED")
masterFrame:RegisterEvent("LOOT_CLOSED")
masterFrame:RegisterEvent("MAIL_SHOW")
masterFrame:RegisterEvent("MAIL_CLOSED")
masterFrame:RegisterEvent("MAIL_SEND_SUCCESS")
masterFrame:RegisterEvent("CHAT_MSG_SAY")
masterFrame:RegisterEvent("CHAT_MSG_WHISPER")
masterFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
masterFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- enter combat
masterFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leave combat
masterFrame:RegisterEvent("UNIT_DIED")
-- SuperWoW custom events
masterFrame:RegisterEvent("BOBBER_SPLASH")    -- fishing bobber event (SuperWoW)
masterFrame:RegisterEvent("SUPERWOW_LOOT")    -- auto-loot (SuperWoW)

-- ---- Tick intervals ----------------------------------------
local TICK_BOT    = 0.1   -- bot state machine
local TICK_HUMAN  = 0.5   -- human behaviour
local TICK_CMD    = 1.0   -- command poller
local TICK_STATUS = 5.0   -- status file write

local lastTickBot    = 0
local lastTickHuman  = 0
local lastTickCmd    = 0
local lastTickStatus = 0
local initialized    = false

-- ---- OnUpdate master dispatcher ----------------------------
masterFrame:SetScript("OnUpdate", function()
    if not initialized then return end
    local now = GetTime()

    if now - lastTickBot >= TICK_BOT then
        lastTickBot = now
        local cfg = GromitBot_GetConfig()
        if cfg.mode == "fishing"   and GB_Fishing   then GB_Fishing.Tick()   end
        if cfg.mode == "herbalism" and GB_Herbalism then GB_Herbalism.Tick() end
        if cfg.mode == "leveling"  and GB_Leveling  then GB_Leveling.Tick()  end
    end

    if now - lastTickHuman >= TICK_HUMAN then
        lastTickHuman = now
        if GB_Human then GB_Human.Tick() end
    end

    if now - lastTickCmd >= TICK_CMD then
        lastTickCmd = now
        if GB_CmdPoller then GB_CmdPoller.Tick() end
    end

    if now - lastTickStatus >= TICK_STATUS then
        lastTickStatus = now
        if GB_CmdPoller then GB_CmdPoller.WriteStatus() end
    end
end)

-- ---- Event dispatcher --------------------------------------
masterFrame:SetScript("OnEvent", function()
    local evt = event     -- WoW 1.12 uses global `event`

    -- ---- Init events ----------------------------------------
    if evt == "VARIABLES_LOADED" or evt == "PLAYER_LOGIN" then
        GromitBot_LoadConfig()
        GB_Chat.Reset()
        GB_CmdPoller.Init()
        -- Auto-load leveling profile from config if set
        local cfg = GromitBot_GetConfig()
        if cfg.levelingProfile and cfg.levelingProfile ~= "" then
            GB_Profiles.Load(cfg.levelingProfile)
        end
        initialized = true
        GB_Utils.Print("GromitBot v" .. GROMITBOT_VERSION .. " loaded. Mode: "
            .. (GromitBotConfig.mode or "?")
            .. " | /gbot start|stop|mode|profile|help")

    elseif evt == "PLAYER_ENTERING_WORLD" then
        -- Re-set home whenever we enter world
        GB_Human.SetHome()

    -- ---- Loot events ----------------------------------------
    elseif evt == "LOOT_OPENED" then
        -- Auto-loot all slots (works for both fishing and herbalism)
        for i = 1, GetNumLootItems() do
            LootSlot(i)
        end
        if GB_Herbalism then GB_Herbalism.OnLootOpened() end
        if GB_Leveling  then GB_Leveling.OnLootOpened()  end

    elseif evt == "LOOT_CLOSED" then
        -- nothing

    -- ---- Mail events ----------------------------------------
    elseif evt == "MAIL_SHOW" then
        if GB_Inventory.mailPending then
            GB_Inventory.mailState = 1  -- MAIL_STATE_WAIT → advance to ATTACH
        end

    elseif evt == "MAIL_CLOSED" then
        GB_Inventory.OnMailClosed()

    elseif evt == "MAIL_SEND_SUCCESS" then
        GB_Utils.Debug("Mail sent successfully.")

    -- ---- Chat events ----------------------------------------
    elseif evt == "CHAT_MSG_SAY" or evt == "CHAT_MSG_WHISPER" then
        -- WoW 1.12 passes args as: arg1=msg, arg2=author, ...
        GB_Chat.OnChatMessage(evt, arg1, arg2, arg3, arg4, arg5,
                               arg6, arg7, arg8, arg9, arg10, arg11, arg12)

    -- ---- Spell cast events ----------------------------------
    elseif evt == "UNIT_SPELLCAST_SUCCEEDED" then
        -- arg1 = unit, arg2 = spellName
        if arg1 == "player" and GB_Fishing then
            GB_Fishing.OnSpellCast(arg2)
        end

    -- ---- Combat events (leveling) ---------------------------
    elseif evt == "PLAYER_REGEN_DISABLED" then
        if GB_Herbalism then GB_Herbalism.OnEnterCombat() end
        if GB_Leveling  then GB_Leveling.OnEnterCombat()  end

    elseif evt == "PLAYER_REGEN_ENABLED" then
        -- Left combat — leveling bot checks rest in its next tick

    elseif evt == "UNIT_DIED" then
        -- arg1 = unit token ("target", "player", etc.)
        if GB_Leveling then GB_Leveling.OnUnitDied(arg1) end

    -- ---- SuperWoW custom events ----------------------------
    elseif evt == "BOBBER_SPLASH" then
        -- arg1 = bobber GUID (provided by SuperWoW)
        if GB_Fishing then
            GB_Fishing.OnBobberSplash(arg1)
        end
    end
end)

-- ============================================================
-- Slash commands: /gbot or /gromitbot
-- ============================================================
SLASH_GROMITBOT1 = "/gbot"
SLASH_GROMITBOT2 = "/gromitbot"

SlashCmdList["GROMITBOT"] = function(msg)
    local cmd, args = msg:match("^(%S+)%s*(.*)")
    cmd = cmd and cmd:lower() or ""

    if cmd == "start" then
        local cfg = GromitBot_GetConfig()
        if GB_Human.IsOnBreak() then
            GB_Utils.Print("Bot is on an AFK break — use /gbot breakstop to cancel.")
            return
        end
        GB_Human.SetHome()
        if cfg.mode == "fishing" then
            GB_Fishing.Start()
            GB_Utils.Print("Fishing bot started.")
        elseif cfg.mode == "herbalism" then
            GB_Herbalism.Start()
            GB_Utils.Print("Herbalism bot started.")
        elseif cfg.mode == "leveling" then
            local profile = GB_Profiles.Active()
            if not profile then
                GB_Utils.Print("No profile loaded. Use /gbot profile <name> first.")
                GB_Utils.Print("Available: " .. GB_Profiles.ListNames())
            else
                GB_Leveling.Start()
                GB_Utils.Print("Leveling bot started with profile: " .. profile.name)
            end
        else
            GB_Utils.Print("Unknown mode: " .. (cfg.mode or "nil"))
        end

    elseif cmd == "breakstop" then
        -- Force-cancel an active AFK break
        if GB_Human.IsOnBreak() then
            GB_Human.CancelBreak()
            GB_Utils.Print("AFK break cancelled.")
        else
            GB_Utils.Print("Not currently on a break.")
        end

    elseif cmd == "stop" then
        if GB_Fishing   then GB_Fishing.Stop()   end
        if GB_Herbalism then GB_Herbalism.Stop() end
        if GB_Leveling  then GB_Leveling.Stop()  end
        GB_Utils.Print("Bot stopped.")

    elseif cmd == "mode" then
        local newMode = args and args:lower() or ""
        if newMode == "fishing" or newMode == "herbalism" or newMode == "leveling" then
            GromitBotConfig.mode = newMode
            GB_Utils.Print("Mode set to " .. newMode .. ". Type /gbot start to begin.")
        else
            GB_Utils.Print("Usage: /gbot mode fishing|herbalism|leveling")
        end

    elseif cmd == "profile" then
        -- Load (and optionally hot-swap) a leveling profile
        local name = args and GB_Utils.Trim(args) or ""
        if name == "" then
            local active = GB_Profiles.Active()
            if active then
                GB_Utils.Print("Active profile: " .. active.name)
            else
                GB_Utils.Print("No profile active.")
            end
            GB_Utils.Print("Available: " .. GB_Profiles.ListNames())
        elseif GB_Leveling and GB_Leveling.IsRunning() then
            -- Hot-swap while running
            if GB_Leveling.SwapProfile(name) then
                GromitBotConfig.mode = "leveling"
                GromitBotConfig.levelingProfile = name
            end
        else
            if GB_Profiles.Load(name) then
                GromitBotConfig.mode = "leveling"
                GromitBotConfig.levelingProfile = name
                GB_Utils.Print("Profile set. Type /gbot start to begin.")
            end
        end

    elseif cmd == "profiles" then
        GB_Utils.Print("Available profiles: " .. GB_Profiles.ListNames())

    elseif cmd == "mail" then
        GB_Inventory.StartAutoMail()
        GB_Utils.Print("Auto-mail triggered.")

    elseif cmd == "status" then
        local cfg  = GromitBot_GetConfig()
        local t, f = GB_Inventory.GetSlotCounts()
        GB_Utils.Print(string.format(
            "Mode: %s | Bags: %d/%d (%.0f%%) | MailTarget: %s",
            cfg.mode, t - f, t, GB_Inventory.GetFullnessPct(), cfg.mailTarget
        ))

    elseif cmd == "debug" then
        GromitBotConfig.debug = not GromitBotConfig.debug
        GB_Utils.Print("Debug " .. (GromitBotConfig.debug and "ON" or "OFF"))

    elseif cmd == "reload" then
        ReloadUI()

    elseif cmd == "home" then
        GB_Human.SetHome()
        GB_Utils.Print("Home position updated.")

    elseif cmd == "help" or cmd == "" then
        GB_Utils.Print("--- GromitBot v" .. GROMITBOT_VERSION .. " ---")
        GB_Utils.Print("/gbot start              — start configured bot mode")
        GB_Utils.Print("/gbot stop               — stop bot")
        GB_Utils.Print("/gbot mode fishing       — switch to fishing mode")
        GB_Utils.Print("/gbot mode herbalism     — switch to herbalism mode")
        GB_Utils.Print("/gbot mode leveling      — switch to leveling mode")
        GB_Utils.Print("/gbot profile <name>     — load/hot-swap a leveling profile")
        GB_Utils.Print("/gbot profiles           — list all available profiles")
        GB_Utils.Print("/gbot mail               — send bags to mailTarget now")
        GB_Utils.Print("/gbot status             — show bag/mode status")
        GB_Utils.Print("/gbot debug              — toggle debug messages")
        GB_Utils.Print("/gbot home               — update home position")
        GB_Utils.Print("/gbot breakstop          — cancel active AFK break")
    else
        GB_Utils.Print("Unknown command. Type /gbot help")
    end
end
