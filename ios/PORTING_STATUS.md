# iOS port status: SDL3 + MoltenVK

The iOS port is being developed on the separate `ios-moltenvk-port` branch.
The Android target remains in the build graph and the Vulkan renderer is retained.

## Implemented in the repository

- Split the top-level CMake target: Android continues to build the `main` shared
  library; iOS builds an arm64 `Black.app` bundle.
- Added an Objective-C++ bridge for the app's Documents directory.
- Guarded Android JNI, storage, system-property, logcat, and Activity-only code
  so those implementations are not compiled into the iOS target.
- Replaced the ELF-only embedded Europe patch assembly with a generated,
  portable C++ byte array.
- Added iOS MoltenVK framework/header integration and Vulkan portability
  enumeration/device-extension handling.
- Added an iOS Info.plist, Codemagic build workflow, and setup notes.
- Enabled iOS file sharing so game data can be copied through Files into
  **On My iPhone > Black**; the host scans Documents and its `assets` folder.

## Not yet verified

- No successful Xcode/Codemagic build has been recorded.
- No IPA has been produced or installed on a device.
- Vulkan surface creation, shader compilation, GPU feature/format compatibility,
  rendering, audio, touch/gamepad input, and suspend/resume have not been tested
  on a physical iPhone.
- The Codemagic workflow currently packages an **unsigned** IPA. A signing
  certificate and provisioning profile are required for normal installation.
- iOS update checking remains a platform stub; it does not claim to check for
  updates.
- The app uses Files file sharing rather than a native document-picker UI.

## Build requirements

The iOS workflow requires an Xbox game ISO supplied by the user through the
Codemagic environment variable `GAME_ISO_URL`, or an ISO already present in the
repository's `assets/` or `iso/` directory. The game image is not included in
the repository or app. The recompiled sources and XBE must come from the same
legally obtained game image.

Run the Codemagic workflow **Black iOS (unsigned)** on this branch to obtain the
first real build log. Fixes after that point should be driven by the actual
Xcode/CMake diagnostics rather than treating an untested configuration as
working.

## Release validation checklist

- [ ] Xcode successfully builds the arm64 iOS app bundle.
- [ ] The app bundle contains SDL3 and the correct iOS MoltenVK binary.
- [ ] The app launches on a real iPhone/iPad and creates a Vulkan surface.
- [ ] The game image is copied through Files and passes the expected image hash.
- [ ] The game boots and renders at the intended quality.
- [ ] Touch/gamepad input, audio, saves, and suspend/resume work.
- [ ] The IPA is signed with a valid Apple certificate/profile for installation.

This status distinguishes source changes from build and device verification.
