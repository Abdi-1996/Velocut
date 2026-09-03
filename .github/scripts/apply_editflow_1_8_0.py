from pathlib import Path

root = Path('.')
editor = root / 'EditFlow/EditFlow/Views/Editor/EditorView.swift'
vm = root / 'EditFlow/EditFlow/ViewModels/EditorViewModel.swift'
inline = root / 'EditFlow/EditFlow/Views/Editor/InlineEditorSettings.swift'
project = root / 'EditFlow/project.yml'
changelog = root / 'EditFlow/CHANGELOG.md'


def replace_once(path: Path, old: str, new: str):
    text = path.read_text()
    if old not in text:
        raise SystemExit(f'Pattern not found in {path}: {old[:120]!r}')
    path.write_text(text.replace(old, new, 1))

# ViewModel: contextual tool section + selection behavior.
replace_once(vm,
'''struct ClipMovePlacement: Equatable {
    var timelineStart: Double
    var layer: Int
    var snapGuide: Double?
}

@MainActor''',
'''struct ClipMovePlacement: Equatable {
    var timelineStart: Double
    var layer: Int
    var snapGuide: Double?
}

enum ClipToolsSection: String, CaseIterable, Identifiable {
    case effects = "Эффекты"
    case transition = "Переход"
    case animation = "Анимация"

    var id: String { rawValue }
}

@MainActor''')

replace_once(vm,
'''    @Published var showingSpeedRamp = false
    @Published var showingClipTools = false
    @Published var showingExport = false''',
'''    @Published var showingSpeedRamp = false
    @Published var showingClipTools = false
    @Published var clipToolsSection: ClipToolsSection = .effects
    @Published var showingExport = false''')

replace_once(vm,
'''        self.project = normalizedProject
        selectedClipID = normalizedProject.clips.first?.id
        playhead = min(normalizedProject.clips.first?.timelineStart ?? 0, normalizedProject.duration)''',
'''        self.project = normalizedProject
        selectedClipID = nil
        playhead = min(normalizedProject.clips.first?.timelineStart ?? 0, normalizedProject.duration)''')

replace_once(vm,
'''    func select(_ clip: MediaClip) {
        selectedClipID = clip.id
    }
''',
'''    func select(_ clip: MediaClip) {
        if selectedClipID != clip.id {
            closeInlineEditor()
        }
        selectedClipID = clip.id
    }

    func deselectClip() {
        closeInlineEditor()
        selectedClipID = nil
    }
''')

replace_once(vm,
'''    func openClipTools() {
        guard selectedClip != nil else { return }
        showingSpeedRamp = false
        showingClipTools = true
    }
''',
'''    func openClipTools(section: ClipToolsSection = .effects) {
        guard selectedClip != nil else { return }
        clipToolsSection = section
        showingSpeedRamp = false
        showingClipTools = true
    }
''')

replace_once(vm,
'''        project.clips.removeAll { $0.id == selectedClipID }
        self.selectedClipID = project.clips.first?.id
        compactPrimaryTrack()''',
'''        project.clips.removeAll { $0.id == selectedClipID }
        self.selectedClipID = nil
        closeInlineEditor()
        compactPrimaryTrack()''')

# EditorView: replace two-row toolbar runtime with one contextual bar.
replace_once(editor,
'''                ContextToolBar(
                    tool: selectedTool,
                    viewModel: viewModel,
                    galleryAction: openMainGallery,
                    overlayAction: openOverlayGallery,
                    audioGalleryAction: { showingAudioVideoGallery = true },
                    fileAction: { showingImporter = true }
                )

                EditorToolDock(selection: $selectedTool)''',
'''                ContextualEditorBar(
                    viewModel: viewModel,
                    galleryAction: openMainGallery,
                    overlayAction: openOverlayGallery,
                    audioGalleryAction: { showingAudioVideoGallery = true },
                    fileAction: { showingImporter = true }
                )''')

replace_once(editor,
'''                ContextToolBar(
                    tool: selectedTool,
                    viewModel: viewModel,
                    galleryAction: openMainGallery,
                    overlayAction: openOverlayGallery,
                    audioGalleryAction: { showingAudioVideoGallery = true },
                    fileAction: { showingImporter = true }
                )
                EditorToolDock(selection: $selectedTool)''',
'''                ContextualEditorBar(
                    viewModel: viewModel,
                    galleryAction: openMainGallery,
                    overlayAction: openOverlayGallery,
                    audioGalleryAction: { showingAudioVideoGallery = true },
                    fileAction: { showingImporter = true }
                )''')

marker = '''private struct EditorToolDock: View {'''
text = editor.read_text()
if marker not in text:
    raise SystemExit('EditorToolDock marker not found')
contextual = r'''private struct ContextualEditorBar: View {
    @ObservedObject var viewModel: EditorViewModel
    let galleryAction: () -> Void
    let overlayAction: () -> Void
    let audioGalleryAction: () -> Void
    let fileAction: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if let clip = viewModel.selectedClip {
                    item("Назад", "chevron.left") {
                        viewModel.deselectClip()
                    }

                    switch clip.kind {
                    case .video:
                        item("Разделить", "scissors") {
                            viewModel.splitSelected(at: viewModel.playhead)
                        }
                        item("Скорость", "gauge.with.dots.needle.67percent") {
                            viewModel.openSpeedRamp()
                        }
                        item(
                            clip.isMuted ? "Включить звук" : "Без звука",
                            clip.isMuted ? "speaker.wave.2" : "speaker.slash"
                        ) {
                            viewModel.toggleMuteSelected()
                        }
                        item("Эффекты", "sparkles") {
                            viewModel.openClipTools(section: .effects)
                        }
                        item("Переход", "rectangle.split.2x1") {
                            viewModel.openClipTools(section: .transition)
                        }
                        item("Анимация", "diamond") {
                            viewModel.openClipTools(section: .animation)
                        }
                        item("Копия", "plus.square.on.square") {
                            viewModel.duplicateSelected()
                        }
                        item("Удалить", "trash", role: .destructive) {
                            viewModel.deleteSelected()
                        }

                    case .image:
                        item("Эффекты", "sparkles") {
                            viewModel.openClipTools(section: .effects)
                        }
                        item("Анимация", "diamond") {
                            viewModel.openClipTools(section: .animation)
                        }
                        item("Копия", "plus.square.on.square") {
                            viewModel.duplicateSelected()
                        }
                        item("Удалить", "trash", role: .destructive) {
                            viewModel.deleteSelected()
                        }

                    case .audio:
                        item("Разделить", "scissors") {
                            viewModel.splitSelected(at: viewModel.playhead)
                        }
                        item(
                            clip.isMuted ? "Включить звук" : "Без звука",
                            clip.isMuted ? "speaker.wave.2" : "speaker.slash"
                        ) {
                            viewModel.toggleMuteSelected()
                        }
                        item("Копия", "plus.square.on.square") {
                            viewModel.duplicateSelected()
                        }
                        item("Удалить", "trash", role: .destructive) {
                            viewModel.deleteSelected()
                        }
                    }
                } else {
                    item("Медиа", "photo.on.rectangle.angled", galleryAction)
                    item("Файлы", "folder", fileAction)
                    item("Аудио из видео", "waveform.badge.plus", audioGalleryAction)
                    item("Наложение", "square.stack.3d.up.badge.plus", overlayAction)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 66)
        .background(.ultraThinMaterial)
        .animation(.easeOut(duration: 0.16), value: viewModel.selectedClipID)
    }

    private func item(
        _ title: String,
        _ icon: String,
        role: ButtonRole? = nil,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.white.opacity(0.9))
            .frame(minWidth: 72, minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

'''
editor.write_text(text.replace(marker, contextual + marker, 1))

# Inline editor: nested view reflects the exact tool button that opened it.
replace_once(inline,
'''                Image(systemName: "chevron.down")''',
'''                Image(systemName: "chevron.left")''')

replace_once(inline,
'''                Text(viewModel.showingSpeedRamp ? "Speed Ramp" : "Настройки клипа")''',
'''                Text(viewModel.showingSpeedRamp ? "Speed Ramp" : viewModel.clipToolsSection.rawValue)''')

replace_once(inline,
'''private struct InlineClipToolsEditor: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var section: ToolSection = .effects

    private enum ToolSection: String, CaseIterable, Identifiable {
        case effects = "Эффекты"
        case transition = "Переход"
        case animation = "Keyframes"
        var id: String { rawValue }
    }
''',
'''private struct InlineClipToolsEditor: View {
    @ObservedObject var viewModel: EditorViewModel
''')

replace_once(inline,
'''            Picker("Инструмент", selection: $section) {
                ForEach(ToolSection.allCases) { item in''',
'''            Picker("Инструмент", selection: $viewModel.clipToolsSection) {
                ForEach(ClipToolsSection.allCases) { item in''')

replace_once(inline,
'''                switch section {''',
'''                switch viewModel.clipToolsSection {''')

# Version/changelog.
replace_once(project,
'''    MARKETING_VERSION: 1.7.0
    CURRENT_PROJECT_VERSION: 19''',
'''    MARKETING_VERSION: 1.8.0
    CURRENT_PROJECT_VERSION: 20''')

text = changelog.read_text()
entry = '''## 1.8.0

### Added

- Added one CapCut-style contextual bottom toolbar that automatically switches between global project actions and controls for the selected video, image, or audio clip.
- Added a Back action in selected-object context to clear selection and return to the global project tools.
- Video context now exposes working Split, Speed Ramp, mute, Effects, Transition, Animation, Duplicate, and Delete actions from one row.
- Image and audio selections now receive their own relevant working tool sets instead of sharing a generic workspace dock.

### Changed

- Removed the two-row `ContextToolBar` + `EditorToolDock` runtime layout from iPhone and iPad and replaced it with one bottom interaction surface.
- Opening Effects, Transition, or Animation now opens the matching section directly inside the existing inline editor; its back button returns to the selected-object toolbar.
- Existing projects now open with no clip selected so the global bottom tools are visible first.

'''
if text.startswith('# Changelog\n\n'):
    text = '# Changelog\n\n' + entry + text[len('# Changelog\n\n'):]
else:
    raise SystemExit('Unexpected changelog header')
changelog.write_text(text)
