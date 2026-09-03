from pathlib import Path

root = Path('.')
timeline_path = root / 'EditFlow/EditFlow/Views/Editor/TimelineView.swift'
vm_path = root / 'EditFlow/EditFlow/ViewModels/EditorViewModel.swift'
editor_path = root / 'EditFlow/EditFlow/Views/Editor/EditorView.swift'
project_path = root / 'EditFlow/project.yml'
changelog_path = root / 'EditFlow/CHANGELOG.md'

timeline = timeline_path.read_text()
vm = vm_path.read_text()
editor = editor_path.read_text()
project = project_path.read_text()
changelog = changelog_path.read_text()

if 'MARKETING_VERSION: 1.7.0' in project:
    raise SystemExit(0)

# Timeline state: keep horizontal time zoom separate from track height.
timeline = timeline.replace(
'''    @State private var zoom: CGFloat = 78
    @State private var panOriginTime: Double?
    @State private var verticalOriginOffset: CGFloat?
    @State private var verticalOffset: CGFloat = 0
    @State private var panAxis: TimelinePanAxis?
    @State private var snappingEnabled = true
''',
'''    @State private var zoom: CGFloat = 78
    @State private var trackHeight: CGFloat = 50
    @State private var panOriginTime: Double?
    @State private var verticalOriginOffset: CGFloat?
    @State private var verticalOffset: CGFloat = 0
    @State private var panAxis: TimelinePanAxis?
    @State private var snappingEnabled = true
    @State private var isPinching = false
    @State private var pinchOriginZoom: CGFloat?
    @State private var pinchAnchorX: CGFloat?
    @State private var pinchAnchorTime: Double?
''')

timeline = timeline.replace(
'''    private let labelWidth: CGFloat = 44
    private let rowHeight: CGFloat = 50
    private let rowSpacing: CGFloat = 7
''',
'''    private let labelWidth: CGFloat = 44
    private let rowSpacing: CGFloat = 7

    private var rowHeight: CGFloat { trackHeight }
''')

old_geometry = '''                VStack(spacing: 0) {
                    ruler(width: proxy.size.width, playheadX: playheadX)

                    if viewModel.project.clips.isEmpty {
                        emptyTimeline(
                            playheadX: playheadX,
                            height: max(60, proxy.size.height - 28)
                        )
                    } else {
                        timelineTracks(
                            playheadX: playheadX,
                            viewportHeight: max(60, proxy.size.height - 28)
                        )
                    }
                }
'''
new_geometry = '''                VStack(spacing: 0) {
                    ruler(width: proxy.size.width, playheadX: playheadX)

                    if viewModel.project.clips.isEmpty {
                        emptyTimeline(
                            playheadX: playheadX,
                            height: max(60, proxy.size.height - 28)
                        )
                    } else {
                        timelineTracks(
                            playheadX: playheadX,
                            viewportHeight: max(60, proxy.size.height - 28)
                        )
                    }
                }
                .simultaneousGesture(
                    timelineMagnifyGesture(
                        viewportWidth: proxy.size.width,
                        playheadX: playheadX
                    )
                )
'''
if old_geometry not in timeline:
    raise SystemExit('geometry block not found')
timeline = timeline.replace(old_geometry, new_geometry, 1)

old_header = '''            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.white.opacity(0.42))

            Slider(value: $zoom, in: 38...150)
                .frame(maxWidth: 110)
                .tint(.white)
                .accessibilityLabel("Масштаб таймлайна")

            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.white.opacity(0.42))
'''
new_header = '''            Text("−H")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))

            Slider(value: $trackHeight, in: 38...82)
                .frame(maxWidth: 110)
                .tint(.white)
                .accessibilityLabel("Высота дорожек")

            Text("+H")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
'''
if old_header not in timeline:
    raise SystemExit('header zoom slider block not found')
timeline = timeline.replace(old_header, new_header, 1)

# One-finger pan is disabled while a two-finger pinch owns the timeline.
timeline = timeline.replace(
'                guard movingClipID == nil, trimmingClipID == nil else { return }',
'                guard movingClipID == nil, trimmingClipID == nil, !isPinching else { return }',
2
)

# Add pinch zoom centered at the original two-finger location.
marker = '''    private var rulerPanGesture: some Gesture {
'''
pinch_code = '''    private func timelineMagnifyGesture(
        viewportWidth: CGFloat,
        playheadX: CGFloat
    ) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard movingClipID == nil, trimmingClipID == nil else { return }

                if pinchOriginZoom == nil {
                    isPinching = true
                    pinchOriginZoom = zoom
                    let anchorX = min(max(labelWidth, value.startLocation.x), viewportWidth)
                    pinchAnchorX = anchorX
                    pinchAnchorTime = viewModel.playhead + Double((anchorX - playheadX) / max(1, zoom))
                    viewModel.pausePlayback()
                }

                guard let originZoom = pinchOriginZoom,
                      let anchorX = pinchAnchorX,
                      let anchorTime = pinchAnchorTime else { return }

                let newZoom = min(220, max(30, originZoom * value.magnification))
                zoom = newZoom

                let anchoredPlayhead = anchorTime - Double((anchorX - playheadX) / max(1, newZoom))
                viewModel.playhead = min(
                    max(0, anchoredPlayhead),
                    max(0, viewModel.project.duration)
                )
            }
            .onEnded { _ in
                let finalTime = viewModel.playhead
                isPinching = false
                pinchOriginZoom = nil
                pinchAnchorX = nil
                pinchAnchorTime = nil
                viewModel.scrubTimeline(to: finalTime)
            }
    }

'''
if marker not in timeline:
    raise SystemExit('rulerPan marker not found')
timeline = timeline.replace(marker, pinch_code + marker, 1)

# Timeline scrub snapping: clip edges + whole seconds.
old_snap_time = '''        let candidates = viewModel.project.clips.flatMap { [$0.timelineStart, $0.timelineEnd] }

        if let nearest = candidates.min(by: { abs($0 - time) < abs($1 - time) }),
           abs(nearest - time) <= 0.08 {
            return nearest
        }

        return time
'''
new_snap_time = '''        var candidates = viewModel.project.clips.flatMap { [$0.timelineStart, $0.timelineEnd] }
        candidates.append(time.rounded())
        let threshold = min(0.20, max(0.04, Double(10 / max(1, zoom))))

        if let nearest = candidates.min(by: { abs($0 - time) < abs($1 - time) }),
           abs(nearest - time) <= threshold {
            return min(max(0, nearest), duration)
        }

        return time
'''
if old_snap_time not in timeline:
    raise SystemExit('snappedTime block not found')
timeline = timeline.replace(old_snap_time, new_snap_time, 1)

# Move mode delay to 0.5 seconds. Existing activation already produces haptic + red outline.
timeline = timeline.replace(
'LongPressGesture(minimumDuration: 0.80, maximumDistance: 12)',
'LongPressGesture(minimumDuration: 0.50, maximumDistance: 12)'
)

# Unified trim magnet: also snap to whole seconds.
old_trim_tail = '''        if let nearest = otherTargets.min(by: { abs($0 - clamped) < abs($1 - clamped) }),
           abs(nearest - clamped) <= threshold,
           nearest >= minimum,
           nearest <= maximum {
            return (nearest, nearest)
        }

        return (clamped, nil)
'''
new_trim_tail = '''        if let nearest = otherTargets.min(by: { abs($0 - clamped) < abs($1 - clamped) }),
           abs(nearest - clamped) <= threshold,
           nearest >= minimum,
           nearest <= maximum {
            return (nearest, nearest)
        }

        let wholeSecond = clamped.rounded()
        if abs(wholeSecond - clamped) <= threshold,
           wholeSecond >= minimum,
           wholeSecond <= maximum {
            return (wholeSecond, wholeSecond)
        }

        return (clamped, nil)
'''
# Replace the last/current unified occurrence only by locating after TimelineUnifiedTrimOverlay.
unified_index = timeline.find('private struct TimelineUnifiedTrimOverlay')
if unified_index < 0:
    raise SystemExit('unified trim overlay not found')
prefix, suffix = timeline[:unified_index], timeline[unified_index:]
if old_trim_tail not in suffix:
    raise SystemExit('unified trim snap tail not found')
suffix = suffix.replace(old_trim_tail, new_trim_tail, 1)
timeline = prefix + suffix

# Move snapping: clip edges, playhead, and whole-second grid for either clip edge.
old_move_targets = '''        let targets = compatibleTargets + [playhead]

        for target in targets {
'''
new_move_targets = '''        let wholeSecondTargets = [start.rounded(), (start + duration).rounded()]
        let targets = compatibleTargets + [playhead] + wholeSecondTargets

        for target in targets {
'''
if old_move_targets not in vm:
    raise SystemExit('move targets block not found')
vm = vm.replace(old_move_targets, new_move_targets, 1)

# Transport: time/frame stepping on the left, primary playback group on the right.
old_transport = '''        HStack(spacing: 10) {
            transportButton("backward.end.fill", label: "Воспроизвести с начала") {
                viewModel.playFromStart()
            }

            transportButton(
                viewModel.isPlaying ? "pause.fill" : "play.fill",
                label: viewModel.isPlaying ? "Пауза" : "Воспроизвести",
                emphasized: true
            ) {
                viewModel.togglePlayback()
            }

            Button {
                viewModel.toggleLoop()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(viewModel.isLooping ? Color.orange : Color.white.opacity(0.88))
                    .frame(width: 32, height: 32)
                    .background(viewModel.isLooping ? Color.orange.opacity(0.14) : Color.white.opacity(0.055))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isLooping ? "Отключить цикл" : "Включить цикл")

            transportButton("arrow.up.left.and.arrow.down.right", label: "Полный экран") {
                fullScreenAction()
            }

            Spacer(minLength: 4)

            Button { viewModel.stepFrame(-1) } label: {
                Image(systemName: "backward.frame.fill")
            }
            .accessibilityLabel("Предыдущий кадр")

            Button { viewModel.stepFrame(1) } label: {
                Image(systemName: "forward.frame.fill")
            }
            .accessibilityLabel("Следующий кадр")

            Text("\\(viewModel.playhead.formattedDuration) / \\(viewModel.project.duration.formattedDuration)")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
'''
new_transport = '''        HStack(spacing: 10) {
            Text("\\(viewModel.playhead.formattedDuration) / \\(viewModel.project.duration.formattedDuration)")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Button { viewModel.stepFrame(-1) } label: {
                Image(systemName: "backward.frame.fill")
            }
            .accessibilityLabel("Предыдущий кадр")

            Button { viewModel.stepFrame(1) } label: {
                Image(systemName: "forward.frame.fill")
            }
            .accessibilityLabel("Следующий кадр")

            Spacer(minLength: 4)

            transportButton("backward.end.fill", label: "Воспроизвести с начала") {
                viewModel.playFromStart()
            }

            transportButton(
                viewModel.isPlaying ? "pause.fill" : "play.fill",
                label: viewModel.isPlaying ? "Пауза" : "Воспроизвести",
                emphasized: true
            ) {
                viewModel.togglePlayback()
            }

            Button {
                viewModel.toggleLoop()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(viewModel.isLooping ? Color.orange : Color.white.opacity(0.88))
                    .frame(width: 32, height: 32)
                    .background(viewModel.isLooping ? Color.orange.opacity(0.14) : Color.white.opacity(0.055))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isLooping ? "Отключить цикл" : "Включить цикл")

            transportButton("arrow.up.left.and.arrow.down.right", label: "Полный экран") {
                fullScreenAction()
            }
        }
'''
if old_transport not in editor:
    raise SystemExit('transport block not found')
editor = editor.replace(old_transport, new_transport, 1)

project = project.replace('MARKETING_VERSION: 1.6.9', 'MARKETING_VERSION: 1.7.0')
project = project.replace('CURRENT_PROJECT_VERSION: 18', 'CURRENT_PROJECT_VERSION: 19')

entry = '''## 1.7.0

### Added

- Added two-finger pinch zoom for the timeline time scale. The time under the initial pinch center stays anchored while zooming.
- Magnet mode now snaps clip movement, trim boundaries, and timeline scrubbing to whole-second grid points as well as compatible clip edges.

### Changed

- Move Mode now activates after a 0.5-second hold. Haptic feedback and the red clip outline appear only when Move Mode actually activates.
- The timeline header slider now changes track height instead of horizontal timeline length; clip thumbnails and waveform area resize with the track.
- Moved the primary playback controls (play from start, play/pause, loop, fullscreen) to the right side of the playback bar.
- Horizontal timeline zoom is now controlled by a two-finger pinch rather than the header slider.

'''
changelog = changelog.replace('# Changelog\n\n', '# Changelog\n\n' + entry, 1)

timeline_path.write_text(timeline)
vm_path.write_text(vm)
editor_path.write_text(editor)
project_path.write_text(project)
changelog_path.write_text(changelog)
