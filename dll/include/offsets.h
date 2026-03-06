#pragma once
// ============================================================
// WoW 1.12.1 (build 5875) memory offsets for Turtle WoW
// All offsets verified against vanilla client base 0x00400000
// ============================================================

// ---- Object Manager ----------------------------------------
#define STATIC_CLIENT_CONNECTION   0x00C79CE0
#define OFFSET_GAME_OBJ_MANAGER    0x2ED0
#define OBJECT_MANAGER_FIRST_OBJ   0x00AC
#define OBJECT_MANAGER_LOCAL_GUID  0x00C0

// ---- Object fields -----------------------------------------
#define OBJECT_TYPE_OFFSET         0x14
#define OBJECT_GUID_OFFSET         0x30
#define OBJECT_NEXT_OFFSET         0x3C

// ---- Unit descriptors (player/mob) -------------------------
#define UNIT_FIELD_HEALTH          0x58 * 4  // descriptor array index * 4
#define UNIT_FIELD_MAXHEALTH       0x60 * 4
#define UNIT_FIELD_LEVEL           0x36 * 4
#define UNIT_FIELD_FLAGS           0xB6 * 4
#define UNIT_FIELD_TARGET          0x12 * 4
#define UNIT_DYNAMIC_FLAGS         0x0A2 * 4

// ---- Player position (local player) ------------------------
#define PLAYER_POS_X               0xABD6FC
#define PLAYER_POS_Y               0xABD700
#define PLAYER_POS_Z               0xABD704
#define PLAYER_FACING              0xABD720
#define PLAYER_MAP_ID              0xABCEEB8

// ---- WoW GUID types ----------------------------------------
#define HIGHGUID_UNIT              0x00F10000
#define HIGHGUID_GAMEOBJ           0x00F11000
#define HIGHGUID_PLAYER            0x00000000

// ---- Object types ------------------------------------------
#define OBJECT_TYPE_ITEM           1
#define OBJECT_TYPE_CONTAINER      2
#define OBJECT_TYPE_UNIT           3
#define OBJECT_TYPE_PLAYER         4
#define OBJECT_TYPE_GAMEOBJECT     5
#define OBJECT_TYPE_DYNOBJ         6
#define OBJECT_TYPE_CORPSE         7

// ---- Casting / spell state ---------------------------------
#define PLAYER_CASTING_ID          0xABD6F4
#define PLAYER_CASTING_REMAINING   0xABD6F8

// ---- Inventory (bag 0 = backpack, slots 1-16 inside bags) --
#define BAG_BASE_SLOT              19   // first bag slot
#define BACKPACK_SLOT_START        23
#define BACKPACK_SLOT_COUNT        16
#define BAG_SLOT_COUNT             28   // per bag

// ---- Fishing bobber detection ------------------------------
#define FISHING_BOBBER_SPLASH_FLAG 0x10  // dynamic flags bit
#define FISHING_NODE_ENTRY         35591 // Fishing Bobber entry ID

// ---- Lua state pointer ------------------------------------
#define LUA_STATE_PTR              0x00C7B284

// ---- Target GUID ------------------------------------------
#define TARGET_GUID_PTR            0x00B4B43C

// ---- Zone / subzone text ptrs -----------------------------
#define ZONE_TEXT_PTR              0x00C2BA54
#define SUBZONE_TEXT_PTR           0x00C2BA58

// ---- Game object fields ------------------------------------
#define GAMEOBJECT_POS_X           0xE8
#define GAMEOBJECT_POS_Y           0xEC
#define GAMEOBJECT_POS_Z           0xF0
#define GAMEOBJECT_ENTRY           0x1C4  // from base ptr

// ---- Minimap tracking slots (herb node entries) -----------
// Find Herbs populates minimap nodes; we scan object manager
// for OBJECT_TYPE_GAMEOBJECT with known herb entry IDs.
#define HERBALISM_TRACKING_FLAG    0x200  // unit flags bit for tracking

// ---- ClntObjMgr_GetActivePlayer --------------------------
#define FUNC_GET_LOCAL_GUID        0x00468550
#define FUNC_ENUMVISIBLE_OBJECTS   0x004D4B30
#define FUNC_GETOBJECTPTR          0x00468380
