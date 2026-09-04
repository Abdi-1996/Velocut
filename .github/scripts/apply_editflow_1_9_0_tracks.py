from pathlib import Path

root = Path('.')
timeline_path = root / 'EditFlow/EditFlow/Views/Editor/TimelineView.swift'
editor_path = root / 'EditFlow/EditFlow/Views/Editor/EditorView.swift'
vm_path = root / 'EditFlow/EditFlow/ViewModels/EditorViewModel.swift'
project_path = root / 'EditFlow/project.yml'
changelog_path = root / 'EditFlow/CHANGELOG.md'

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f'{label}: expected 1 occurrence, found {count}')
    return text.replace(old, new, 1)

# ViewModel: shared selected-track state and destructive track deletion.
vm = vm_path.read_text()
vm = replace_once(
    vm,
    '    @Published var selectedClipID: UUID?\n',
    '    @Published var selectedClipID: UUID?\n    @Published var selectedTrackLayer: Int?\n',
    'selected track published state'
)

old_selection = '''    func select(_ clip: MediaClip) {
        if selectedClipID != clip.id {
            closeInlineEditor()
        }
        selectedClipID = clip.id
    }

    func deselectClip() {
        closeInlineEditor()
        selectedClipID = nil
    }
'''
new_selection = '''    func select(_ clip: MediaClip) {
        if selectedClipID != clip.id {
            closeInlineEditor()
        }
        selectedTrackLayer = nil
        selectedClipID = clip.id
    }

    func deselectClip() {
        closeInlineEditor()
        selectedClipID = nil
    }

    var selectedTrackName: String? {
        guard let layer = selectedTrackLayer else { return nil }
        if layer >= Self.audioLayerBase {
            return "A\\(layer - Self.audioLayerBase + 1)"
        }
        return "V\\(layer + 1)"
    }

    var selectedTrackClipCount: Int {
        guard let layer = selectedTrackLayer else { return 0 }
        return project.clips.filter { $0.layer == layer }.count
    }

    func selectTrack(_ layer: Int) {
        closeInlineEditor()
        selectedClipID = nil
        selectedTrackLayer = layer
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func deselectTrack() {
        selectedTrackLayer = nil
    }

    func deleteSelectedTrack() {
        guard let layer = selectedTrackLayer else { return }
        let deletingAudio = layer >= Self.audioLayerBase

        project.clips.removeAll { $0.layer == layer }

        for index in project.clips.indices {
            if deletingAudio {
                if project.clips[index].kind == .audio,
                   project.clips[index].layer > layer {
                    project.clips[index].layer -= 1
                }
            } else if project.clips[index].kind != .audio,
                      project.clips[index].layer > layer {
                project.clips[index].layer -= 1
            }
        }

        selectedTrackLayer = nil
        selectedClipID = nil
        closeInlineEditor()
        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
    }
'''
vm = replace_once(vm, old_selection, new_selection, 'track selection methods')
vm_path.write_text(vm)

# Timeline: remove always-empty extra lanes, add transient lane only while moving into it.
timeline = timeline_path.read_text()
old_tracks = '''    private var trackNumbers: [Int] {
        let visualLayers = viewModel.project.clips
            .filter { $0.kind != .audio }
            .map(\\.layer)
        let highestVisual = max(0, visualLayers.max() ?? 0)
        let visualTop = min(8, max(1, highestVisual + 1))
        let visuals = Array(stride(from: visualTop, through: 0, by: -1))

        let audioIndices = viewModel.project.clips
            .filter { $0.kind == .audio }
            .map { max(0, $0.layer - EditorViewModel.audioLayerBase) }
        let highestAudio = max(0, audioIndices.max() ?? 0)
        let audioTop = min(7, audioIndices.isEmpty ? 0 : highestAudio + 1)
        let audios = Array(0...audioTop).map { EditorViewModel.audioLayerBase + $0 }

        return visuals + audios
    }
'''
new_tracks = '''    private var trackNumbers: [Int] {
        var visualLayers = viewModel.project.clips
            .filter { $0.kind != .audio }
            .map(\\.layer)
        var audioIndices = viewModel.project.clips
            .filter { $0.kind == .audio }
            .map { max(0, $0.layer - EditorViewModel.audioLayerBase) }

        if let previewLayer = movePreview?.placement.layer {
            if previewLayer >= EditorViewModel.audioLayerBase {
                audioIndices.append(max(0, previewLayer - EditorViewModel.audioLayerBase))
            } else {
                visualLayers.append(max(0, previewLayer))
            }
        }

        let visuals: [Int]
        if let highestVisual = visualLayers.max() {
            let visualTop = min(8, max(0, highestVisual))
            visuals = Array(stride(from: visualTop, through: 0, by: -1))
        } else {
            visuals = []
        }

        let audios: [Int]
        if let highestAudio = audioIndices.max() {
            let audioTop = min(7, max(0, highestAudio))
            audios = Array(0...audioTop).map { EditorViewModel.audioLayerBase + $0 }
        } else {
            audios = []
        }

        return visuals + audios
    }
'''
timeline = replace_once(timeline, old_tracks, new_tracks, 'track numbers')

# Selected lane highlight.
timeline = replace_once(
    timeline,
    '                .fill(movePreview?.placement.layer == layer ? Color.red.opacity(0.055) : Color.white.opacity(0.025))\n',
    '''                .fill(
                    viewModel.selectedTrackLayer == layer
                        ? Color.blue.opacity(0.10)
                        : (movePreview?.placement.layer == layer ? Color.red.opacity(0.055) : Color.white.opacity(0.025))
                )
''',
    'track background highlight'
)

# Isolate all clip/trim/move content from the fixed name column.
marker = '''            if let preview = movePreview,
               preview.placement.layer == layer,
               let clip = viewModel.project.clips.first(where: { $0.id == preview.clipID }) {
'''
timeline = replace_once(
    timeline,
    marker,
    '''            ZStack(alignment: .leading) {
                if let preview = movePreview,
                   preview.placement.layer == layer,
                   let clip = viewModel.project.clips.first(where: { $0.id == preview.clipID }) {
''',
    'open masked track content group'
)

old_label = '''            Rectangle()
                .fill(Color(red: 0.072, green: 0.072, blue: 0.082))
                .frame(width: labelWidth)
                .overlay(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(layerName(layer))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))

                        Image(systemName: layer >= EditorViewModel.audioLayerBase ? "speaker.wave.1.fill" : "film.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                    .padding(.leading, 6)
                }
                .zIndex(2000)
'''
new_label = '''            }
            .mask(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: labelWidth)
                    Rectangle()
                        .fill(.white)
                }
            }

            Button {
                guard movingClipID == nil, trimmingClipID == nil, !isPinching else { return }
                viewModel.selectTrack(layer)
            } label: {
                Rectangle()
                    .fill(
                        viewModel.selectedTrackLayer == layer
                            ? Color.blue.opacity(0.28)
                            : Color(red: 0.072, green: 0.072, blue: 0.082)
                    )
                    .frame(width: labelWidth)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text(layerName(layer))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(
                                    viewModel.selectedTrackLayer == layer
                                        ? Color.white
                                        : Color.white.opacity(0.72)
                                )

                            Image(systemName: layer >= EditorViewModel.audioLayerBase ? "speaker.wave.1.fill" : "film.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    viewModel.selectedTrackLayer == layer
                                        ? Color.white.opacity(0.82)
                                        : Color.white.opacity(0.34)
                                )
                        }
                        .padding(.leading, 6)
                    }
            }
            .buttonStyle(.plain)
            .frame(width: labelWidth, height: rowHeight)
            .contentShape(Rectangle())
            .accessibilityLabel("Выбрать дорожку \\(layerName(layer))")
            .zIndex(10000)
'''
timeline = replace_once(timeline, old_label, new_label, 'fixed track label button')

# Keep snap guides out of the fixed label/name column too.
old_guide = '''                    .position(x: guideX, y: viewportHeight / 2)
                    .allowsHitTesting(false)
'''
new_guide = '''                    .position(x: guideX, y: viewportHeight / 2)
                    .mask(alignment: .leading) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: labelWidth)
                            Rectangle().fill(.white)
                        }
                    }
                    .allowsHitTesting(false)
'''
if timeline.count(old_guide) < 2:
    raise RuntimeError('snap guide mask: expected at least 2 guide blocks')
timeline = timeline.replace(old_guide, new_guide, 2)

# Stable lane targeting: only create a new lane when the finger crosses beyond the real top/bottom lane.
old_target = '''    private func moveTargetLayer(for verticalTranslation: CGFloat) -> Int {
        let validLanes = laneOrder.filter { layer in
            sourceClip.kind == .audio
                ? layer >= EditorViewModel.audioLayerBase
                : layer < EditorViewModel.audioLayerBase
        }

        guard !validLanes.isEmpty else {
            return sourceClip.layer
        }

        let sourceIndex = validLanes.firstIndex(of: sourceClip.layer) ?? 0
        let deltaRows = Int(
            (verticalTranslation / max(1, rowStride)).rounded()
        )
        let targetIndex = min(
            max(0, sourceIndex + deltaRows),
            validLanes.count - 1
        )

        return validLanes[targetIndex]
    }
'''
new_target = '''    private func moveTargetLayer(for verticalTranslation: CGFloat) -> Int {
        let deltaRows = Int(
            (verticalTranslation / max(1, rowStride)).rounded()
        )

        if sourceClip.kind == .audio {
            let highestIndex = viewModel.project.clips
                .filter { $0.kind == .audio }
                .map { max(0, $0.layer - EditorViewModel.audioLayerBase) }
                .max() ?? max(0, sourceClip.layer - EditorViewModel.audioLayerBase)
            let lanes = Array(0...max(0, highestIndex)).map { EditorViewModel.audioLayerBase + $0 }
            let sourceIndex = lanes.firstIndex(of: sourceClip.layer) ?? 0
            let rawTargetIndex = sourceIndex + deltaRows

            if rawTargetIndex >= lanes.count, highestIndex < 7 {
                return EditorViewModel.audioLayerBase + highestIndex + 1
            }

            return lanes[min(max(0, rawTargetIndex), lanes.count - 1)]
        }

        let highestVisual = viewModel.project.clips
            .filter { $0.kind != .audio }
            .map(\\.layer)
            .max() ?? sourceClip.layer
        let visualTop = min(8, max(0, highestVisual))
        let lanes = Array(stride(from: visualTop, through: 0, by: -1))
        let sourceIndex = lanes.firstIndex(of: sourceClip.layer) ?? 0
        let rawTargetIndex = sourceIndex + deltaRows

        if rawTargetIndex < 0, visualTop < 8 {
            return visualTop + 1
        }

        return lanes[min(max(0, rawTargetIndex), lanes.count - 1)]
    }
'''
timeline = replace_once(timeline, old_target, new_target, 'dynamic move target lane')
timeline_path.write_text(timeline)

# Editor: let the timeline consume free vertical space so the one bottom panel is pinned to the bottom.
editor = editor_path.read_text()
old_timeline_frame = '''            TimelineView(viewModel: viewModel)
                .frame(
                    minHeight: viewModel.hasInlineEditor ? 145 : 185,
                    idealHeight: viewModel.hasInlineEditor ? 165 : 220,
                    maxHeight: viewModel.hasInlineEditor ? 185 : 260
                )
'''
new_timeline_frame = '''            TimelineView(viewModel: viewModel)
                .frame(minHeight: viewModel.hasInlineEditor ? 145 : 185, maxHeight: .infinity)
                .layoutPriority(1)
'''
editor = replace_once(editor, old_timeline_frame, new_timeline_frame, 'pin bottom panel')

editor = replace_once(
    editor,
    '''private struct ContextualEditorBar: View {
    @ObservedObject var viewModel: EditorViewModel
''',
    '''private struct ContextualEditorBar: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var confirmingTrackDeletion = false
''',
    'track delete confirmation state'
)

editor = replace_once(
    editor,
    '''            HStack(spacing: 4) {
                if let clip = viewModel.selectedClip {
''',
    '''            HStack(spacing: 4) {
                if let trackLayer = viewModel.selectedTrackLayer {
                    item("Назад", "chevron.left") {
                        viewModel.deselectTrack()
                    }

                    let trackName = viewModel.selectedTrackName ?? (trackLayer >= EditorViewModel.audioLayerBase ? "A" : "V")
                    item("Удалить \\(trackName)", "trash", role: .destructive) {
                        if viewModel.selectedTrackClipCount == 0 {
                            viewModel.deleteSelectedTrack()
                        } else {
                            confirmingTrackDeletion = true
                        }
                    }
                } else if let clip = viewModel.selectedClip {
''',
    'track contextual toolbar'
)

old_bar_tail = '''        .frame(height: 66)
        .background(.ultraThinMaterial)
        .animation(.easeOut(duration: 0.16), value: viewModel.selectedClipID)
    }
'''
new_bar_tail = '''        .frame(height: 66)
        .background(.ultraThinMaterial)
        .animation(.easeOut(duration: 0.16), value: viewModel.selectedClipID)
        .animation(.easeOut(duration: 0.16), value: viewModel.selectedTrackLayer)
        .confirmationDialog(
            "Удалить дорожку \\(viewModel.selectedTrackName ?? "")?",
            isPresented: $confirmingTrackDeletion,
            titleVisibility: .visible
        ) {
            Button("Удалить дорожку", role: .destructive) {
                viewModel.deleteSelectedTrack()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все клипы на этой дорожке (\\(viewModel.selectedTrackClipCount)) будут удалены.")
        }
    }
'''
editor = replace_once(editor, old_bar_tail, new_bar_tail, 'track deletion dialog')
editor_path.write_text(editor)

# Version + changelog.
project = project_path.read_text()
project = replace_once(project, '    MARKETING_VERSION: 1.8.1\n', '    MARKETING_VERSION: 1.9.0\n', 'marketing version')
project = replace_once(project, '    CURRENT_PROJECT_VERSION: 21\n', '    CURRENT_PROJECT_VERSION: 22\n', 'build number')
project_path.write_text(project)

changelog = changelog_path.read_text()
entry = '''# Changelog

## 1.9.0

### Added

- Track names (`V1`, `V2`, `A1`, and so on) are now tappable and select the complete track.
- The contextual bottom panel now offers destructive whole-track deletion; occupied tracks require confirmation and all clips on that track are removed together.
- Dragging a clip beyond the current highest visual lane creates a temporary new lane only while needed; releasing the clip there makes that lane real.

### Changed

- Removed the permanently empty extra top visual/audio lane. The timeline now displays only the lanes required by actual project content plus a temporary move destination when needed.
- The contextual bottom surface is pinned to the bottom of the iPhone editor by allowing the timeline to consume the remaining vertical workspace.
- Track-name columns are now fixed interaction zones. Clip bodies, move previews, trim handles, and magnetic snap guides are masked so they cannot draw over `V/A` labels.
- Deleting a track closes gaps by renumbering higher tracks of the same media family while preserving clip timeline positions.

'''
if not changelog.startswith('# Changelog\n'):
    raise RuntimeError('unexpected changelog header')
changelog = entry + changelog[len('# Changelog\n\n'):]
changelog_path.write_text(changelog)
