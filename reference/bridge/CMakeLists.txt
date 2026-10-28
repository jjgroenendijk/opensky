# OpenSkyBridge: the SKSE plugin that lets OpenSky drive the Windows reference game
# (docs/tools/reference-game.md). Developer tooling only; no release builds or ships it.
# `reference/bridge/build.sh` configures this with `cmake/macos-clangcl.cmake`.
cmake_minimum_required(VERSION 3.28)
project(OpenSkyBridge LANGUAGES CXX)

include(FetchContent)
set(FETCHCONTENT_QUIET ON)

# Every download is pinned by SHA-256, at the versions the library was built with: the
# vcpkg baseline in its `vcpkg-configuration.json`. CommonLibSSE-NG is GPL-3.0-or-later with a
# modding exception; this plugin's own source stays Apache-2.0, which the GPL allows.
FetchContent_Declare(commonlib
    URL https://github.com/alandtse/CommonLibSSE-NG/releases/download/v15.0.1/commonlibsse-ng-prebuilt-v15.0.1-all-clangcl-cmake.zip
    URL_HASH SHA256=ff44a70e6d5810612f0442e8dfcffa3a1707aec4e60c4c56d62cd07bdc7ebed9)
FetchContent_Declare(fmt
    URL https://github.com/fmtlib/fmt/archive/refs/tags/12.2.0.tar.gz
    URL_HASH SHA256=8b852bb5aa6e7d8564f9e81394055395dd1d1936d38dfd3a17792a02bebd7af0)
FetchContent_Declare(spdlog
    URL https://github.com/gabime/spdlog/archive/refs/tags/v1.17.0.tar.gz
    URL_HASH SHA256=d8862955c6d74e5846b3f580b1605d2428b11d97a410d86e2fb13e857cd3a744)
FetchContent_Declare(directxmath
    URL https://github.com/microsoft/DirectXMath/archive/refs/tags/jun2026.tar.gz
    URL_HASH SHA256=cb46002679b16a25fd11d0a2a13f6a7c7bf9c51bf04258fb5485e5b839da8474)
FetchContent_Declare(directxtk
    URL https://github.com/microsoft/DirectXTK/archive/refs/tags/may2026.tar.gz
    URL_HASH SHA256=5aeb5ead8ab5c14fe56c7dd77e86e6310f102cf434ba30c0d00d565eab3d57d2)

# The library's objects call spdlog's compiled functions, which call fmt 12.
set(SPDLOG_FMT_EXTERNAL ON CACHE BOOL "" FORCE)
set(FMT_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(fmt spdlog)
FetchContent_Populate(commonlib)
FetchContent_Populate(directxmath)
FetchContent_Populate(directxtk)

add_library(OpenSkyBridge SHARED
    src/Channel.cpp
    src/Plugin.cpp
    src/State.cpp
    src/WineShim.cpp)
set_target_properties(OpenSkyBridge PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
    MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
target_include_directories(OpenSkyBridge SYSTEM PRIVATE
    "${commonlib_SOURCE_DIR}/include"
    "${commonlib_SOURCE_DIR}/extern/openvr/headers"
    "${directxmath_SOURCE_DIR}/Inc"
    "${directxtk_SOURCE_DIR}/Inc")
# The runtime set changes header layouts, so it must match the prebuilt library.
target_compile_definitions(OpenSkyBridge PRIVATE
    WINVER=0x0601
    _WIN32_WINNT=0x0601
    ENABLE_SKYRIM_SE=1
    ENABLE_SKYRIM_AE=1
    ENABLE_SKYRIM_VR=1
    HAS_SKYRIM_MULTI_TARGETING=1)
# The CommonLibSSE-NG headers expect this header first in every file.
target_compile_options(OpenSkyBridge PRIVATE /W4 /WX "/FI${CMAKE_CURRENT_SOURCE_DIR}/src/PCH.h")
target_link_libraries(OpenSkyBridge PRIVATE
    "${commonlib_SOURCE_DIR}/lib/CommonLibSSE.lib"
    "${commonlib_SOURCE_DIR}/lib/openvr_api.lib"
    spdlog::spdlog
    fmt::fmt
    advapi32 bcrypt d3d11 d3dcompiler dbghelp dxgi ole32 version)
