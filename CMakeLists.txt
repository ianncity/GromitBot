cmake_minimum_required(VERSION 3.20)
project(GromitBot CXX)

# ============================================================
# Top-level CMakeLists.txt
# ============================================================
# Prerequisites:
#   - Visual Studio 2022 (MSVC v143) — 32-bit target (i686)
#   - Windows SDK 10
#   - DirectX 8 SDK headers (for d3d8.h)
#   - Lua 5.1 headers + lib (matching WoW's embedded Lua build)
#
# Build:
#   cmake -B build -A Win32 -DLUA_INCLUDE_DIR="C:/lua51/include"
#                            -DLUA_LIB="C:/lua51/lua51.lib"
#                            -DD3D8_INCLUDE_DIR="C:/DXSDK/include"
#   cmake --build build --config Release
# ============================================================

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ---- Must build as 32-bit to inject into WoW.exe (x86) ----
if(NOT CMAKE_SIZEOF_VOID_P EQUAL 4)
    message(FATAL_ERROR "GromitBot DLL MUST be compiled as 32-bit (x86). "
                        "Pass -A Win32 to cmake or use a 32-bit toolchain.")
endif()

# ---- User-configurable paths --------------------------------
set(LUA_INCLUDE_DIR "" CACHE PATH "Path to Lua 5.1 headers")
set(LUA_LIB         "" CACHE FILEPATH "Path to lua51.lib")
set(D3D8_INCLUDE_DIR "" CACHE PATH "Path to DirectX 8 SDK include dir (for d3d8.h)")

add_subdirectory(dll)
