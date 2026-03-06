#include <Windows.h>
#include <thread>
#include <chrono>
#include "hooks.h"

// ============================================================
// dllmain.cpp — DLL entry point
//
// Injected into WoW.exe via an external injector
// (e.g. simple LoadLibrary injector, SuperWoW loader, etc.)
// ============================================================

static void InstallThread() {
    // Spin until D3D8 device is initialised (WoW renders first frame)
    while (!Hooks::Install()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    // Hook installed; the HookedEndScene will self-remove after
    // registering Lua functions on the first frame.
}

BOOL WINAPI DllMain(HINSTANCE hInstance, DWORD reason, LPVOID) {
    switch (reason) {
    case DLL_PROCESS_ATTACH:
        DisableThreadLibraryCalls(hInstance);
        // Start installation on a worker thread to avoid
        // DllMain deadlock rules.
        std::thread(InstallThread).detach();
        break;

    case DLL_PROCESS_DETACH:
        Hooks::Remove();
        break;
    }
    return TRUE;
}
