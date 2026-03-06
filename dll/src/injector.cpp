/*
 * injector.cpp — Simple LoadLibrary DLL injector
 * ================================================
 * Injects GromitBot.dll into a running WoW.exe process.
 *
 * Usage:
 *   injector.exe [optional: pid]
 *
 * If no PID is provided, the injector will scan for the first
 * process named "WoW.exe" and inject into it automatically.
 *
 * Build:
 *   cl /std:c++17 /W3 /EHsc injector.cpp /link /out:injector.exe
 *   (Must be 32-bit: /arch:IA32 or compile with VS x86 toolset)
 */

#include <Windows.h>
#include <TlHelp32.h>
#include <iostream>
#include <string>
#include <filesystem>

// ---- Find process by name -----------------------------------
static DWORD FindProcessID(const std::wstring& name) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);

    DWORD pid = 0;
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, name.c_str()) == 0) {
                pid = entry.th32ProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return pid;
}

// ---- Inject DLL into target process -------------------------
static bool InjectDLL(DWORD pid, const std::string& dllPath) {
    if (!std::filesystem::exists(dllPath)) {
        std::cerr << "[!] DLL not found: " << dllPath << "\n";
        return false;
    }

    HANDLE hProc = OpenProcess(
        PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
        PROCESS_VM_OPERATION  | PROCESS_VM_WRITE | PROCESS_VM_READ,
        FALSE, pid
    );
    if (!hProc) {
        std::cerr << "[!] OpenProcess failed: " << GetLastError() << "\n";
        return false;
    }

    // Allocate memory in target for DLL path
    SIZE_T pathLen = dllPath.size() + 1;
    LPVOID remoteStr = VirtualAllocEx(hProc, nullptr, pathLen,
                                       MEM_COMMIT | MEM_RESERVE,
                                       PAGE_READWRITE);
    if (!remoteStr) {
        std::cerr << "[!] VirtualAllocEx failed: " << GetLastError() << "\n";
        CloseHandle(hProc);
        return false;
    }

    if (!WriteProcessMemory(hProc, remoteStr, dllPath.c_str(), pathLen, nullptr)) {
        std::cerr << "[!] WriteProcessMemory failed: " << GetLastError() << "\n";
        VirtualFreeEx(hProc, remoteStr, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return false;
    }

    HANDLE hThread = CreateRemoteThread(
        hProc, nullptr, 0,
        (LPTHREAD_START_ROUTINE)GetProcAddress(GetModuleHandleA("kernel32.dll"),
                                                "LoadLibraryA"),
        remoteStr, 0, nullptr
    );
    if (!hThread) {
        std::cerr << "[!] CreateRemoteThread failed: " << GetLastError() << "\n";
        VirtualFreeEx(hProc, remoteStr, 0, MEM_RELEASE);
        CloseHandle(hProc);
        return false;
    }

    std::cout << "[+] Injection thread started (TID: " << GetThreadId(hThread) << ")\n";
    WaitForSingleObject(hThread, 8000);

    DWORD exitCode = 0;
    GetExitCodeThread(hThread, &exitCode);
    std::cout << "[+] LoadLibraryA returned: 0x" << std::hex << exitCode << "\n";

    CloseHandle(hThread);
    VirtualFreeEx(hProc, remoteStr, 0, MEM_RELEASE);
    CloseHandle(hProc);

    return exitCode != 0;
}

// ---- Main ---------------------------------------------------
int main(int argc, char* argv[]) {
    std::cout << "=== GromitBot DLL Injector ===\n";

    DWORD pid = 0;
    if (argc >= 2) {
        pid = std::stoul(argv[1]);
    } else {
        pid = FindProcessID(L"WoW.exe");
        if (!pid) {
            std::cerr << "[!] WoW.exe not found. Start WoW first.\n";
            return 1;
        }
        std::cout << "[+] Found WoW.exe PID: " << pid << "\n";
    }

    // DLL path: same directory as injector.exe
    char exePath[MAX_PATH] = {};
    GetModuleFileNameA(nullptr, exePath, MAX_PATH);
    std::filesystem::path dllPath =
        std::filesystem::path(exePath).parent_path() / "GromitBot.dll";

    std::cout << "[+] Injecting: " << dllPath.string() << "\n";
    bool ok = InjectDLL(pid, dllPath.string());

    if (ok) {
        std::cout << "[+] Injection successful!\n";
    } else {
        std::cerr << "[!] Injection failed.\n";
        return 1;
    }

    return 0;
}
