#include "hooks.h"
#include "lua_bridge.h"
#include "memory.h"
#include "../include/offsets.h"
#include <d3d8.h>
#include <atomic>

// ============================================================
// hooks.cpp — EndScene detour for per-frame Lua registration
//
// Strategy:
//   1. Read the D3D8 device vtable pointer from WoW's static D3D
//      device pointer (offset 0x00C5DF88 for build 5875).
//   2. Patch vtable[35] (EndScene index for D3D8) to our hook.
//   3. On first call, grab the Lua state and register GB_ funcs.
//   4. Restore the original pointer and stop hooking.
//
// MinHook is NOT required — we use a simple vtable patch.
// ============================================================

#define D3D8_DEVICE_PTR   0x00C5DF88  // WoW 1.12.1 build 5875
#define ENDSCENE_VTBL_IDX 35          // D3D8 EndScene vtable index

typedef HRESULT (__stdcall *EndScene_t)(void* device);
static EndScene_t g_origEndScene = nullptr;
static void*      g_vtablePtr    = nullptr;
static std::atomic<bool> g_ready { false };
static lua_State* g_luaState     = nullptr;

// ---- Hooked EndScene ----------------------------------------
static HRESULT __stdcall HookedEndScene(void* device) {
    if (!g_ready.load()) {
        // Read Lua state from WoW's static pointer
        uintptr_t luaStateAddr = Memory::Read<uintptr_t>(LUA_STATE_PTR);
        if (luaStateAddr) {
            g_luaState = reinterpret_cast<lua_State*>(luaStateAddr);
            LuaBridge::RegisterAll(g_luaState);
            ObjectManager::Initialize();
            g_ready.store(true);

            // Restore original EndScene so we stop paying the hook cost
            DWORD oldProtect;
            VirtualProtect(g_vtablePtr, sizeof(void*), PAGE_EXECUTE_READWRITE, &oldProtect);
            *reinterpret_cast<void**>(g_vtablePtr) = reinterpret_cast<void*>(g_origEndScene);
            VirtualProtect(g_vtablePtr, sizeof(void*), oldProtect, &oldProtect);
        }
    }
    return g_origEndScene(device);
}

namespace Hooks {

bool Install() {
    // Get D3D8 device pointer
    uintptr_t devPtrAddr = D3D8_DEVICE_PTR;
    uintptr_t devicePtr  = 0;
    if (!Memory::SafeRead(devPtrAddr, devicePtr) || devicePtr == 0) {
        // D3D8 device not yet created — wait for first frame
        // Caller should spin until Install() returns true
        return false;
    }

    // device vtable is at *devicePtr
    uintptr_t vtable = 0;
    if (!Memory::SafeRead(devicePtr, vtable) || vtable == 0) return false;

    g_vtablePtr = reinterpret_cast<void*>(vtable + ENDSCENE_VTBL_IDX * sizeof(void*));

    uintptr_t origFunc = 0;
    Memory::SafeRead(reinterpret_cast<uintptr_t>(g_vtablePtr), origFunc);
    g_origEndScene = reinterpret_cast<EndScene_t>(origFunc);

    // Patch vtable
    DWORD oldProtect;
    VirtualProtect(g_vtablePtr, sizeof(void*), PAGE_EXECUTE_READWRITE, &oldProtect);
    *reinterpret_cast<void**>(g_vtablePtr) = reinterpret_cast<void*>(&HookedEndScene);
    VirtualProtect(g_vtablePtr, sizeof(void*), oldProtect, &oldProtect);

    return true;
}

void Remove() {
    if (g_vtablePtr && g_origEndScene) {
        DWORD oldProtect;
        VirtualProtect(g_vtablePtr, sizeof(void*), PAGE_EXECUTE_READWRITE, &oldProtect);
        *reinterpret_cast<void**>(g_vtablePtr) = reinterpret_cast<void*>(g_origEndScene);
        VirtualProtect(g_vtablePtr, sizeof(void*), oldProtect, &oldProtect);
    }
}

lua_State* GetLuaState() { return g_luaState; }
bool IsReady() { return g_ready.load(); }

} // namespace Hooks
