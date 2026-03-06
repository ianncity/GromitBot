-- ============================================================
-- chat_listener.lua — Intercepts whispers and /say messages,
-- queries Ollama, replies with human-like delay.
-- Anti-detection: GM name / keyword detection stops the bot
-- immediately and crafts a confused, innocent-sounding reply.
-- ============================================================

GB_Chat = {}

-- Track per-sender say message counts this session
local sayCounts = {}    -- { [name] = count }

-- Track how many times we have replied to each sender this session
local replyCounts = {}  -- { [name] = count }

-- ---- Typing-pause state -----------------------------------
-- Set to true from the moment a reply is triggered until a short
-- period after the message is sent, so the character stands still
-- while "composing" — exactly as a real player would.
local isTyping = false

function GB_Chat.IsTyping()
    return isTyping
end

-- Cancel CTM and all movement keys so the character freezes in place.
local function StopAllMovement()
    MoveForwardStop()
    MoveBackwardStop()
    StrafeLeftStop()
    StrafeRightStop()
    if MoveToPosition then MoveToPosition(0, 0, 0, 0) end
end

-- ---- Rate limiting -----------------------------------------
local lastReplyTime  = {}  -- { [name] = GetTime() }
local REPLY_COOLDOWN = 8   -- seconds between replies to same person

-- ---- GM canned responses (chosen randomly) ----------------
local GM_RESPONSES = {
    "Oh hey! Sorry, I was a bit distracted — what's up?",
    "Haha sorry, was just zoning out a bit. Did you need something?",
    "Oh! Hi! Wasn't expecting a message, lol. Everything ok?",
    "Hey, sorry for the slow response — just chilling. What's going on?",
    "Ah, haha, sorry I'm a little slow today. How can I help?",
}

-- ---- Detect if the sender name looks like a GM account ----
local function LooksLikeGM(senderName)
    local cfg = GromitBot_GetConfig()
    if not cfg.gmDetectEnabled then return false end
    for _, pattern in ipairs(cfg.gmNamePatterns or {}) do
        if senderName:match(pattern) then
            return true
        end
    end
    return false
end

-- ---- Detect GM keywords in message text --------------------
local function ContainsGMKeyword(text)
    local cfg = GromitBot_GetConfig()
    if not cfg.gmDetectEnabled then return false end
    local lower = text:lower()
    for _, kw in ipairs(cfg.gmKeywords or {}) do
        if lower:find(kw, 1, true) then
            return true
        end
    end
    return false
end

-- ---- Handle a suspected GM contact -------------------------
local function HandleGMContact(senderName, msgType)
    local cfg = GromitBot_GetConfig()

    GB_Utils.Print("|cffff0000[GromitBot] Possible GM contact from " .. senderName .. " — stopping bot!|r")

    -- Stop all bots immediately
    local stopDelay = cfg.gmStopDelay or 2.0
    GB_Utils.After(stopDelay * 0.1, function()
        if GB_Fishing   then GB_Fishing.Stop()   end
        if GB_Herbalism then GB_Herbalism.Stop() end
    end)

    -- Send a human-like confused reply after a natural delay
    local replyDelay = GB_Utils.GaussRand(2.5, 0.7)
    replyDelay = math.max(1.5, math.min(5.0, replyDelay))
    GB_Utils.After(replyDelay, function()
        local response = GM_RESPONSES[math.random(#GM_RESPONSES)]
        if msgType == "WHISPER" then
            SendChatMessage(response, "WHISPER", nil, senderName)
        else
            SendChatMessage(response, "SAY")
        end
        lastReplyTime[senderName] = GetTime()
        GB_Utils.Debug("GM reply sent to " .. senderName)
    end)
end

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

    -- Never reply more than chatReplyMaxPerSender times to the same person
    local replies = replyCounts[senderName] or 0
    if replies >= cfg.chatReplyMaxPerSender then
        GB_Utils.Debug(senderName .. " reply limit reached (" .. replies .. ") — ignoring")
        return false
    end

    if msgType == "WHISPER" then
        return true  -- always reply to whispers (within limit)
    end

    -- SAY: only if sender is within chatReplySayRange ft
    local px, py, pz = 0, 0, 0
    if GB_GetPlayerPos then px, py, pz = GB_GetPlayerPos() end

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

    -- Stop moving immediately — a real player stops to type.
    isTyping = true
    StopAllMovement()

    GB_Utils.After(replyDelay, function()
        if not GB_OllamaSend then
            GB_Utils.Debug("GB_OllamaSend not available (DLL not loaded)")
            isTyping = false
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
            isTyping = false
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
        replyCounts[senderName] = (replyCounts[senderName] or 0) + 1
        GB_Utils.Debug("Replied to " .. senderName .. ": " .. response)

        -- Brief post-send pause before resuming movement—simulates the
        -- moment a player hits Enter then moves their hand back to WASD.
        local resumeDelay = math.max(0.5, math.min(2.5,
            GB_Utils.GaussRand(1.1, 0.45)))
        GB_Utils.After(resumeDelay, function()
            isTyping = false
        end)
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

    -- ---- GM detection (highest priority) -------------------
    -- Check sender name pattern OR message keywords.
    -- Act immediately regardless of other filters.
    if LooksLikeGM(senderName) or (isWhisper and ContainsGMKeyword(text)) then
        HandleGMContact(senderName, simpleMsgType)
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
    replyCounts    = {}
end
