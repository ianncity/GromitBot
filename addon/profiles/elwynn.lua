-- ============================================================
-- profiles/elwynn.lua — Elwynn Forest starter leveling profile
-- Level range: 1–9
-- Intended class: any (melee default rotation; override rotation
--   in your SavedVariables or via /gbot config for casters)
-- ============================================================

GB_Profiles.Register({
    name       = "Elwynn Forest 1-9",
    zone       = "Elwynn Forest",
    levelRange = { 1, 9 },

    -- ---- Mobs to kill (entry IDs) ---------------------------
    -- These are vanilla/Turtle WoW entry IDs for Elwynn mobs.
    killTargets = {
        { entry = 38,   name = "Young Wolf"          },
        { entry = 39,   name = "Timber Wolf"         },
        { entry = 40,   name = "Gray Forest Wolf"    },
        { entry = 47,   name = "Kobold Vermin"       },
        { entry = 48,   name = "Kobold Worker"       },
        { entry = 49,   name = "Kobold Laborer"      },
        { entry = 36,   name = "Defias Thug"         },
        { entry = 3980, name = "Defias Bandit"       },
        { entry = 111,  name = "Stonetusk Boar"      },
        { entry = 112,  name = "Thistle Boar"        },
    },

    -- ---- Patrol path: loop around the kobold mine area ------
    -- Westfall's Fargodeep Mine and Gold Coast Mine approach roads
    -- Approximate Elwynn coords near Fargodeep Mine:
    patrolPath = {
        { x = -9385, y =  439 },
        { x = -9450, y =  511 },
        { x = -9510, y =  465 },
        { x = -9490, y =  380 },
        { x = -9420, y =  340 },
        { x = -9370, y =  390 },
    },

    -- ---- Melee-focused default rotation ----------------------
    -- Works for Warriors, Rogues, and non-caster classes.
    -- Casters should override this in their SavedVariables profile.
    rotation = {
        { name = "Heroic Strike", minMana = 0,  maxRange = 3  },
        { name = "Rend",          minMana = 0,  maxRange = 3  },
        { name = "Sunder Armor",  minMana = 0,  maxRange = 3  },
    },

    -- ---- Rest thresholds (%) --------------------------------
    restHP   = 40,   resumeHP = 80,
    restMP   = 20,   resumeMP = 70,

    -- ---- Quests ---------------------------------------------
    -- Uncomment and fill in NPC coordinates once surveyed in-game.
    -- quests = {
    --   {
    --     id   = 60,
    --     name = "A Threat Within",
    --     objectives = {},
    --     acceptNPC  = { name = "Marshal Dughan",  x = -9461, y = 62 },
    --     turnInNPC  = { name = "Marshal McBride", x = -9382, y = 66 },
    --   },
    -- },
})
