import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EditorView: View {
    @StateObject var viewModel: EditorViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingImporter = false
    @State private var showingGallery = false
    @State private var gallerySelection: [PhotosPickerItem] = []
    @State private var selectedTool: EditorWorkspaceTool = .edit
    @State private var galleryTargetLayer = 0
    @State private var isPlaying = false

    private var importTypes: [UTType] { [.movie, .image, .audio] }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .navigationTitle(viewModel.project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { editorToolbar }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: importTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): viewModel.importFiles(urls)
            case .failure(let error): viewModel.errorMessage = error.localizedDescription
            }
        }
        .photosPicker(
            isPresented: $showingGallery,
            selection: $gallerySelection,
            maxSelectionCount: 50,
            selectionBehavior: .ordered,
            matching: .any(of: [.videos, .images]),
            preferredItemEncoding: .current
        )
        .onChange(of: gallerySelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await viewModel.importFromGallery(items, visualLayer: galleryTargetLayer)
                gallerySelection.removeAll()
            }
        }
        .sheet(isPresented: $viewModel.showingSpeedRamp) {
            SpeedRampSheet(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $viewModel.showingClipTools) {
            ClipToolsSheet(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $viewModel.showingExport) {
            ExportSheet(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .alert("EditFlow", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .background(Color.black.ignoresSafeArea())
        .onDisappear { viewModel.player.pause() }
        .overlay {
            if viewModel.isImporting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Импорт из галереи…")
                        .font(.subheadline.weight(.medium))
                }
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                viewModel.showingExport = true
            } label: {
                Label("Экспорт", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Экспорт")
            .disabled(viewModel.project.clips.allSatisfy { $0.kind == .audio })
        }
    }

    private var preview: some View {
        ZStack {
            Color(red: 0.055, green: 0.055, blue: 0.065)
            Group {
                if let clip = viewModel.selectedClip, clip.kind == .image,
                   let image = UIImage(contentsOfFile: viewModel.mediaURL(for: clip).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else if viewModel.player.currentItem == nil {
                    EmptyPreview()
                } else {
                    PlayerContainer(player: viewModel.player)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack {
                HStack {
                    Text(viewModel.project.aspectRatio.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: Capsule())
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            preview
                .frame(minHeight: 225, idealHeight: 280, maxHeight: 330)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            PlaybackControlBar(viewModel: viewModel, isPlaying: $isPlaying)
            TimelineView(viewModel: viewModel)
                .frame(minHeight: 185, idealHeight: 220)
            ContextToolBar(
                tool: selectedTool,
                viewModel: viewModel,
                galleryAction: openMainGallery,
                overlayAction: openOverlayGallery,
                fileAction: { showingImporter = true }
            )
            EditorToolDock(selection: $selectedTool)
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.042))
    }

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            MediaSidebar(viewModel: viewModel, importAction: { showingGallery = true })
                .frame(width: 220)
            VStack(spacing: 0) {
                preview
                PlaybackControlBar(viewModel: viewModel, isPlaying: $isPlaying)
                TimelineView(viewModel: viewModel)
                    .frame(height: 300)
                ContextToolBar(
                    tool: selectedTool,
                    viewModel: viewModel,
                    galleryAction: openMainGallery,
                    overlayAction: openOverlayGallery,
                    fileAction: { showingImporter = true }
                )
                EditorToolDock(selection: $selectedTool)
            }
            ClipInspector(viewModel: viewModel)
                .frame(width: 260)
        }
    }

    private func openMainGallery() {
        galleryTargetLayer = 0
        showingGallery = true
    }

    private func openOverlayGallery() {
        galleryTargetLayer = 1
        showingGallery = true
    }
}

enum EditorWorkspaceTool: String, CaseIterable, Identifiable {
    case edit = "Монтаж"
    case audio = "Аудио"
    case text = "Текст"
    case overlay = "Наложение"
    case effects = "Эффекты"
    case transitions = "Переходы"
    case color = "Цвет"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .edit: "slider.horizontal.3"
        case .audio: "music.note"
        case .text: "textformat"
        case .overlay: "square.on.square"
        case .effects: "sparkles"
        case .transitions: "rectangle.split.2x1"
        case .color: "circle.lefthalf.filled"
        }
    }
}

private struct PlaybackControlBar: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isPlaying: Bool

    var body: some View {
        HStack(spacing: 24) {
            Text(viewModel.playhead.formattedDuration)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Button {
                viewModel.playhead = max(0, viewModel.playhead - 1 / Double(viewModel.project.frameRate))
                viewModel.player.seek(to: .init(seconds: viewModel.playhead, preferredTimescale: 600))
            } label: { Image(systemName: "backward.frame.fill") }
            Button {
                isPlaying.toggle()
                if isPlaying {
                    viewModel.player.play()
                } else {
                    viewModel.player.pause()
                }
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
            }
            Button {
                viewModel.playhead = min(viewModel.project.duration, viewModel.playhead + 1 / Double(viewModel.project.frameRate))
                viewModel.player.seek(to: .init(seconds: viewModel.playhead, preferredTimescale: 600))
            } label: { Image(systemName: "forward.frame.fill") }
            Text(viewModel.project.duration.formattedDuration)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.9))
        .buttonStyle(.plain)
        .frame(height: 44)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
    }
}

private struct EditorToolDock: View {
    @Binding var selection: EditorWorkspaceTool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(EditorWorkspaceTool.allCases) { tool in
                    Button { selection = tool } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tool.icon).font(.system(size: 19))
                            Text(tool.rawValue).font(.caption2)
                        }
                        .foregroundStyle(selection == tool ? Color.white : Color.white.opacity(0.58))
                        .frame(minWidth: 68, minHeight: 54)
                        .background(selection == tool ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 66)
        .background(.ultraThinMaterial)
    }
}

private struct ContextToolBar: View {
    let tool: EditorWorkspaceTool
    @ObservedObject var viewModel: EditorViewModel
    let galleryAction: () -> Void
    let overlayAction: () -> Void
    let fileAction: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                switch tool {
                case .edit:
                    item("Добавить", "plus", galleryAction)
                    item("Разделить", "scissors") { viewModel.splitSelected(at: viewModel.playhead) }
                    item("Скорость", "gauge.with.dots.needle.67percent") { viewModel.showingSpeedRamp = true }
                    item("Копия", "plus.square.on.square") { viewModel.duplicateSelected() }
                    item("Без звука", "speaker.slash") { viewModel.toggleMuteSelected() }
                    item("Удалить", "trash") { viewModel.deleteSelected() }
                case .audio:
                    item("Импорт аудио", "music.note.list", fileAction)
                    item("Без звука", "speaker.slash") { viewModel.toggleMuteSelected() }
                case .text:
                    item("Добавить текст", "text.badge.plus") { viewModel.errorMessage = "Редактор текста появится в следующем обновлении." }
                case .overlay:
                    item("Добавить слой", "square.stack.3d.up.badge.plus", overlayAction)
                    item("Удалить", "trash") { viewModel.deleteSelected() }
                case .effects:
                    item("Настроить", "sparkles") { viewModel.showingClipTools = true }
                    item("Сбросить", "arrow.counterclockwise") { viewModel.resetEffects() }
                case .transitions:
                    item("Между клипами", "rectangle.split.2x1") { viewModel.showingClipTools = true }
                case .color:
                    item("Коррекция", "slider.horizontal.3") { viewModel.showingClipTools = true }
                    item("Сбросить", "arrow.counterclockwise") { viewModel.resetEffects() }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 58)
        .background(Color(red: 0.065, green: 0.065, blue: 0.075))
    }

    private func item(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16))
                Text(title).font(.caption2).lineLimit(1)
            }
            .frame(minWidth: 72, minHeight: 46)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedClip == nil && title != "Добавить" && title != "Импорт аудио" && title != "Добавить слой" && title != "Добавить текст")
    }
}

private struct MediaSidebar: View {
    @ObservedObject var viewModel: EditorViewModel
    let importAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Медиа").font(.headline)
                Spacer()
                Button(action: importAction) { Image(systemName: "plus") }
            }
            if viewModel.project.clips.isEmpty {
                Text("Добавьте клипы, фото или музыку.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.project.clips) { clip in
                            Button { viewModel.select(clip) } label: {
                                HStack {
                                    Image(systemName: clip.kind.icon)
                                        .frame(width: 28)
                                    VStack(alignment: .leading) {
                                        Text(clip.fileName).lineLimit(1)
                                        Text(clip.playbackDuration.formattedDuration)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(9)
                                .background(viewModel.selectedClipID == clip.id ? Color.blue.opacity(0.22) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

private struct ClipInspector: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        Form {
            if let clip = viewModel.selectedClip {
                Section("Выбранный клип") {
                    LabeledContent("Тип", value: clip.kind.rawValue.capitalized)
                    LabeledContent("Длительность", value: clip.playbackDuration.formattedDuration)
                    Toggle("Без звука", isOn: Binding(
                        get: { clip.isMuted },
                        set: { _ in viewModel.toggleMuteSelected() }
                    ))
                }
                Section("Обрезка") {
                    Slider(value: Binding(
                        get: { clip.trimStart },
                        set: { viewModel.setTrim(start: $0) }
                    ), in: 0...max(0.05, clip.trimEnd - 0.05))
                    Slider(value: Binding(
                        get: { clip.trimEnd },
                        set: { viewModel.setTrim(end: $0) }
                    ), in: min(clip.sourceDuration, clip.trimStart + 0.05)...clip.sourceDuration)
                }
                Section {
                    Button("Открыть Speed Ramp") { viewModel.showingSpeedRamp = true }
                    Button("Эффекты, переход и keyframes") { viewModel.showingClipTools = true }
                    Button("Удалить клип", role: .destructive) { viewModel.deleteSelected() }
                }
            } else {
                ContentUnavailableView("Клип не выбран", systemImage: "cursorarrow.click")
            }
        }
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
    }
}

extension MediaKind {
    var icon: String {
        switch self {
        case .video: "film"
        case .image: "photo"
        case .audio: "waveform"
        }
    }
}
