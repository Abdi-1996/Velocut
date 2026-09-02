# EditFlow 1.0.0

EditFlow is a native iPhone and iPad editor for short vertical edits. The current build is an honest functional foundation: projects, local media import, a multi-track timeline, clip operations, Speed Ramp, persistence, playback, and AVFoundation export are implemented.

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

## Signed IPA in GitHub Actions

The workflow always builds and tests the simulator version. The signed IPA job starts only when these repository secrets exist:

- `IOS_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISION_PROFILE_BASE64`
- `APPLE_TEAM_ID`

The workflow exports a real signed IPA and uploads it as the `EditFlow-1.0.0-IPA` artifact. It does not create a fake IPA from a renamed ZIP.

## Local data

Projects and imported copies of media files are stored under the app's Application Support directory. Source media stays on the device and is not uploaded to a server.

