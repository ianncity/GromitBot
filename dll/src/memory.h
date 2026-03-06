#pragma once
#include <Windows.h>
#include <cstdint>
#include <vector>
#include <string>

// ============================================================
// memory.h — Safe process-memory read/write helpers
// ============================================================

namespace Memory {

// ---- Primitive typed reads ---------------------------------
template<typename T>
inline T Read(uintptr_t address) {
    return *reinterpret_cast<T*>(address);
}

template<typename T>
inline void Write(uintptr_t address, T value) {
    *reinterpret_cast<T*>(address) = value;
}

// ---- String read (null-terminated, max 256 chars) ----------
std::string ReadString(uintptr_t address, size_t maxLen = 256);

// ---- Multi-level pointer dereference -----------------------
uintptr_t ReadMultiLevelPtr(uintptr_t base, const std::vector<uintptr_t>& offsets);

// ---- Bounds-checked safe read (returns false on AV) --------
template<typename T>
inline bool SafeRead(uintptr_t address, T& out) {
    __try {
        out = *reinterpret_cast<T*>(address);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

} // namespace Memory

// ============================================================
// WoWObject — thin wrapper around a game object base pointer
// ============================================================
struct WoWObject {
    uintptr_t base = 0;
    uint64_t  guid = 0;
    int       type = 0;

    bool  IsValid()  const { return base != 0; }
    float GetX()     const;
    float GetY()     const;
    float GetZ()     const;
    float DistanceTo(float px, float py, float pz) const;
    int   GetEntry() const;

    // Unit-specific
    int  GetHealth()    const;
    int  GetMaxHealth() const;
    int  GetLevel()     const;
    bool IsCasting()    const;
    bool IsDead()       const;
    uint32_t GetDynamicFlags() const;

    // GameObj-specific
    bool IsFishingBobber() const;
};

// ============================================================
// ObjectManager — iterates WoW object list
// ============================================================
namespace ObjectManager {
    bool         Initialize();
    uint64_t     GetLocalGUID();
    WoWObject    GetLocalPlayer();
    WoWObject    GetObjectByGUID(uint64_t guid);
    std::vector<WoWObject> GetAllObjects();
    std::vector<WoWObject> GetNearbyUnits(float x, float y, float z, float radius);
    std::vector<WoWObject> GetNearbyGameObjects(float x, float y, float z, float radius);
    WoWObject    FindFishingBobber();
    WoWObject    FindNearestHerbNode(float x, float y, float z,
                                     const std::vector<int>& herbEntryIds);
}
