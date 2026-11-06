# Android-to-iOS source audit

This audit is based on the current repository source. It is a work list for the
platform split; it is not a claim that these files have already been ported.

## `native/main.cpp`

Android dependencies observed:
- `<android/log.h>` and `__android_log_*` for log forwarding.
- `<sys/system_properties.h>`, `PROP_VALUE_MAX`, and
  `__system_property_get` for device details.
- `SDL_GetAndroidSDKVersion()` for Android API reporting.
- `SDL_GetAndroidExternalStorageState/Path()` and
  `SDL_GetAndroidInternalStoragePath()` for the game data directory.
- `SDL_HINT_ANDROID_TRAP_BACK_BUTTON` and Android-specific ImGui backend name.
- Android-oriented comments and low-memory reporting.

iOS replacement:
- Use stderr/os_log for logging; do not redirect stderr to an Android logcat pipe.
- Report device/OS information using Apple APIs or omit nonessential fields.
- Resolve the writable app directory through SDL's iOS filesystem APIs or
  Foundation's Documents/Application Support directories.
- Keep the SDL foreground/background event handling, but test surface epoch
  and swapchain recreation on real device lifecycle transitions.
- Use SDL3's iOS entry point convention; confirm the SDL build's main callback
  configuration before deciding whether to retain a conventional `main()`.

## `native/game_files.cpp`

Android dependencies observed:
- `jni.h`, `SDL_GetAndroidJNIEnv()`, `SDL_GetAndroidActivity()`.
- Activity method `cardFolderPaths()`.
- Hard-coded `/storage/emulated/0/Black` and `/storage` paths.
- Android removable-volume enumeration.
- GNU/ELF assembly that places `europe.patch` in `.rodata` with
  `.incbin`.

iOS replacement:
- Add a document picker for ISO/XBE import, with security-scoped URL handling.
- Copy selected content into the app's sandbox before using existing
  filesystem-based disc code. Do not assume a Files-provider URL remains
  permanently accessible.
- Preserve the SHA-1 release validation and disc parser.
- Replace ELF inline assembly with a portable generated C++ byte-array source
  or an Apple-compatible linker section. A generated C++ array is preferable
  because it avoids assembler syntax and symbol differences.
- Make the no-game state actionable (show an import prompt) rather than relying
  on Android shared-storage discovery.

## `native/update.cpp`

The entire implementation calls methods on the Android Activity through JNI.
For iOS, either implement the update check in portable C++/SDL and present
results through the existing UI, or provide a small Objective-C++ bridge.
Persist the startup-check preference in the app's settings. Do not compile this
JNI implementation into the iOS target.

## `native/input.cpp`

The SDL gamepad path is portable and should remain. The `Loose` controller
adapter and its Android key-code mapping exist only for Android Activity input.
Exclude those JNI entry points on iOS; iOS controllers should arrive through
SDL3's GameController/Gamepad API. Retain touch controls and verify controller
button mapping, triggers, rumble, and disconnect behavior on iOS.

## `native/host.h`

The declarations are mostly platform-neutral despite Android-specific comments.
Keep this interface stable where possible; implement its window, foreground,
surface epoch, and wait behavior in a platform-specific host implementation.

## Renderer / build boundary

`native/vulkan.cpp` is the renderer and should not be replaced with SDL_Renderer
or a lower-fidelity graphics path. The iOS target must supply Vulkan headers,
loader symbols, and MoltenVK's iOS binary, and use the SDL3 iOS Vulkan surface.
The renderer's optional Vulkan features and pixel formats must be checked
against the exact MoltenVK version selected for the build.

## First implementation boundary

The safest first code change is to separate Android-only sources and
implementations from common renderer/game sources. Avoid broad search-and-replace
of Android calls: the game file importer, app lifecycle, update bridge, and
controller adapter each need different iOS behavior.
