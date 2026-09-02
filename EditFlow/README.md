# EditFlow 1.1.1

EditFlow is a native iPhone and iPad editor for short vertical edits. Version 1.1.1 adds direct multi-selection import from the system photo library, alongside real per-clip effects, still-photo rendering, transitions, keyframes, Speed Ramp, persistence, playback, and AVFoundation export.

## Requirements

- Xcode 16 or newer
- iOS or iPadOS 17 or newer
- A free or paid Apple developer team for installation on a physical device

## Open and run

1. Open `EditFlow.xcodeproj` in Xcode 16.
2. Select the `EditFlow` target.
3. In Signing & Capabilities, choose your Apple developer team.
4. Select an iPhone, iPad, or simulator and press Run.

The included `project.yml` can regenerate the project with XcodeGen:

```sh
brew install xcodegen
cd EditFlow
xcodegen generate
```

## IPA in GitHub Actions

The workflow builds and tests the simulator version, compiles a real device app, and uploads it as the `EditFlow-1.1.1-unsigned-IPA` artifact. The resulting IPA must be signed before installation on an ordinary iPhone. It is not a renamed source ZIP.

## Local data

Projects and imported copies of media files are stored under the app's Application Support directory. Source media stays on the device and is not uploaded to a server.
