#include "memory.h"
#include "../include/offsets.h"
#include <stdexcept>
#include <cmath>

// ============================================================
// memory.cpp
// ============================================================

namespace Memory {

std::string ReadString(uintptr_t address, size_t maxLen) {
    if (!address) return "";
    std::string result;
    result.reserve(64);
    for (size_t i = 0; i < maxLen; ++i) {
        char c = 0;
        if (!SafeRead(address + i, c) || c == '\0') break;
        result += c;
    }
    return result;
}

uintptr_t ReadMultiLevelPtr(uintptr_t base, const std::vector<uintptr_t>& offsets) {
    uintptr_t current = base;
    for (auto off : offsets) {
        uintptr_t next = 0;
        if (!SafeRead(current + off, next) || next == 0) return 0;
        current = next;
    }
    return current;
}

} // namespace Memory

// ============================================================
// WoWObject impl
// ============================================================
float WoWObject::GetX() const {
    float v = 0.f;
    Memory::SafeRead(base + GAMEOBJECT_POS_X, v);
    return v;
}
float WoWObject::GetY() const {
    float v = 0.f;
    Memory::SafeRead(base + GAMEOBJECT_POS_Y, v);
    return v;
}
float WoWObject::GetZ() const {
    float v = 0.f;
    Memory::SafeRead(base + GAMEOBJECT_POS_Z, v);
    return v;
}
float WoWObject::DistanceTo(float px, float py, float pz) const {
    float dx = GetX() - px, dy = GetY() - py, dz = GetZ() - pz;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}
int WoWObject::GetEntry() const {
    int entry = 0;
    Memory::SafeRead(base + GAMEOBJECT_ENTRY, entry);
    return entry;
}
int WoWObject::GetHealth() const {
    int v = 0;
    // descriptor ptr sits at base+0x8, field array at descriptor+fieldOffset
    uintptr_t desc = 0;
    Memory::SafeRead(base + 0x8, desc);
    Memory::SafeRead(desc + UNIT_FIELD_HEALTH, v);
    return v;
}
int WoWObject::GetMaxHealth() const {
    int v = 0;
    uintptr_t desc = 0;
    Memory::SafeRead(base + 0x8, desc);
    Memory::SafeRead(desc + UNIT_FIELD_MAXHEALTH, v);
    return v;
}
int WoWObject::GetLevel() const {
    int v = 0;
    uintptr_t desc = 0;
    Memory::SafeRead(base + 0x8, desc);
    Memory::SafeRead(desc + UNIT_FIELD_LEVEL, v);
    return v;
}
bool WoWObject::IsCasting() const {
    int spellId = 0;
    Memory::SafeRead(PLAYER_CASTING_ID, spellId);
    return spellId != 0;
}
bool WoWObject::IsDead() const {
    return GetHealth() == 0;
}
uint32_t WoWObject::GetDynamicFlags() const {
    uint32_t v = 0;
    uintptr_t desc = 0;
    Memory::SafeRead(base + 0x8, desc);
    Memory::SafeRead(desc + UNIT_DYNAMIC_FLAGS, v);
    return v;
}
bool WoWObject::IsFishingBobber() const {
    return (type == OBJECT_TYPE_GAMEOBJECT) && (GetEntry() == FISHING_NODE_ENTRY);
}

// ============================================================
// ObjectManager impl
// ============================================================
namespace ObjectManager {

static uint64_t s_localGuid = 0;

bool Initialize() {
    uintptr_t clientConn = Memory::Read<uintptr_t>(STATIC_CLIENT_CONNECTION);
    if (!clientConn) return false;
    uintptr_t mgr = Memory::Read<uintptr_t>(clientConn + OFFSET_GAME_OBJ_MANAGER);
    return mgr != 0;
}

uint64_t GetLocalGUID() {
    uintptr_t clientConn = Memory::Read<uintptr_t>(STATIC_CLIENT_CONNECTION);
    if (!clientConn) return 0;
    uintptr_t mgr = Memory::Read<uintptr_t>(clientConn + OFFSET_GAME_OBJ_MANAGER);
    if (!mgr) return 0;
    uint64_t guid = 0;
    Memory::SafeRead(mgr + OBJECT_MANAGER_LOCAL_GUID, guid);
    return guid;
}

static std::vector<WoWObject> EnumerateObjects() {
    std::vector<WoWObject> result;
    uintptr_t clientConn = Memory::Read<uintptr_t>(STATIC_CLIENT_CONNECTION);
    if (!clientConn) return result;
    uintptr_t mgr = Memory::Read<uintptr_t>(clientConn + OFFSET_GAME_OBJ_MANAGER);
    if (!mgr) return result;

    uintptr_t objPtr = 0;
    Memory::SafeRead(mgr + OBJECT_MANAGER_FIRST_OBJ, objPtr);

    int iterations = 0;
    while (objPtr && objPtr != mgr && iterations < 2000) {
        ++iterations;
        WoWObject obj;
        obj.base = objPtr;
        Memory::SafeRead(objPtr + OBJECT_GUID_OFFSET, obj.guid);
        Memory::SafeRead(objPtr + OBJECT_TYPE_OFFSET, obj.type);
        if (obj.guid != 0) result.push_back(obj);
        Memory::SafeRead(objPtr + OBJECT_NEXT_OFFSET, objPtr);
    }
    return result;
}

WoWObject GetLocalPlayer() {
    uint64_t lguid = GetLocalGUID();
    for (auto& obj : EnumerateObjects()) {
        if (obj.guid == lguid && obj.type == OBJECT_TYPE_PLAYER) return obj;
    }
    return {};
}

WoWObject GetObjectByGUID(uint64_t guid) {
    for (auto& obj : EnumerateObjects()) {
        if (obj.guid == guid) return obj;
    }
    return {};
}

std::vector<WoWObject> GetAllObjects() { return EnumerateObjects(); }

std::vector<WoWObject> GetNearbyUnits(float x, float y, float z, float radius) {
    std::vector<WoWObject> result;
    for (auto& obj : EnumerateObjects()) {
        if (obj.type == OBJECT_TYPE_UNIT || obj.type == OBJECT_TYPE_PLAYER)
            if (obj.DistanceTo(x, y, z) <= radius) result.push_back(obj);
    }
    return result;
}

std::vector<WoWObject> GetNearbyGameObjects(float x, float y, float z, float radius) {
    std::vector<WoWObject> result;
    for (auto& obj : EnumerateObjects()) {
        if (obj.type == OBJECT_TYPE_GAMEOBJECT)
            if (obj.DistanceTo(x, y, z) <= radius) result.push_back(obj);
    }
    return result;
}

WoWObject FindFishingBobber() {
    for (auto& obj : EnumerateObjects()) {
        if (obj.IsFishingBobber()) return obj;
    }
    return {};
}

WoWObject FindNearestHerbNode(float x, float y, float z,
                               const std::vector<int>& herbEntryIds) {
    WoWObject nearest;
    float nearestDist = 1e9f;
    for (auto& obj : EnumerateObjects()) {
        if (obj.type != OBJECT_TYPE_GAMEOBJECT) continue;
        int entry = obj.GetEntry();
        for (int id : herbEntryIds) {
            if (id == entry) {
                float d = obj.DistanceTo(x, y, z);
                if (d < nearestDist) { nearestDist = d; nearest = obj; }
                break;
            }
        }
    }
    return nearest;
}

} // namespace ObjectManager
