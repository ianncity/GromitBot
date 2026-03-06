cmake_minimum_required(VERSION 3.20)

# ============================================================
# dll/CMakeLists.txt — builds GromitBot.dll
# ============================================================

set(SOURCES
    src/dllmain.cpp
    src/memory.cpp
    src/lua_bridge.cpp
    src/http_client.cpp
    src/hooks.cpp
)

add_library(GromitBot SHARED ${SOURCES})

# ---- Include dirs ------------------------------------------
target_include_directories(GromitBot PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include   # httplib.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src       # local headers
    ${LUA_INCLUDE_DIR}
    ${D3D8_INCLUDE_DIR}
)

# ---- Compiler options (MSVC) --------------------------------
if(MSVC)
    # /MT = static CRT (avoids CRT version mismatch inside WoW)
    target_compile_options(GromitBot PRIVATE
        /MT /O2 /W3
        /wd4996   # 'deprecated' warnings
        /EHa      # async exception handling (for __try/__except)
    )
    # Disable incremental linking in Release
    set_target_properties(GromitBot PROPERTIES
        LINK_FLAGS "/SAFESEH:NO /INCREMENTAL:NO"
    )
endif()

# ---- Link libraries ----------------------------------------
target_link_libraries(GromitBot PRIVATE
    ${LUA_LIB}
    d3d8
    ws2_32     # Winsock for cpp-httplib
    winhttp
)

# ---- Output name -------------------------------------------
set_target_properties(GromitBot PROPERTIES
    OUTPUT_NAME "GromitBot"
    SUFFIX ".dll"
    PREFIX ""
)

# ---- Injector executable ------------------------------------
add_executable(injector src/injector.cpp)

if(MSVC)
    target_compile_options(injector PRIVATE /MT /O2 /W3 /std:c++17 /EHsc)
    set_target_properties(injector PROPERTIES
        LINK_FLAGS "/INCREMENTAL:NO"
    )
endif()

set_target_properties(injector PROPERTIES
    OUTPUT_NAME "injector"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
