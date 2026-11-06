# iOS port notes

## Game files

The iOS build uses the app's Documents directory as its game-data directory. The app bundle enables iOS file sharing and opening documents in place, so after installing a signed build you can use the Files app:

1. Open **Files** → **On My iPhone** → **Black**.
2. Copy the legally obtained game image (`.iso`) into that folder. The extracted `default.xbe` and game data can also be placed there.
3. Launch Black. The host scans the Documents directory and its `assets` subfolder.

The app does not contain the commercial game image. The game data must be supplied by the user.

## Build

The Codemagic workflow builds the iOS app as an ARM64 Xcode bundle and links the iOS slice of `MoltenVK.xcframework`. The resulting IPA is currently unsigned. It must be signed with an Apple development/distribution certificate and provisioning profile before normal installation on an iPhone.

The iOS target uses SDL3's static target and keeps the existing Vulkan renderer; MoltenVK translates Vulkan to Apple's Metal API.
