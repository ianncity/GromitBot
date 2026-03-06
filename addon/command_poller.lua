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
--   MODE fishing|herbalism — switch bot mode
--   MAIL                — trigger auto-mail immediately
--   STATUS              — write status JSON to response file
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

    return string.format(
        '{"player":"%s","zone":"%s","mode":"%s","running":%s,'
        .. '"hp":%d,"maxhp":%d,"bagFull":%.1f,"freeSlots":%d,"time":%.0f}',
        player, zone, mode, running and "true" or "false",
        hp, maxhp, fullPct, freeSlots, GetTime()
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
        GB_Utils.Print("Bot stopped by remote command.")

    elseif cmd == "START" then
        local cfg = GromitBot_GetConfig()
        if cfg.mode == "fishing"   then GB_Fishing.Start()   end
        if cfg.mode == "herbalism" then GB_Herbalism.Start() end
        GB_Utils.Print("Bot started by remote command.")

    elseif cmd == "MODE" then
        local newMode = args and args:lower() or ""
        if newMode == "fishing" or newMode == "herbalism" then
            GromitBotConfig.mode = newMode
            -- Stop active bot first
            if GB_Fishing   then GB_Fishing.Stop()   end
            if GB_Herbalism then GB_Herbalism.Stop() end
            GB_Utils.Print("Mode set to " .. newMode)
        end

    elseif cmd == "MAIL" then
        GB_Inventory.StartAutoMail()

    elseif cmd == "STATUS" then
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
