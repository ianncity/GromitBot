-- ============================================================
-- command_poller.lua
-- Polls a local command file (written by the Python agent)
-- every 1 second and executes commands.
--
-- File format (one command per line, consumed and cleared):
--   COMMAND [args...]
--
-- Supported commands:
--   DISCONNECT          — leave game (/quit)
--   JUMP                — player jumps once
--   SAY <text>          — say text in /say
--   STOP                — stop the active bot
--   START               — start the configured bot
--   MODE fishing|herbalism|leveling — switch bot mode
--   PROFILE <name>      — load/hot-swap a leveling profile
--   PROFILES            — print available profiles to chat
--   MAIL                — trigger auto-mail immediately
--   STATUS              — write status JSON to response file
--   POSITION            — write status JSON with fresh world-map coordinates
--   PRINT <text>        — print text to chat frame
--   RELOAD              — ReloadUI()
-- ============================================================

GB_CmdPoller = {}

local POLL_INTERVAL = 1.0          -- seconds
local lastPoll      = 0
local CMD_FILE      = nil          -- set from config on init
local STATUS_FILE   = nil          -- same path + ".status"

-- SuperWoW provides file I/O via LoadFile / WriteFile
-- (non-standard Lua functions unlocked by SuperWoW).
local function ReadFile(path)
    if ReadFile_SWoW then return ReadFile_SWoW(path) end   -- SuperWoW
    if io then                                              -- dev/debug
        local f = io.open(path, "r")
        if f then local s = f:read("*a"); f:close(); return s end
    end
    return nil
end

local function WriteFile(path, content)
    if WriteFile_SWoW then WriteFile_SWoW(path, content); return end
    if io then
        local f = io.open(path, "w")
        if f then f:write(content); f:close() end
    end
end

-- ---- Get 0-1 world-map coordinates ----------------------------
local function GetWorldMapCoords()
    -- Save current map state so we can restore it afterwards
    local savedContinent = GetCurrentMapContinent()
    local savedZone      = GetCurrentMapZone()

    local x, y
    -- pcall guards against unexpected API behaviour in edge cases
    local ok = pcall(function()
        -- continent 0 = full world (Azeroth) view in WoW 1.12
        SetMapZoom(0)
        x, y = GetPlayerMapPosition("player")
    end)

    -- Restore previous map zoom; fall back to SetMapToCurrentZone on failure
    local restored = pcall(function()
        if savedContinent and savedContinent >= 0 then
            SetMapZoom(savedContinent, savedZone)
        else
            SetMapToCurrentZone()
        end
    end)
    if not restored then
        pcall(SetMapToCurrentZone)
    end

    if ok and x and y then
        return x, y
    end
    return nil, nil
end

-- ---- Build status JSON string ------------------------------
local function BuildStatusJSON()
    local cfg    = GromitBot_GetConfig()
    local player = UnitName("player") or "Unknown"
    local zone   = GetZoneText() or "Unknown"
    local hp, maxhp = 0, 0
    if GB_GetPlayerHealth then hp, maxhp = GB_GetPlayerHealth() end
    local _, freeSlots = GB_Inventory.GetSlotCounts()
    local fullPct      = GB_Inventory.GetFullnessPct()
    local mode         = cfg.mode or "unknown"
    local running      = false
    if mode == "fishing"   and GB_Fishing   then running = GB_Fishing.IsRunning()   end
    if mode == "herbalism" and GB_Herbalism then running = GB_Herbalism.IsRunning() end
    if mode == "leveling"  and GB_Leveling  then running = GB_Leveling.IsRunning()  end

    local plevel = UnitLevel("player") or 0
    local activeProfile = GB_Profiles and GB_Profiles.Active()
    local profileName   = (activeProfile and activeProfile.name) or ""

    -- World-map position (0-1 fractions); may be nil if unavailable
    local mapX, mapY = GetWorldMapCoords()
    local mapFields = ""
    if mapX and mapY then
        mapFields = string.format(',"mapX":%.4f,"mapY":%.4f', mapX, mapY)
    end

    return string.format(
        '{"player":"%s","name":"%s","zone":"%s","mode":"%s","running":%s,'
        .. '"hp":%d,"maxhp":%d,"bagFull":%.1f,"freeSlots":%d,'
        .. '"level":%d,"profile":"%s","time":%.0f%s}',
        player, player, zone, mode, running and "true" or "false",
        hp, maxhp, fullPct, freeSlots,
        plevel, profileName, GetTime(), mapFields
    )
end

-- ---- Execute a single command line -------------------------
local function ExecuteCommand(line)
    line = GB_Utils.Trim(line)
    if line == "" or line:sub(1, 1) == "#" then return end

    local cmd, args = line:match("^(%S+)%s*(.*)")
    cmd = cmd and cmd:upper() or ""

    GB_Utils.Debug("[CMD] " .. cmd .. " " .. (args or ""))

    if cmd == "DISCONNECT" then
        GB_Utils.Print("Disconnect command received — leaving game")
        Quit()

    elseif cmd == "JUMP" then
        JumpOrAscendStart()
        GB_Utils.After(0.1, function() JumpOrAscendStop() end)

    elseif cmd == "SAY" then
        if args and args ~= "" then
            SendChatMessage(args, "SAY")
        end

    elseif cmd == "WHISPER" then
        -- WHISPER TargetName message...
        local target, msg = args:match("^(%S+)%s+(.*)")
        if target and msg then
            SendChatMessage(msg, "WHISPER", nil, target)
        end

    elseif cmd == "STOP" then
        if GB_Fishing   then GB_Fishing.Stop()   end
        if GB_Herbalism then GB_Herbalism.Stop() end
        if GB_Leveling  then GB_Leveling.Stop()  end
        GB_Utils.Print("Bot stopped by remote command.")

    elseif cmd == "START" then
        local cfg = GromitBot_GetConfig()
        if cfg.mode == "fishing"   then GB_Fishing.Start()  end
        if cfg.mode == "herbalism" then GB_Herbalism.Start() end
        if cfg.mode == "leveling"  then
            local p = GB_Profiles and GB_Profiles.Active()
            if p then
                GB_Leveling.Start()
            else
                GB_Utils.Print("Leveling mode: no profile loaded. Send PROFILE <name> first.")
            end
        end
        GB_Utils.Print("Bot started by remote command.")

    elseif cmd == "MODE" then
        local newMode = args and args:lower() or ""
        if newMode == "fishing" or newMode == "herbalism" or newMode == "leveling" then
            GromitBotConfig.mode = newMode
            if GB_Fishing   then GB_Fishing.Stop()   end
            if GB_Herbalism then GB_Herbalism.Stop() end
            if GB_Leveling  then GB_Leveling.Stop()  end
            GB_Utils.Print("Mode set to " .. newMode)
        else
            GB_Utils.Print("Unknown mode: " .. newMode)
        end

    elseif cmd == "PROFILE" then
        local name = args and GB_Utils.Trim(args) or ""
        if name == "" then
            local p = GB_Profiles and GB_Profiles.Active()
            GB_Utils.Print("Active: " .. (p and p.name or "none"))
            GB_Utils.Print("Available: " .. (GB_Profiles and GB_Profiles.ListNames() or "?"))
        elseif GB_Leveling and GB_Leveling.IsRunning() then
            if GB_Leveling.SwapProfile(name) then
                GromitBotConfig.mode = "leveling"
                GromitBotConfig.levelingProfile = name
            end
        else
            if GB_Profiles and GB_Profiles.Load(name) then
                GromitBotConfig.mode = "leveling"
                GromitBotConfig.levelingProfile = name
            end
        end

    elseif cmd == "PROFILES" then
        GB_Utils.Print("Available profiles: " .. (GB_Profiles and GB_Profiles.ListNames() or "none"))

    elseif cmd == "MAIL" then
        GB_Inventory.StartAutoMail()

    elseif cmd == "STATUS" then
        if STATUS_FILE then
            WriteFile(STATUS_FILE, BuildStatusJSON())
        end

    elseif cmd == "POSITION" then
        -- Force an immediate status write with fresh world-map coordinates
        if STATUS_FILE then
            WriteFile(STATUS_FILE, BuildStatusJSON())
        end

    elseif cmd == "PRINT" then
        GB_Utils.Print(args or "")

    elseif cmd == "RELOAD" then
        ReloadUI()

    elseif cmd == "EMOTE" then
        DoEmote(args or "")

    elseif cmd == "SIT" then
        DoEmote("SIT")

    elseif cmd == "STAND" then
        DoEmote("STAND")

    else
        GB_Utils.Debug("Unknown command: " .. cmd)
    end
end

-- ---- Poll tick ---------------------------------------------
function GB_CmdPoller.Tick()
    local now = GetTime()
    if now - lastPoll < POLL_INTERVAL then return end
    lastPoll = now

    if not CMD_FILE then return end

    local content = ReadFile(CMD_FILE)
    if not content or content == "" then return end

    -- Clear the file immediately to avoid replaying
    WriteFile(CMD_FILE, "")

    -- Process each line
    for line in content:gmatch("[^\r\n]+") do
        local ok, err = pcall(ExecuteCommand, line)
        if not ok then
            GB_Utils.Debug("Command error: " .. tostring(err))
        end
    end
end

-- ---- Periodic status write (every 5 s) ---------------------
local lastStatusWrite = 0
function GB_CmdPoller.WriteStatus()
    local now = GetTime()
    if now - lastStatusWrite < 5 then return end
    lastStatusWrite = now
    if STATUS_FILE then
        local ok, err = pcall(function()
            WriteFile(STATUS_FILE, BuildStatusJSON())
        end)
        if not ok then GB_Utils.Debug("Status write error: " .. tostring(err)) end
    end
end

-- ---- Init --------------------------------------------------
function GB_CmdPoller.Init()
    local cfg = GromitBot_GetConfig()
    CMD_FILE    = cfg.commandFilePath or "C:\\GromitBot\\command.txt"
    STATUS_FILE = CMD_FILE:gsub("%.txt$", "") .. "_status.json"
    GB_Utils.Debug("CmdPoller: watching " .. CMD_FILE)
end
