-- ============================================================
-- chat_listener.lua — Intercepts whispers and /say messages,
-- queries Ollama, replies with human-like delay.
-- ============================================================

GB_Chat = {}

-- Track per-sender say message counts this session
local sayCounts   = {}  -- { [name] = count }
local pendingReply = {}  -- { [name] = { type, text } }  waiting for Ollama

-- ---- Rate limiting -----------------------------------------
local lastReplyTime = {}  -- { [name] = GetTime() }
local REPLY_COOLDOWN = 8  -- seconds between replies to same person

-- ---- Build the full Ollama prompt --------------------------
local function BuildPrompt(msgType, senderName, text)
    local cfg = GromitBot_GetConfig()
    local ctx = ""
    if msgType == "SAY" then
        ctx = string.format('A player named %s says in /say chat: "%s"', senderName, text)
    else
        ctx = string.format('A player named %s whispers to you: "%s"', senderName, text)
    end
    return ctx
end

-- ---- Should we respond to this sender? ---------------------
local function ShouldReply(msgType, senderName, x, y, z)
    local cfg = GromitBot_GetConfig()

    if msgType == "WHISPER" then
        return true  -- always reply to whispers
    end

    -- SAY: only if in range AND sufficient messages
    local cnt = sayCounts[senderName] or 0
    if cnt < cfg.chatReplyMinSayMessages then
        GB_Utils.Debug(senderName .. " SAY count " .. cnt .. " < min — ignoring")
        return false
    end

    -- Range check
    local px, py, pz = 0, 0, 0
    if GB_GetPlayerPos then px, py, pz = GB_GetPlayerPos() end

    -- For SAY we need sender position — use UnitPosition(unit) where unit = target
    -- This only works if the sender is in our object manager.
    -- Heuristic: check if they are within chatReplySayRange via last known pos
    -- (populated by seeing them in object manager).
    local dist = cfg.chatReplySayRange  -- default: assume in range if we can't check
    if x and y then
        dist = GB_Utils.Dist2D(px, py, x, y)
    end

    return dist <= cfg.chatReplySayRange
end

-- ---- Send the Ollama request (synchronous inside WoW thread)
-- NOTE: GB_OllamaSend is a *blocking* call added by the C++ DLL.
-- We wrap it in a C_Timer-like After() to avoid hitching the frame.
local function QueryOllamaAndReply(msgType, senderName, text)
    local cfg = GromitBot_GetConfig()

    -- Human-like delay: 2–4 seconds (simulate typing)
    local replyDelay = GB_Utils.RandFloat(2.0, 4.0)

    GB_Utils.After(replyDelay, function()
        if not GB_OllamaSend then
            GB_Utils.Debug("GB_OllamaSend not available (DLL not loaded)")
            return
        end
        local prompt = BuildPrompt(msgType, senderName, text)
        local response, err = GB_OllamaSend(
            cfg.ollamaModel,
            cfg.ollamaPersona,
            prompt
        )
        if not response then
            GB_Utils.Debug("Ollama error: " .. (err or "unknown"))
            return
        end

        -- Trim and sanitise response
        response = GB_Utils.Trim(response)
        response = GB_Utils.WrapText(response, 255)  -- WoW chat limit

        -- Send reply
        if msgType == "WHISPER" then
            SendChatMessage(response, "WHISPER", nil, senderName)
        else
            -- Reply in /say (or yell if say was yelled — keep say)
            SendChatMessage(response, "SAY")
        end

        lastReplyTime[senderName] = GetTime()
        GB_Utils.Debug("Replied to " .. senderName .. ": " .. response)
    end)
end

-- ---- Main event handler (registered in GromitBot.lua) ------
function GB_Chat.OnChatMessage(msgType, text, language, channelName,
                                playerName, minimap, zone, channelNum,
                                channelName2, unused, lineId, guid)
    -- Strip realm name from playerName (e.g. "Name-TurtleWoW" → "Name")
    local senderName = playerName and playerName:match("^([^%-]+)") or playerName
    if not senderName or senderName == "" then return end

    -- Ignore own messages
    local myName = UnitName("player")
    if senderName == myName then return end

    -- Only handle SAY and WHISPER
    if msgType ~= "CHAT_MSG_SAY" and msgType ~= "CHAT_MSG_WHISPER" then return end

    local isWhisper = (msgType == "CHAT_MSG_WHISPER")
    local simpleMsgType = isWhisper and "WHISPER" or "SAY"

    -- Track say counts
    if not isWhisper then
        sayCounts[senderName] = (sayCounts[senderName] or 0) + 1
    end

    -- Cooldown check
    local last = lastReplyTime[senderName] or 0
    if GetTime() - last < REPLY_COOLDOWN then
        GB_Utils.Debug("Cooldown active for " .. senderName)
        return
    end

    if not ShouldReply(simpleMsgType, senderName, nil, nil, nil) then return end

    GB_Utils.Debug("Chat from " .. senderName .. " [" .. simpleMsgType .. "]: " .. text)
    QueryOllamaAndReply(simpleMsgType, senderName, text)
end

-- Reset session counts (call on login)
function GB_Chat.Reset()
    sayCounts      = {}
    lastReplyTime  = {}
end
