# Black (original Xbox), statically recompiled for Android or iOS.
# The x86 code is recompiled on the host first: this build takes generated/game as it is, with the SDK's
# portable runtime, the game's sources in src and the SDL-based native host in native.

cmake_minimum_required(VERSION 3.22)
project(black LANGUAGES C CXX)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    enable_language(OBJCXX)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(REPO ${CMAKE_CURRENT_SOURCE_DIR})
set(NATIVE ${CMAKE_CURRENT_SOURCE_DIR}/native)
set(GAME ${CMAKE_CURRENT_SOURCE_DIR}/src)  # the game's hooks, sound, Direct3D 8 and settings

# the SDK: sdk/ in the repo, a checkout beside it, else downloaded
include(FetchContent)
if(EXISTS ${REPO}/sdk/cmake/XbeRecomp.cmake)
    set(SDK ${REPO}/sdk)
elseif(EXISTS ${REPO}/../XboxXBE-Recomp/cmake/XbeRecomp.cmake)
    get_filename_component(SDK ${REPO}/../XboxXBE-Recomp ABSOLUTE)
else()
    # pinned: the SDK's main moved to game code built into a DLL at first start (Windows), which this port's
    # recompiler step and libmain.so do not take; this is the commit v1.5.0 was built with
    FetchContent_Declare(xbe_sdk GIT_REPOSITORY https://github.com/TGP482/XboxXBE-Recomp.git
                         GIT_TAG 99078b119b5d5e0d1d6afb1390e29437c0c984c0)
    FetchContent_MakeAvailable(xbe_sdk)
    set(SDK ${xbe_sdk_SOURCE_DIR})
endif()

# Apple's pthread_setname_np API accepts only the thread name; the SDK's
# Linux implementation passes (pthread_t, name). Patch the fetched runtime
# source for iOS without changing the upstream SDK or Android builds.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(XBE_THREADS_SOURCE "${SDK}/runtime/kernel/threads.cpp")
    if(NOT EXISTS "${XBE_THREADS_SOURCE}")
        message(FATAL_ERROR "XBE SDK thread runtime source not found: ${XBE_THREADS_SOURCE}")
    endif()
    file(READ "${XBE_THREADS_SOURCE}" XBE_THREADS_CONTENT)
    set(XBE_PTHREAD_SETNAME_LINUX "pthread_setname_np(pthread_self(), name);")
    string(FIND "${XBE_THREADS_CONTENT}" "${XBE_PTHREAD_SETNAME_LINUX}" XBE_PTHREAD_SETNAME_POS)
    if(XBE_PTHREAD_SETNAME_POS EQUAL -1)
        message(FATAL_ERROR "Could not locate the SDK pthread_setname_np call for the iOS compatibility patch")
    endif()
    string(REPLACE "${XBE_PTHREAD_SETNAME_LINUX}"
        "#if defined(__APPLE__)\n    pthread_setname_np(name);\n#else\n    pthread_setname_np(pthread_self(), name);\n#endif"
        XBE_THREADS_CONTENT "${XBE_THREADS_CONTENT}")
    file(WRITE "${XBE_THREADS_SOURCE}" "${XBE_THREADS_CONTENT}")
endif()

# Linux provides memfd_create(), but Darwin/iOS does not. Use a temporary
# POSIX shared-memory object for the SDK's aliased physical RAM mappings.
# Unlink it immediately after opening so no filesystem artifact remains.
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(XBE_MEMORY_SOURCE "${SDK}/runtime/kernel/memory.cpp")
    if(NOT EXISTS "${XBE_MEMORY_SOURCE}")
        message(FATAL_ERROR "XBE SDK memory runtime source not found: ${XBE_MEMORY_SOURCE}")
    endif()
    file(READ "${XBE_MEMORY_SOURCE}" XBE_MEMORY_CONTENT)
    set(XBE_MEMFD_CALL "int fd = g_base ? memfd_create(\"ram\", 0) : -1;")
    string(FIND "${XBE_MEMORY_CONTENT}" "${XBE_MEMFD_CALL}" XBE_MEMFD_POS)
    if(XBE_MEMFD_POS EQUAL -1)
        message(FATAL_ERROR "Could not locate the SDK memfd_create call for the iOS compatibility patch")
    endif()
    string(REPLACE "#include <sys/mman.h>"
        "#include <sys/mman.h>\n#include <fcntl.h>\n#include <cerrno>\n#include <unistd.h>"
        XBE_MEMORY_CONTENT "${XBE_MEMORY_CONTENT}")
    string(REPLACE "${XBE_MEMFD_CALL}"
        "int fd = -1;\n    if (g_base) {\n        fd = shm_open(\"/black-port-ram\", O_CREAT | O_RDWR, 0600);\n        if (fd >= 0) shm_unlink(\"/black-port-ram\");\n    }"
        XBE_MEMORY_CONTENT "${XBE_MEMORY_CONTENT}")

    # iOS may reject a 4 GiB anonymous mapping when MAP_NORESERVE is requested
    # or when a fixed high-address hint is supplied. The guest runtime uses
    # offsets from g_base, so it does not require a particular host address.
    # Let Darwin choose an available contiguous range and use portable flags.
    set(XBE_GUEST_MMAP_CALL "void* p = mmap(reinterpret_cast<void*>(0x100000000ull), size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);")
    string(FIND "${XBE_MEMORY_CONTENT}" "${XBE_GUEST_MMAP_CALL}" XBE_GUEST_MMAP_POS)
    if(XBE_GUEST_MMAP_POS EQUAL -1)
        message(FATAL_ERROR "Could not locate the SDK 4 GB guest mmap call for the iOS compatibility patch")
    endif()
    string(REPLACE "${XBE_GUEST_MMAP_CALL}"
        "void* p = mmap(nullptr, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);"
        XBE_MEMORY_CONTENT "${XBE_MEMORY_CONTENT}")

    # Keep the SDK's original guest RAM mapping logic. The exact formatting of
    # that block differs across SDK revisions; diagnostics must not make CMake
    # configuration fail when the portable shm_open/mmap substitutions above
    # have already been applied.
    file(WRITE "${XBE_MEMORY_SOURCE}" "${XBE_MEMORY_CONTENT}")
endif()

# the recompiled code and the xbe it came from
set(XBE_GENERATED ${REPO}/generated/game CACHE PATH "the recompiled code of default.xbe")
set(XBE_IMAGE ${REPO}/assets/default.xbe CACHE FILEPATH "the xbe it was recompiled from")
set(GEN ${XBE_GENERATED})
set(XBE ${XBE_IMAGE})

# Embed the binary Europe patch as a portable C++ array. Inline assembler using
# .incbin/.rodata is ELF-specific and cannot be assembled by Apple's Mach-O toolchain.
find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(EUROPE_PATCH_HEADER ${CMAKE_CURRENT_BINARY_DIR}/generated/europe_patch.h)
add_custom_command(
    OUTPUT ${EUROPE_PATCH_HEADER}
    COMMAND ${Python3_EXECUTABLE} ${REPO}/tools/bin2c.py
            ${GAME}/common/europe.patch ${EUROPE_PATCH_HEADER}
    DEPENDS ${REPO}/tools/bin2c.py ${GAME}/common/europe.patch
    VERBATIM
)
if(NOT EXISTS ${GEN}/x86_func_mapping.cpp OR NOT EXISTS ${XBE})
    message(FATAL_ERROR "No recompiled code: put the game in assets/ or iso/ and run build.bat, it writes generated/game")
endif()
file(STRINGS ${REPO}/config/game.toml GAME_PARTITIONS REGEX "^partitions *=")
string(REGEX MATCH "[0-9]+" GAME_PARTITIONS "${GAME_PARTITIONS}")
math(EXPR last "${GAME_PARTITIONS} - 1")
set(GEN_SOURCES ${GEN}/x86_func_mapping.cpp)
foreach(i RANGE ${last})
    list(APPEND GEN_SOURCES ${GEN}/x86_recomp.${i}.cpp)
endforeach()
file(SHA1 ${XBE} xbe_sha1)
file(CONFIGURE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/image_sha1.cpp CONTENT "extern const char kImageSha1[] = \"${xbe_sha1}\";\n")
# the build's version for the log: the commit when the project is in git, else unknown
set(BUILD_COMMIT "unknown")
find_package(Git QUIET)
if(GIT_EXECUTABLE)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD WORKING_DIRECTORY ${REPO}
                    OUTPUT_VARIABLE head OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET RESULT_VARIABLE failed)
    if(NOT failed AND head)
        set(BUILD_COMMIT ${head})
    endif()
endif()
file(CONFIGURE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/build_info.h CONTENT "#define BLACK_COMMIT \"${BUILD_COMMIT}\"\n")

# dependencies: SDL3 from the checkout Gradle makes (its Java side goes into the APK), the rest fetched
set(SDL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/SDL)
if(NOT EXISTS ${SDL_DIR}/CMakeLists.txt)
    message(FATAL_ERROR "SDL3 is missing from ${SDL_DIR}: the Gradle build clones it")
endif()
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(SDL_SHARED OFF CACHE BOOL "" FORCE)
    set(SDL_STATIC ON CACHE BOOL "" FORCE)
    set(SDL_VULKAN ON CACHE BOOL "" FORCE)
else()
    set(SDL_SHARED ON CACHE BOOL "" FORCE)
    set(SDL_STATIC OFF CACHE BOOL "" FORCE)
endif()
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_RENDER OFF CACHE BOOL "" FORCE)
set(SDL_GPU OFF CACHE BOOL "" FORCE)
set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
add_subdirectory(${SDL_DIR} ${CMAKE_CURRENT_BINARY_DIR}/SDL EXCLUDE_FROM_ALL)

set(ENABLE_OPT OFF CACHE BOOL "" FORCE)
set(ENABLE_HLSL ON CACHE BOOL "" FORCE)
set(ENABLE_GLSLANG_BINARIES OFF CACHE BOOL "" FORCE)
set(ENABLE_SPVREMAPPER OFF CACHE BOOL "" FORCE)
set(GLSLANG_TESTS OFF CACHE BOOL "" FORCE)
set(GLSLANG_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(BUILD_EXTERNAL OFF CACHE BOOL "" FORCE)
FetchContent_Declare(glslang GIT_REPOSITORY https://github.com/KhronosGroup/glslang.git GIT_TAG 16.0.0 GIT_SHALLOW TRUE)
FetchContent_Declare(tomlplusplus GIT_REPOSITORY https://github.com/marzer/tomlplusplus.git GIT_TAG v3.4.0 GIT_SHALLOW TRUE)
FetchContent_Declare(imgui GIT_REPOSITORY https://github.com/ocornut/imgui.git GIT_TAG v1.91.0 GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(glslang tomlplusplus imgui)

# the SDK's runtime but its Windows parts, and those the game replaces (src/sound, src/d3d)
file(GLOB RUNTIME_SOURCES ${SDK}/runtime/*/*.cpp)
list(FILTER RUNTIME_SOURCES EXCLUDE REGEX
     "/runtime/app/|/core/input\\.cpp$|/gpu/(d3d12|render_thread)\\.cpp$|/audio/xaudio2\\.cpp$|/xdk/(dsound|d3d8)\\.cpp$")
# the game's sources: its hooks, sound, Direct3D 8 and settings
file(GLOB GAME_HOST_SOURCES CONFIGURE_DEPENDS ${GAME}/*/*.cpp)
file(GLOB HOST_SOURCES CONFIGURE_DEPENDS ${NATIVE}/*.cpp)
set(IMGUI_SOURCES ${imgui_SOURCE_DIR}/imgui.cpp ${imgui_SOURCE_DIR}/imgui_draw.cpp ${imgui_SOURCE_DIR}/imgui_tables.cpp
    ${imgui_SOURCE_DIR}/imgui_widgets.cpp ${imgui_SOURCE_DIR}/backends/imgui_impl_vulkan.cpp)

set(BLACK_SOURCES ${RUNTIME_SOURCES} ${GAME_HOST_SOURCES} ${HOST_SOURCES} ${GEN_SOURCES} ${IMGUI_SOURCES}
    ${CMAKE_CURRENT_BINARY_DIR}/image_sha1.cpp ${EUROPE_PATCH_HEADER})

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # iOS applications must be executables; a dynamically loaded library cannot own main().
    add_executable(Black MACOSX_BUNDLE ${BLACK_SOURCES} ${REPO}/ios/platform.mm)
    # Keep the existing vector artwork as a bundle resource. The repository
    # contains AppIcon.svg (not AppIcon.png); referencing a missing PNG stops
    # CMake generation before Xcode can build the app.
    set_source_files_properties(${REPO}/ios/AppIcon.svg PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    target_sources(Black PRIVATE ${REPO}/ios/AppIcon.svg)
    set(BLACK_TARGET Black)
    set_target_properties(Black PROPERTIES
        MACOSX_BUNDLE_INFO_PLIST "${REPO}/ios/Info.plist.in"
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.tsmaker.black"
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "15.0"
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO")
else()
    add_library(main SHARED ${BLACK_SOURCES})
    set(BLACK_TARGET main)
endif()
# compat/ for the SDK's x86 header, the SDK harness's for the Winsock and DXGI names its portable runtime uses
target_include_directories(${BLACK_TARGET} PRIVATE ${NATIVE}/compat ${SDK}/harness/compat ${NATIVE} ${GAME} ${SDK}/runtime ${GEN}
                           ${CMAKE_CURRENT_BINARY_DIR} ${CMAKE_CURRENT_BINARY_DIR}/generated ${glslang_SOURCE_DIR})
target_include_directories(${BLACK_TARGET} SYSTEM PRIVATE ${imgui_SOURCE_DIR})
# x86 chars are signed, as the game's code and the runtime were written for
target_compile_options(${BLACK_TARGET} PRIVATE -fno-strict-aliasing -fsigned-char)
set_source_files_properties(${HOST_SOURCES} ${RUNTIME_SOURCES} ${GAME_HOST_SOURCES} PROPERTIES
    COMPILE_OPTIONS "-include;${NATIVE}/compat/crt.h")
set_source_files_properties(${GEN_SOURCES} PROPERTIES
    COMPILE_OPTIONS "-O2;-w;-fno-strict-aliasing;-fsigned-char")
set_source_files_properties(${NATIVE}/vk_shader.cpp PROPERTIES COMPILE_DEFINITIONS ENABLE_HLSL)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(MOLTENVK_ROOT "" CACHE PATH "Root of the MoltenVK Release package")
    # The official MoltenVK iOS package ships a static XCFramework under
    # MoltenVK/static, while Vulkan headers are in the sibling MoltenVK/include.
    set(MOLTENVK_INCLUDE "${MOLTENVK_ROOT}/MoltenVK/include")
    set(MOLTENVK_XCFRAMEWORK "${MOLTENVK_ROOT}/MoltenVK/static/MoltenVK.xcframework")
    set(MOLTENVK_LIBRARY "${MOLTENVK_XCFRAMEWORK}/ios-arm64/libMoltenVK.a")
    if(NOT EXISTS "${MOLTENVK_XCFRAMEWORK}/Info.plist")
        message(FATAL_ERROR "MoltenVK static XCFramework not found at ${MOLTENVK_XCFRAMEWORK}")
    endif()
    if(NOT EXISTS "${MOLTENVK_INCLUDE}/vulkan/vulkan.h")
        message(FATAL_ERROR "MoltenVK Vulkan headers not found under ${MOLTENVK_INCLUDE}")
    endif()
    if(NOT EXISTS "${MOLTENVK_LIBRARY}")
        message(FATAL_ERROR "MoltenVK iOS arm64 static library not found at ${MOLTENVK_LIBRARY}")
    endif()
    target_include_directories(${BLACK_TARGET} SYSTEM PRIVATE "${MOLTENVK_INCLUDE}")
    target_link_libraries(${BLACK_TARGET} PRIVATE SDL3::SDL3-static tomlplusplus::tomlplusplus
        glslang glslang-default-resource-limits "${MOLTENVK_LIBRARY}"
        "-framework Metal" "-framework UIKit" "-framework QuartzCore" "-framework Foundation"
        "-framework CoreGraphics" "-framework ImageIO" "-framework IOSurface")
    target_link_options(${BLACK_TARGET} PRIVATE "-Wl,-dead_strip")
else()
    target_link_libraries(${BLACK_TARGET} PRIVATE SDL3::SDL3 tomlplusplus::tomlplusplus
        glslang glslang-default-resource-limits vulkan android log)
    # 16 KB pages, as Android 15 devices may have
    target_link_options(${BLACK_TARGET} PRIVATE -Wl,-z,max-page-size=16384)
endif()
