#pragma once
// ============================================================
// lua_bridge.h — Registers C++ functions into the WoW Lua VM
// SuperWoW exposes lua_State via the Lua C API; we piggyback.
// ============================================================

extern "C" {
    // Standard Lua C API headers — bundled with SuperWoW or WoW libs
    // Adjust include paths to match your WoW SDK / SuperWoW headers
    #include <lua.h>
    #include <lauxlib.h>
    #include <lualib.h>
}

namespace LuaBridge {
    // Call once after DLL injection to register all GB_* functions
    void RegisterAll(lua_State* L);
}

// ---- Individual Lua-callable C functions -------------------
// All follow the lua_CFunction signature: int fn(lua_State* L)
// They are registered as globals named "GB_<name>" in Lua.

// Player state
int L_GetPlayerPos(lua_State* L);         // -> x, y, z
int L_GetPlayerFacing(lua_State* L);      // -> facing (radians)
int L_GetPlayerHealth(lua_State* L);      // -> hp, maxhp
int L_GetPlayerMana(lua_State* L);        // -> mana, maxmana
int L_GetPlayerLevel(lua_State* L);       // -> level
int L_IsCasting(lua_State* L);            // -> bool
int L_GetMapID(lua_State* L);             // -> mapId

// Object queries
int L_FindFishingBobber(lua_State* L);    // -> guid_low, guid_high, x, y, z  (or nil)
int L_FindNearestHerb(lua_State* L);      // -> guid_low, x, y, z, entry  (or nil)
int L_FindNearestMob(lua_State* L);       // entryTable -> guid_low, x, y, z, entry, dist, name (or nil)
int L_GetNearbyObjects(lua_State* L);     // radius -> table of {guid,type,x,y,z}
int L_GetObjectHealth(lua_State* L);      // guid_low -> hp, maxhp

// Inventory
int L_GetInventoryFullness(lua_State* L); // -> pct (0-100)
int L_GetFreeSlotCount(lua_State* L);     // -> count of free bag slots

// Ollama / HTTP
int L_OllamaSend(lua_State* L);           // model, system, prompt -> response string
int L_HttpPost(lua_State* L);             // host, port, path, json -> body string
