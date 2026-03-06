-- ============================================================
-- config.lua — Runtime configuration loaded from SavedVariables
-- Edit GromitBotConfig in WTF/Account/*/SavedVariables/ or
-- copy the defaults below and tune them in-game via /gbot config
-- ============================================================

-- Default values — merged over SavedVariables on load.
local DEFAULTS = {
    -- "fishing" or "herbalism"
    mode = "fishing",

    -- Who to mail inventory when bags hit mailThreshold % full
    mailTarget = "Bankalt",

    -- Bag fullness % that triggers auto-mail (0-100)
    mailThreshold = 80,

    -- Ollama settings
    ollamaModel  = "llama3",
    ollamaPort   = 11434,
    ollamaPersona =
        "You are a friendly World of Warcraft player on the Turtle WoW server. "
        .. "Respond naturally and in-character, keep replies short (1-2 sentences), "
        .. "use WoW slang where appropriate. Never break character.",

    -- Only reply to whispers, or to /say if the sender is within 10 ft.
    -- Never reply to the same person more than chatReplyMaxPerSender times per session.
    chatReplySayRange       = 10,  -- ft (approx 3.3 WoW yards)
    chatReplyMaxPerSender   = 3,

    -- GM / staff detection: stop bot and send a confused reply if a whisper
    -- looks like it might be from a GM. Pattern matched case-insensitively.
    gmDetectEnabled  = true,
    gmNamePatterns   = { "^GM", "^%[GM%]", "Blizz", "GameMaster", "CM", "^Staff" },
    gmKeywords       = {
        "bot", "botting", "cheat", "hack", "automat", "script",
        "third.party", "violation", "suspended", "banned", "report",
        "game master", "gm here",
    },
    -- Delay (seconds) before auto-stopping when GM phrases detected
    gmStopDelay      = 2.0,

    -- Farming zone name (used for navmesh selection)
    farmZone = "Arathi Highlands",

    -- Herbalism node entry IDs to target in the current zone
    -- Default list covers common Azeroth herbs — tune per zone
    herbEntries = {
        3820,   -- Stranglekelp (if near water)
        3355,   -- Wild Steelbloom
        3357,   -- Kingsblood
        3818,   -- Fadeleaf
        3821,   -- Goldthorn
    },

    -- Navmesh file path (relative to WoW root or absolute)
    navmeshPath = "Interface\\AddOns\\GromitBot\\navmesh\\arathi.nav",

    -- Human behaviour tuning
    humanJumpChance      = 0.08,  -- average probability per second of random jump
    humanJumpMinGap      = 4.0,   -- minimum seconds between consecutive jumps
    humanTurnAmount      = 0.15,  -- max camera yaw (radians) per random event
    humanTurnInterval    = { 4, 10 }, -- seconds between random camera turns (Gaussian)
    humanWiggleRadius    = 2.0,   -- max wander offset from home position (yards)
    humanWiggleInterval  = { 8, 20 }, -- seconds between position wiggles (Gaussian)

    -- Camera pitch (vertical look) variation
    humanPitchEnabled    = true,
    humanPitchAmount     = 0.12,  -- max vertical look offset in radians

    -- Random emotes (SIT, YAWN, STRETCH, etc.)
    humanEmotesEnabled   = true,
    humanEmoteInterval   = { 45, 120 }, -- seconds between emotes (Gaussian)

    -- Briefly target a nearby unit to mimic player curiosity
    humanTargetScanEnabled = true,
    humanScanInterval      = { 30, 90 }, -- seconds between target scans (Gaussian)

    -- AFK / session break system
    humanBreaksEnabled   = true,
    humanBreakInterval   = { 2700, 5400 }, -- 45–90 min between breaks (Gaussian)
    humanBreakDuration   = { 180, 900 },   -- 3–15 min break length (Gaussian)

    -- ---- Leveling bot settings ----------------------------
    -- Active profile name (must match a registered profile's .name field)
    levelingProfile = "",

    -- Pull range override (yards). 0 = auto-detect from rotation maxRange.
    levelingPullRange    = 0,

    -- Looted corpse memory size (how many GUIDs to remember to avoid re-loot)
    levelingCorpseMemory = 50,

    -- Combat timeout (s) before the bot retreats and resets
    levelingCombatTimeout = 30,

    -- Command file polled by Lua (written by Python agent)
    commandFilePath = "C:\\GromitBot\\command.txt",

    -- Verbose debug messages in chat
    debug = false,
}

function GromitBot_LoadConfig()
    if type(GromitBotConfig) ~= "table" then
        GromitBotConfig = {}
    end
    -- Merge defaults for any missing keys
    for k, v in pairs(DEFAULTS) do
        if GromitBotConfig[k] == nil then
            GromitBotConfig[k] = GB_Utils.DeepCopy(v)
        end
    end
end

-- Convenience alias used throughout the addon
function GromitBot_GetConfig()
    return GromitBotConfig
end
