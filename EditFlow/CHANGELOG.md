# Changelog

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
