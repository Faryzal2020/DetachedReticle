cmake_minimum_required(VERSION 3.22)

project(DetachedReticle VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build configuration options
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

include(FetchContent)

# Fetch RED4ext.SDK
FetchContent_Declare(
    RED4ext.SDK
    GIT_REPOSITORY https://github.com/WopsS/RED4ext.SDK.git
    GIT_TAG        master
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(RED4ext.SDK)

# Include directories
include_directories(
    src
    ${RED4ext.SDK_SOURCE_DIR}/include
)

# Source files
set(SOURCES
    src/Main.cpp
    src/Hooks/AnimationHook.cpp
    src/Hooks/AnimationHook.hpp
    src/Hooks/ShootingHook.cpp
    src/Hooks/ShootingHook.hpp
)

# Shared library (RED4ext Plugin DLL)
add_library(${PROJECT_NAME} SHARED ${SOURCES})

target_link_libraries(${PROJECT_NAME} PRIVATE
    RED4ext.SDK
)

target_compile_definitions(${PROJECT_NAME} PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
    DETACHED_RETICLE_EXPORTS
)

# Post-build copy directly to game directory if CYBERPUNK_ROOT environment variable is set
if(DEFINED ENV{CYBERPUNK_ROOT})
    set(GAME_PLUGIN_DIR "$ENV{CYBERPUNK_ROOT}/red4ext/plugins/${PROJECT_NAME}")
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${GAME_PLUGIN_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:${PROJECT_NAME}>" "${GAME_PLUGIN_DIR}/${PROJECT_NAME}.dll"
        COMMENT "Deploying ${PROJECT_NAME}.dll to ${GAME_PLUGIN_DIR}"
    )
endif()
