#include "lua_bridge.h"
#include "memory.h"
#include "http_client.h"
#include "../include/offsets.h"
#include <cstring>
#include <string>

// ============================================================
// lua_bridge.cpp
// C++ functions exposed to WoW Lua as GB_* globals.
// ============================================================

// Known herb entry IDs for Azeroth (expanded as needed)
static const std::vector<int> HERB_ENTRIES = {
    1617,   // Peacebloom
    1618,   // Silverleaf
    2045,   // Earthroot
    785,    // Mageroyal
    2041,   // Bruiseweed
    3820,   // Stranglekelp
    3355,   // Wild Steelbloom
    3369,   // Grave Moss
    3357,   // Kingsblood
    3358,   // Liferoot
    3818,   // Fadeleaf
    3821,   // Goldthorn
    3819,   // Khadgar's Whisker
    4625,   // Wintersbite
    8836,   // Arthas' Tears
    8838,   // Sungrass
    8839,   // Blindweed
    8845,   // Ghost Mushroom
    8846,   // Gromsblood
    13464,  // Golden Sansam
    13463,  // Dreamfoil
    13468,  // Mountain Silversage
    13466,  // Plaguebloom
    13467,  // Icecap
    13465,  // Black Lotus
};

// ---------- helpers -----------------------------------------
static float ReadFloat(uintptr_t addr) {
    float v = 0.f; Memory::SafeRead(addr, v); return v;
}

// ============================================================
// Player state functions
// ============================================================
int L_GetPlayerPos(lua_State* L) {
    lua_pushnumber(L, ReadFloat(PLAYER_POS_X));
    lua_pushnumber(L, ReadFloat(PLAYER_POS_Y));
    lua_pushnumber(L, ReadFloat(PLAYER_POS_Z));
    return 3;
}

int L_GetPlayerFacing(lua_State* L) {
    lua_pushnumber(L, ReadFloat(PLAYER_FACING));
    return 1;
}

int L_GetPlayerHealth(lua_State* L) {
    WoWObject lp = ObjectManager::GetLocalPlayer();
    lua_pushinteger(L, lp.IsValid() ? lp.GetHealth()    : 0);
    lua_pushinteger(L, lp.IsValid() ? lp.GetMaxHealth() : 0);
    return 2;
}

int L_GetPlayerMana(lua_State* L) {
    WoWObject lp = ObjectManager::GetLocalPlayer();
    lua_pushinteger(L, lp.IsValid() ? lp.GetMana()    : 0);
    lua_pushinteger(L, lp.IsValid() ? lp.GetMaxMana() : 0);
    return 2;
}

int L_GetPlayerLevel(lua_State* L) {
    WoWObject lp = ObjectManager::GetLocalPlayer();
    lua_pushinteger(L, lp.IsValid() ? lp.GetLevel() : 1);
    return 1;
}

int L_IsCasting(lua_State* L) {
    int spellId = 0;
    Memory::SafeRead(PLAYER_CASTING_ID, spellId);
    lua_pushboolean(L, spellId != 0 ? 1 : 0);
    return 1;
}

int L_GetMapID(lua_State* L) {
    int mapId = 0;
    Memory::SafeRead(PLAYER_MAP_ID, mapId);
    lua_pushinteger(L, mapId);
    return 1;
}

// ============================================================
// Object query functions
// ============================================================
int L_FindFishingBobber(lua_State* L) {
    WoWObject bobber = ObjectManager::FindFishingBobber();
    if (!bobber.IsValid()) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, (int)(bobber.guid & 0xFFFFFFFF));
    lua_pushinteger(L, (int)((bobber.guid >> 32) & 0xFFFFFFFF));
    lua_pushnumber(L,  bobber.GetX());
    lua_pushnumber(L,  bobber.GetY());
    lua_pushnumber(L,  bobber.GetZ());
    lua_pushinteger(L, (bobber.GetDynamicFlags() & FISHING_BOBBER_SPLASH_FLAG) ? 1 : 0);
    return 6; // guid_lo, guid_hi, x, y, z, splashed
}

int L_FindNearestHerb(lua_State* L) {
    float px = ReadFloat(PLAYER_POS_X);
    float py = ReadFloat(PLAYER_POS_Y);
    float pz = ReadFloat(PLAYER_POS_Z);
    WoWObject herb = ObjectManager::FindNearestHerbNode(px, py, pz, HERB_ENTRIES);
    if (!herb.IsValid()) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, (int)(herb.guid & 0xFFFFFFFF));
    lua_pushnumber(L,  herb.GetX());
    lua_pushnumber(L,  herb.GetY());
    lua_pushnumber(L,  herb.GetZ());
    lua_pushinteger(L, herb.GetEntry());
    float dist = herb.DistanceTo(px, py, pz);
    lua_pushnumber(L, dist);
    return 6; // guid_lo, x, y, z, entry, distance
}

int L_FindNearestMob(lua_State* L) {
    // First arg: table of entry IDs to search for
    std::vector<int> entries;
    if (lua_istable(L, 1)) {
        lua_pushnil(L);
        while (lua_next(L, 1)) {
            entries.push_back((int)lua_tointeger(L, -1));
            lua_pop(L, 1);
        }
    }
    float px = ReadFloat(PLAYER_POS_X);
    float py = ReadFloat(PLAYER_POS_Y);
    float pz = ReadFloat(PLAYER_POS_Z);
    WoWObject mob = ObjectManager::FindNearestMob(px, py, pz, entries);
    if (!mob.IsValid()) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, (int)(mob.guid & 0xFFFFFFFF)); // guidLo
    lua_pushnumber(L,  mob.GetX());
    lua_pushnumber(L,  mob.GetY());
    lua_pushnumber(L,  mob.GetZ());
    lua_pushinteger(L, mob.GetEntry());
    lua_pushnumber(L,  mob.DistanceTo(px, py, pz));
    lua_pushnil(L); // name not available from descriptor; Lua uses `mname or "Mob"` fallback
    return 7; // guidLo, x, y, z, entry, dist, name
}

int L_GetNearbyObjects(lua_State* L) {
    float radius = (float)luaL_optnumber(L, 1, 40.0);
    float px = ReadFloat(PLAYER_POS_X);
    float py = ReadFloat(PLAYER_POS_Y);
    float pz = ReadFloat(PLAYER_POS_Z);

    auto objs = ObjectManager::GetNearbyGameObjects(px, py, pz, radius);
    lua_newtable(L);
    int idx = 1;
    for (auto& obj : objs) {
        lua_newtable(L);
        lua_pushinteger(L, (int)(obj.guid & 0xFFFFFFFF)); lua_setfield(L, -2, "guid");
        lua_pushinteger(L, obj.type);                      lua_setfield(L, -2, "type");
        lua_pushnumber(L,  obj.GetX());                    lua_setfield(L, -2, "x");
        lua_pushnumber(L,  obj.GetY());                    lua_setfield(L, -2, "y");
        lua_pushnumber(L,  obj.GetZ());                    lua_setfield(L, -2, "z");
        lua_pushinteger(L, obj.GetEntry());                lua_setfield(L, -2, "entry");
        lua_rawseti(L, -2, idx++);
    }
    return 1;
}

int L_GetObjectHealth(lua_State* L) {
    uint64_t guidLo = (uint64_t)luaL_checkinteger(L, 1);
    auto objs = ObjectManager::GetAllObjects();
    for (auto& obj : objs) {
        if ((obj.guid & 0xFFFFFFFF) == guidLo) {
            lua_pushinteger(L, obj.GetHealth());
            lua_pushinteger(L, obj.GetMaxHealth());
            return 2;
        }
    }
    lua_pushinteger(L, 0);
    lua_pushinteger(L, 0);
    return 2;
}

// ============================================================
// Inventory functions
// ============================================================
// WoW 1.12 bag layout: bag 0 = backpack (slots 1-16),
// bags 1-4 each 28 slots. We call Lua GetContainerNumSlots
// and GetContainerNumFreeSlots through the game's own Lua API,
// but those require being on the main Lua thread.
// Instead we read memory directly.
//
// Total slots counting: iterate bag slots via DescriptorFields.
// For a practical memory approach we use the known slot counts.
static int CountFreeSlots() {
    // Call WoW's own Lua functions through the already-embedded state
    // This avoids duplicating inventory parsing in C++.
    // We push a small Lua chunk and eval it.
    return -1; // Handled in Lua layer (see inventory.lua)
}

int L_GetInventoryFullness(lua_State* L) {
    // Delegated to Lua — return -1 as signal
    lua_pushinteger(L, -1);
    return 1;
}

int L_GetFreeSlotCount(lua_State* L) {
    lua_pushinteger(L, -1); // Delegated to Lua layer
    return 1;
}

// ============================================================
// Ollama / HTTP functions
// ============================================================
int L_OllamaSend(lua_State* L) {
    const char* model  = luaL_checkstring(L, 1);
    const char* system = luaL_checkstring(L, 2);
    const char* prompt = luaL_checkstring(L, 3);

    OllamaRequest req;
    req.model  = model  ? model  : "llama3";
    req.system = system ? system : "";
    req.prompt = prompt ? prompt : "";
    req.stream = false;

    OllamaResponse resp = HttpClient::PostOllama(req);
    if (!resp.success) {
        lua_pushnil(L);
        lua_pushstring(L, resp.error.c_str());
        return 2;
    }
    lua_pushstring(L, resp.response.c_str());
    return 1;
}

int L_HttpPost(lua_State* L) {
    const char* host = luaL_checkstring(L, 1);
    int         port = (int)luaL_checkinteger(L, 2);
    const char* path = luaL_checkstring(L, 3);
    const char* json = luaL_checkstring(L, 4);

    std::string result = HttpClient::PostJSON(host, port, path, json);
    lua_pushstring(L, result.c_str());
    return 1;
}

// ============================================================
// Registration
// ============================================================
namespace LuaBridge {
void RegisterAll(lua_State* L) {
    struct { const char* name; lua_CFunction fn; } funcs[] = {
        { "GB_GetPlayerPos",       L_GetPlayerPos       },
        { "GB_GetPlayerFacing",    L_GetPlayerFacing     },
        { "GB_GetPlayerHealth",    L_GetPlayerHealth     },
        { "GB_GetPlayerMana",      L_GetPlayerMana       },
        { "GB_GetPlayerLevel",     L_GetPlayerLevel      },
        { "GB_IsCasting",          L_IsCasting           },
        { "GB_GetMapID",           L_GetMapID            },
        { "GB_FindFishingBobber",  L_FindFishingBobber   },
        { "GB_FindNearestHerb",    L_FindNearestHerb     },
        { "GB_FindNearestMob",     L_FindNearestMob      },
        { "GB_GetNearbyObjects",   L_GetNearbyObjects    },
        { "GB_GetObjectHealth",    L_GetObjectHealth     },
        { "GB_GetInventoryFullness", L_GetInventoryFullness },
        { "GB_GetFreeSlotCount",   L_GetFreeSlotCount    },
        { "GB_OllamaSend",         L_OllamaSend          },
        { "GB_HttpPost",           L_HttpPost            },
    };
    for (auto& f : funcs) {
        lua_pushcfunction(L, f.fn);
        lua_setglobal(L, f.name);
    }
}
} // namespace LuaBridge
