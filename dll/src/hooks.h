#pragma once
#include <Windows.h>
#include <cstdint>

// ============================================================
// hooks.h — MinHook / Detour-based function hooks into WoW.exe
// ============================================================
//
// We hook EndScene (D3D8/D3D9 present callback) to get a safe
// main-thread Lua execution context each frame.
//

extern "C" {
    #include <lua.h>
}

namespace Hooks {
    bool Install();   // Call from DllMain THREAD_ATTACH or CreateThread
    void Remove();    // Call from PROCESS_DETACH

    // Retrieve the WoW Lua state (populated after first EndScene call)
    lua_State* GetLuaState();
    
    // True once the Lua bridge has been registered
    bool IsReady();
}
