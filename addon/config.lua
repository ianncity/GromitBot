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

    -- Only reply to whispers, or to /say if the sender is within 20 yards
    -- AND has sent >= 2 messages this session.
    chatReplyMinSayMessages = 2,
    chatReplySayRange       = 20,

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
    humanJumpChance      = 0.08,  -- probability per second of random jump
    humanTurnAmount      = 0.15,  -- max camera turn in radians per random event
    humanTurnInterval    = { 4, 10 }, -- seconds between random camera turns
    humanWiggleRadius    = 2.0,   -- max wander offset from home position (yards)
    humanWiggleInterval  = { 8, 20 }, -- seconds between position wiggles

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
