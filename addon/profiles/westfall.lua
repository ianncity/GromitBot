-- ============================================================
-- profiles/westfall.lua — Westfall leveling profile
-- Level range: 10–20
-- ============================================================

GB_Profiles.Register({
    name       = "Westfall 10-20",
    zone       = "Westfall",
    levelRange = { 10, 20 },

    -- ---- Mobs to kill ----------------------------------------
    killTargets = {
        { entry = 450,  name = "Harvest Golem"       },
        { entry = 451,  name = "Harvest Reaper"      },
        { entry = 453,  name = "Defias Pillager"     },
        { entry = 454,  name = "Defias Outrunner"    },
        { entry = 455,  name = "Defias Pathstalker"  },
        { entry = 117,  name = "Greater Fleshripper" },
        { entry = 116,  name = "Fleshripper"         },
        { entry = 462,  name = "Goretusk"            },
        { entry = 463,  name = "Large Crag Boar"     },
    },

    -- ---- Patrol: loop through the Dust Plains -----------
    -- Covers the Harvest Farm area rich in Golems and Defias.
    patrolPath = {
        { x = -11215, y = 1618 },
        { x = -11380, y = 1643 },
        { x = -11468, y = 1539 },
        { x = -11526, y = 1397 },
        { x = -11450, y = 1278 },
        { x = -11308, y = 1214 },
        { x = -11168, y = 1305 },
        { x = -11117, y = 1458 },
        { x = -11148, y = 1570 },
    },

    -- ---- Melee rotation (generic fighter) -------------------
    rotation = {
        { name = "Heroic Strike", minMana = 0,  maxRange = 3  },
        { name = "Rend",          minMana = 0,  maxRange = 3  },
        { name = "Thunder Clap",  minMana = 0,  maxRange = 3  },
        { name = "Hamstring",     minMana = 0,  maxRange = 3  },
    },

    -- ---- Rest thresholds (%) --------------------------------
    restHP   = 45,   resumeHP = 80,
    restMP   = 20,   resumeMP = 70,

    -- ---- Quests ---------------------------------------------
    quests = {
        {
            id   = 168,
            name = "The Forgotten Heirloom",
            objectives = {
                { type = "kill", entry = 454, count = 10, name = "Defias Outrunner" },
            },
            acceptNPC = { name = "Farmer Saldean", x = -11209, y = 1661 },
            turnInNPC = { name = "Farmer Saldean", x = -11209, y = 1661 },
        },
        {
            id   = 155,
            name = "The Defias Brotherhood",
            objectives = {
                { type = "kill", entry = 453, count = 15, name = "Defias Pillager" },
            },
            -- This quest is picked up from Stormwind — pre-accept and mark acceptNPC=nil
            acceptNPC = nil,
            turnInNPC = { name = "Gryan Stoutmantle", x = -11142, y = 1694, rewardChoice = 1 },
        },
    },
})
