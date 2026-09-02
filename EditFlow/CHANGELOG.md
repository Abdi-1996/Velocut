# Changelog

## 1.2.0

### Changed

- Rebuilt the iPhone editor as a compact CapCut-inspired workspace.
- Added a dedicated playback-control row between the canvas and timeline.
- Added bottom navigation for Edit, Audio, Text, Overlay, Effects, Transitions, and Color.
- Added contextual actions that change with the selected editing category.
- Restyled the multi-track timeline, clips, playhead, zoom control, and canvas.
- Overlay imports now go to their own visual layer.
- Export is now a prominent top action.

## 1.1.1

### Fixed

- Added direct multi-selection import from the iPhone and iPad photo library.
- Gallery videos and photos are copied into the project before the picker releases access.
- Added a visible import progress state and clearer gallery import errors.
- The add-media menu now separates Gallery from Files and audio.

## 1.1.0

### Added

- Per-clip brightness, contrast, saturation, temperature, vignette, and sharpen controls.
- Real Core Image effect rendering before final composition.
- Still-photo conversion to video frames during export.
- Cross-dissolve and fade-to-black transitions.
- Start/end keyframes for position, scale, and rotation.
- Adaptive project aspect-ratio rendering with letterboxing.
- Image preview in the editor.
- Compatibility test for projects created by version 1.0.0.

### Improved

- Primary-track timing now accounts for transition overlap.
- Export uses alternating video and audio tracks for cross-dissolves.
- Clip tools are grouped into a single iOS-style sheet.

## 1.0.0 — initial development build

### Added

- Native SwiftUI interface for iPhone and iPad with iOS 17 materials.
- Local project creation, persistence, duplication, and deletion.
- Import of video, image, and audio files through the system file picker.
- Multi-track timeline with selection, frame stepping, zoom, and playhead.
- Split, trim, duplicate, mute, and delete operations.
- Speed Ramp presets and editable rates.
- AVFoundation export with real segment time scaling.
- Optional save to Photos and system sharing.
- Unit tests for timing calculations.
- GitHub Actions workflow for simulator tests and signed IPA export.

### Known limitations

- Advanced masks, tracking, a full Bézier graph editor, and optical-flow interpolation are planned for later updates.
