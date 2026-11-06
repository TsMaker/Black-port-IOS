# iOS port status: SDL3 + MoltenVK

This directory tracks the iOS migration separately from the existing Android host.
The Android build remains the reference implementation; do not remove Android
sources or weaken the Vulkan renderer to make an iOS build pass.

## Current status

The repository is not yet an iOS-buildable application. The current top-level
CMake project creates an Android shared library and links Android system
libraries. The current native host also contains Android JNI, logcat,
system-property, and shared-storage calls.

The renderer in `native/vulkan.cpp` is a Vulkan renderer and should be retained.
On iOS, Vulkan must be provided by MoltenVK and presented through SDL3's iOS
Metal-backed Vulkan surface. This is not the same as linking the Android Vulkan
loader.

## Required migration work

1. **Build graph**
   - Split the Android and iOS targets in the top-level CMake configuration.
   - Keep the Android target and its link libraries unchanged.
   - Build an iOS app/bundle for arm64; do not produce an Android-style
     `libmain.so`.
   - Integrate SDL3 and the iOS MoltenVK/Vulkan SDK artifacts for the selected
     Xcode toolchain.
   - Link the Vulkan loader/MoltenVK and the required Apple frameworks.

2. **Host/platform layer**
   - Keep Android-only JNI code behind Android-specific compilation.
   - Implement iOS equivalents for logging, device/system information,
     lifecycle/foreground state, app settings, and writable directories.
   - Use SDL3/iOS APIs for windowing, touch, controller input, and sensors.
   - Remove Android JNI entry points from the iOS target.

3. **Game file import**
   - Replace Android shared-storage scanning with an iOS document-picker flow.
   - Copy user-selected ISO/XBE files into the app's sandbox and persist their
     security-scoped access correctly.
   - Store saves, settings, logs, and shader/pipeline caches in writable
     Application Support or Caches directories.
   - Do not bundle copyrighted game data in the app.

4. **Recompiler output**
   - The game-specific generated C++ sources are required by CMake.
   - The recompiler toolchain and the matching `assets/default.xbe` must be
     available before the app target can compile.
   - The generated sources and XBE must correspond to the same game image.
   - Do not create empty placeholder generated directories to bypass this check.

5. **Vulkan compatibility**
   - Request instance extensions through SDL3 for the actual iOS surface.
   - Verify MoltenVK supports every Vulkan feature/format used by the renderer.
   - Preserve the current renderer and shaders; use feature fallbacks only where
     MoltenVK lacks a capability.
   - Validate surface recreation, app suspend/resume, swapchain recreation,
     shader compilation, texture formats, and pipeline cache persistence.

## Known Android-only files / code identified so far

- `native/main.cpp`: Android logcat, system properties, external/internal
  storage paths, Android low-memory handling, and Android platform labels.
- `native/game_files.cpp`: JNI activity folder access and Android storage
  volume scanning; its ELF assembly section for the embedded Europe patch also
  needs a Mach-O-compatible implementation.
- `native/input.cpp`: Android JNI loose-key/axis/release entry points.
- `native/update.cpp`: JNI calls into the Android Activity.
- `CMakeLists.txt`: Android shared-library target and Android system links.

## IPA release criteria

An IPA is considered produced only after all of the following are true:

- Xcode successfully builds an arm64 iOS app bundle.
- The app bundle contains SDL3 and the correct iOS MoltenVK binaries.
- The app launches on a real iPhone/iPad and creates a Vulkan surface.
- The game image is imported from Files and passes the expected image hash.
- The game boots and renders; input, audio, suspend/resume, and storage work.
- The IPA is packaged with a valid app bundle. Signing is a separate requirement
  for installation on a physical device; an unsigned IPA is not installable as-is.

This file records verified repository blockers and the intended migration path.
It does not claim that an iOS build or IPA has succeeded.
