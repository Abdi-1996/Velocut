# Changelog

## 1.7.0

### Added

- Added two-finger pinch zoom for the timeline time scale. The time under the initial pinch center stays anchored while zooming.
- Magnet mode now snaps clip movement, trim boundaries, and timeline scrubbing to whole-second grid points as well as compatible clip edges.

### Changed

- Move Mode now activates after a 0.5-second hold. Haptic feedback and the red clip outline appear only when Move Mode actually activates.
- The timeline header slider now changes track height instead of horizontal timeline length; clip thumbnails and waveform area resize with the track.
- Moved the primary playback controls (play from start, play/pause, loop, fullscreen) to the right side of the playback bar.
- Horizontal timeline zoom is now controlled by a two-finger pinch rather than the header slider.

## 1.6.9

### Added

- The large editor preview now shows the exact source frame under the active trim boundary while dragging a clip edge.
- Left-edge trimming previews the frame at the new `trimStart`; right-edge trimming previews the last included frame immediately before the new `trimEnd`.
- Added a cancellable, latest-request-wins trim frame generator so fast edge drags do not display stale frames.

### Changed

- Playback pauses during edge trimming and the normal playhead preview returns immediately after the trim gesture ends.
- Trim preview generation is local with AVFoundation and does not require network access.

## 1.6.8

### Fixed

- Replaced the two independent 44-point trim touch targets with one unified edge interaction layer for the selected clip.
- Left and right trim hit regions are dynamically limited to at most half the current clip width, so they can never overlap on short clips.
- The trim edge is locked from the initial touch position: the left half can only change trimStart and the right half can only change trimEnd until the finger is released.
- Timeline filmstrip thumbnails now follow the live displayClip during trimming, so trimming the beginning immediately shows the new first frames instead of visually looking like an end trim.
- Kept immediate touch-down ownership, magnetic snapping, haptic feedback, speed-ramp duration mapping, and the 0.8-second center long-press move gesture.

## 1.6.7

### Fixed

- Removed the selected clip trim handles from inside TimelineClipView and moved them to a dedicated top-level interaction layer on each timeline track.
- Edge trim controls now sit above clip tap, long-press movement, track labels, and timeline scrubbing layers so their touch area is no longer covered by SwiftUI overlays.
- Replaced the threshold-based edge pan with an immediate custom UIGestureRecognizer that enters Trim on touch-down and owns the finger until release.
- Left and right trim handles update the visual clip boundary continuously and commit the final trim once on release.
- Magnetic snapping and haptic feedback remain available, including accurate boundary resolution for speed-ramped clips.

## 1.6.6

### Fixed

- Replaced the edge-trim touch recognizer with a dedicated one-finger UIPanGestureRecognizer that directly tracks horizontal finger translation.
- Trim pan cannot be prevented by the timeline or clip-move recognizers, so selected clip edges keep ownership of the drag.
- Left trim now changes only trimStart and the visible left timeline boundary; right trim changes only trimEnd and the visible right boundary.
- Removed the second trim-resolution pass on release: the final locally previewed trim is committed directly to the project once.
- Simplified speed-ramp trim mapping to a direct source-time/timeline-time ratio for stable 1:1 edge movement.

## 1.6.5

### Fixed

- Completely separated selected-clip edge trim touch zones from the clip long-press move gesture.
- The center of a selected clip is now the only area that can start long-press movement; the left and right 44-point edge zones are reserved exclusively for trimming.
- Trim handles are promoted above clip interaction layers and use immediate UIKit touch capture without delayed touch delivery.

## 1.6.4

### Fixed

- Increased clip long-press move activation from 0.4 seconds to 0.8 seconds so edge trimming gets clear touch priority and accidental clip movement is avoided.

## 1.6.3

### Fixed

- Rebuilt clip-edge trimming around a dedicated touch-down recognizer so the trim handle owns the finger immediately, similar to CapCut mobile.
- Trim now uses a local visual preview while dragging instead of mutating project clip timing every pixel, preventing the handle from losing its gesture as the clip width changes.
- Left and right trim edges follow the finger in screen coordinates and commit source trim points only once on release.
- Magnetic trim snapping remains active and displays an orange alignment guide with haptic feedback.
- Speed-ramped clips now resolve trim boundaries from playback duration so the visible edge remains aligned with the finger.

### Changed

- Timeline scrolling and long-press clip movement are disabled from touch-down until the trim handle is released.

## 1.6.2

### Fixed

- Left and right clip-edge trim handles now own the drag gesture instead of allowing timeline scrubbing to steal the same touch.
- Added a dedicated trim interaction state that blocks horizontal scrubbing, vertical track scrolling, and long-press clip movement while an edge handle is active.
- Trim handles now use a full 44x44-point touch target while keeping the visible edge control compact.
- Releasing a trim handle immediately returns gesture control to the timeline.

## 1.6.1

### Fixed

- Timeline edge trim handles now track the finger in global coordinates so changing clip width no longer makes the drag jump or stall.
- Increased the effective touch area of the left and right trim handles for more reliable finger control.
- Trim preview now magnetically snaps to nearby compatible clip boundaries, preferring clips on the same track.
- Magnetic trim snapping preserves the correct source trim point even on speed-ramped clips.
- A short selection haptic fires only when the trim edge actually enters a snap target.
- Timeline thumbnail generation now coalesces rapid trim updates and abandons stale requests instead of queuing expensive frame extraction for every finger movement.

### Changed

- Intermediate trim frames reuse the most recent thumbnails while the newest request is prepared, keeping edge trimming responsive.
- Final trim data is still committed only when the finger is released.

## 1.6.0

### Added

- Added `Аудио → Из видео` to choose videos directly from the iPhone/iPad photo library.
- Selected videos are processed locally and their audio tracks are extracted to M4A before being added to the A1 timeline.
- Multiple gallery videos can be selected and converted to audio in one import operation.
- Added a dedicated progress state while audio is being extracted from gallery video.

### Fixed

- Long-press move mode now keeps the clip at its exact timeline width and height for the entire drag.
- Removed the blurred move glow that visually made the clip look larger while dragging.
- Move highlighting is now drawn inside the clip bounds with no scaling or implicit size animation.

### Changed

- Audio extraction is performed locally with AVFoundation and does not require an internet connection.
- Videos without an audio track now show a clear extraction error instead of adding an empty clip.

## 1.5.0

### Added

- Video clips now show cached frame thumbnails directly inside the timeline.
- Image clips show their source image inside the clip body.
- Audio clips use a lightweight waveform-style visual treatment.
- Clip move mode now displays a dashed ghost destination on the target track.
- Magnetic snapping now shows a visible vertical snap guide and haptic feedback.
- Added transport controls for Play from Start, Play/Pause, Loop, and Full Screen.
- Added a dedicated full-screen preview with compact playback controls.

### Fixed

- A normal tap only selects a clip and no longer enters move mode.
- Long-press move mode exits immediately when the finger is released or the gesture is cancelled.
- Entering move mode no longer scales the clip; the clip is highlighted in red with haptic feedback instead.
- Horizontal timeline scrubbing no longer moves the track area vertically.
- Horizontal and vertical timeline gestures now lock to one axis after the initial movement threshold.
- Manual V1 clip moves no longer get overwritten by automatic primary-track compaction on release.

### Changed

- Timeline clips are now rectangular with square edges and clearer trim handles.
- During drag only lightweight visual state changes; project timing and track data are committed once on release.
- Clip movement follows the finger while the ghost destination shows the exact snapped drop position.
- Video/image clips snap only against visual clip boundaries; audio clips snap against audio boundaries; all clips can snap to the fixed playhead.
- The transport controls are grouped on the left side of the preview toolbar for faster thumb access.

## 1.4.0

### Fixed

- Preview video now renders through a dedicated AVPlayerLayer while audio and video remain synchronized.
- Speed-ramped preview items now include an explicit video composition and preserve source orientation.
- Timeline playhead now follows actual AVPlayer playback time instead of staying visually frozen while audio plays.

### Added

- Long-press a clip to enter move mode with haptic feedback.
- Drag selected clips left or right to reposition them in time.
- Drag video and image clips vertically between V tracks.
- Drag audio clips vertically between A tracks.
- Magnetic snapping for clip start/end against the central playhead and neighboring clip boundaries.
- Extra empty destination tracks appear automatically when additional V/A layers are needed.

### Changed

- The Cut workspace frame, ruler, track headers, and central playhead remain stationary while timeline content moves underneath.
- Timeline panning is blocked while a clip is being moved so the workspace cannot drift accidentally.
- Legacy audio clips are migrated from the old shared layer numbering to dedicated A-track numbering.
- Embedded audio stays linked to its video clip when that video clip is moved.

## 1.3.1

### Fixed

- Speed Ramp now affects the editor preview instead of only changing clip timing data.
- Preview playback is built from the same segmented time-scaling logic used by export.
- Timeline scrubbing seeks inside the speed-ramped preview composition instead of mapping linearly to the source file.
- Frame stepping now goes through the timeline preview engine and respects the active clip under the playhead.
- Preview follows the media under the central Cut playhead rather than the selected clip.
- Still images under the playhead remain visible in Preview.

### Changed

- Speed Ramp settings now open inside the editor workspace instead of covering the whole screen.
- Effects, transitions, and keyframe settings now use the same inline workspace panel.
- Preview stays visible above the settings panel on iPhone and stays visible in the main canvas on iPad.

## 1.3.0

### Changed

- Rebuilt the timeline into a DaVinci Resolve Cut-inspired touch workflow.
- The red playhead is fixed in the center; dragging the timeline moves media beneath it.
- Removed the upper overview timeline completely.
- Selecting a clip now shows dedicated trim handles on both edges.
- Left and right trim handles use non-ripple trimming so the timeline viewport does not jump.
- Selecting a clip no longer moves the playhead.
- Added frame snapping plus optional magnetic snapping to clip boundaries.
- Timeline ruler and tracks now stay synchronized with the fixed playhead.
- Scrubbing seeks the active video under the playhead for responsive preview.

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
