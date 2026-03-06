-- ============================================================
-- profiles/redridge.lua — Redridge Mountains leveling profile
-- Level range: 18–30
-- ============================================================

GB_Profiles.Register({
    name       = "Redridge Mountains 18-30",
    zone       = "Redridge Mountains",
    levelRange = { 18, 30 },

    -- ---- Mobs to kill ----------------------------------------
    killTargets = {
        { entry = 698,  name = "Redridge Mongrel"       },
        { entry = 700,  name = "Redridge Basher"        },
        { entry = 701,  name = "Redridge Mystic"        },
        { entry = 699,  name = "Redridge Brute"         },
        { entry = 718,  name = "Black Dragon Whelp"     },
        { entry = 2768, name = "Blackrock Orc"          },
        { entry = 2767, name = "Blackrock Raider"       },
    },

    -- ---- Patrol: Three Corners → Render's Valley loop ------
    patrolPath = {
        { x = -8865, y = -2177 },
        { x = -8993, y = -2250 },
        { x = -9100, y = -2230 },
        { x = -9196, y = -2155 },
        { x = -9193, y = -2058 },
        { x = -9060, y = -1979 },
        { x = -8927, y = -2015 },
        { x = -8852, y = -2108 },
    },

    -- ---- Rotation: generic melee / warrior ------------------
    rotation = {
        { name = "Heroic Strike",  minMana = 0,  maxRange = 3  },
        { name = "Rend",           minMana = 0,  maxRange = 3  },
        { name = "Thunder Clap",   minMana = 0,  maxRange = 3  },
        { name = "Sunder Armor",   minMana = 0,  maxRange = 3  },
    },

    -- ---- Rest thresholds ------------------------------------
    restHP   = 45,   resumeHP = 80,
    restMP   = 20,   resumeMP = 70,

    -- ---- Quests (stubs — fill x/y in-game) -----------------
    -- quests = {
    --   {
    --     id   = 122,
    --     name = "The Messenger",
    --     objectives = {},
    --     acceptNPC  = { name = "Magistrate Solomon", x = -8953, y = -2137 },
    --     turnInNPC  = { name = "Magistrate Solomon", x = -8953, y = -2137 },
    --   },
    -- },
})
