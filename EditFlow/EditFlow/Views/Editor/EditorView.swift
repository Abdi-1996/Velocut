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
    @State private var isFullScreen = false

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
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importTypes,
            allowsMultipleSelection: true
        ) { result in
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
        .sheet(isPresented: $viewModel.showingExport) {
            ExportSheet(viewModel: viewModel)
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            FullScreenPreview(viewModel: viewModel, isPresented: $isFullScreen)
        }
        .alert(
            "EditFlow",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .background(Color.black.ignoresSafeArea())
        .onDisappear {
            if !isFullScreen {
                viewModel.pausePlayback()
            }
        }
        .overlay {
            if viewModel.isImporting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Импорт из галереи…")
                        .font(.subheadline.weight(.medium))
                }
                .padding(22)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
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
            PreviewMediaSurface(viewModel: viewModel, imagePadding: 12)

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

            PlaybackControlBar(
                viewModel: viewModel,
                fullScreenAction: { isFullScreen = true }
            )

            if viewModel.hasInlineEditor {
                InlineEditorSettings(viewModel: viewModel)
                    .frame(minHeight: 245, idealHeight: 300, maxHeight: 360)
            } else {
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
        }
        .background(Color(red: 0.035, green: 0.035, blue: 0.042))
    }

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            MediaSidebar(viewModel: viewModel, importAction: { showingGallery = true })
                .frame(width: 220)

            VStack(spacing: 0) {
                preview
                PlaybackControlBar(
                    viewModel: viewModel,
                    fullScreenAction: { isFullScreen = true }
                )
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

            if viewModel.hasInlineEditor {
                InlineEditorSettings(viewModel: viewModel)
                    .frame(width: 330)
            } else {
                ClipInspector(viewModel: viewModel)
                    .frame(width: 260)
            }
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

private struct PreviewMediaSurface: View {
    @ObservedObject var viewModel: EditorViewModel
    let imagePadding: CGFloat

    var body: some View {
        Group {
            if let clip = viewModel.previewClip,
               clip.kind == .image,
               let image = UIImage(contentsOfFile: viewModel.mediaURL(for: clip).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(imagePadding)
            } else if viewModel.player.currentItem == nil {
                EmptyPreview()
            } else {
                PlayerContainer(player: viewModel.player)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(Rectangle())
    }
}

private struct PlaybackControlBar: View {
    @ObservedObject var viewModel: EditorViewModel
    let fullScreenAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
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

            Text("\(viewModel.playhead.formattedDuration) / \(viewModel.project.duration.formattedDuration)")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 10)
        .foregroundStyle(.white.opacity(0.9))
        .buttonStyle(.plain)
        .frame(height: 44)
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
    }

    private func transportButton(
        _ systemName: String,
        label: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: emphasized ? 18 : 15, weight: .semibold))
                .frame(width: emphasized ? 36 : 32, height: 32)
                .background(emphasized ? Color.white.opacity(0.10) : Color.white.opacity(0.055))
        }
        .accessibilityLabel(label)
    }
}

private struct FullScreenPreview: View {
    @ObservedObject var viewModel: EditorViewModel
    @Binding var isPresented: Bool
    @State private var controlsVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PreviewMediaSurface(viewModel: viewModel, imagePadding: 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.16)) {
                        controlsVisible.toggle()
                    }
                }

            if controlsVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .frame(width: 42, height: 42)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Закрыть полный экран")
                    }
                    .padding()

                    Spacer()

                    HStack(spacing: 18) {
                        Button { viewModel.playFromStart() } label: {
                            Image(systemName: "backward.end.fill")
                        }

                        Button { viewModel.togglePlayback() } label: {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .frame(width: 44, height: 44)
                        }

                        Button { viewModel.toggleLoop() } label: {
                            Image(systemName: "repeat")
                                .foregroundStyle(viewModel.isLooping ? Color.orange : Color.white)
                        }

                        Text("\(viewModel.playhead.formattedDuration) / \(viewModel.project.duration.formattedDuration)")
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 28)
                }
                .foregroundStyle(.white)
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
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
                            Image(systemName: tool.icon)
                                .font(.system(size: 19))
                            Text(tool.rawValue)
                                .font(.caption2)
                        }
                        .foregroundStyle(selection == tool ? Color.white : Color.white.opacity(0.58))
                        .frame(minWidth: 68, minHeight: 54)
                        .background(
                            selection == tool ? Color.white.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
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
                    item("Скорость", "gauge.with.dots.needle.67percent") { viewModel.openSpeedRamp() }
                    item("Копия", "plus.square.on.square") { viewModel.duplicateSelected() }
                    item("Без звука", "speaker.slash") { viewModel.toggleMuteSelected() }
                    item("Удалить", "trash") { viewModel.deleteSelected() }

                case .audio:
                    item("Импорт аудио", "music.note.list", fileAction)
                    item("Без звука", "speaker.slash") { viewModel.toggleMuteSelected() }

                case .text:
                    item("Добавить текст", "text.badge.plus") {
                        viewModel.errorMessage = "Редактор текста появится в следующем обновлении."
                    }

                case .overlay:
                    item("Добавить слой", "square.stack.3d.up.badge.plus", overlayAction)
                    item("Удалить", "trash") { viewModel.deleteSelected() }

                case .effects:
                    item("Настроить", "sparkles") { viewModel.openClipTools() }
                    item("Сбросить", "arrow.counterclockwise") { viewModel.resetEffects() }

                case .transitions:
                    item("Между клипами", "rectangle.split.2x1") { viewModel.openClipTools() }

                case .color:
                    item("Коррекция", "slider.horizontal.3") { viewModel.openClipTools() }
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
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(minWidth: 72, minHeight: 46)
        }
        .buttonStyle(.plain)
        .disabled(
            viewModel.selectedClip == nil &&
            title != "Добавить" &&
            title != "Импорт аудио" &&
            title != "Добавить слой" &&
            title != "Добавить текст"
        )
    }
}

private struct MediaSidebar: View {
    @ObservedObject var viewModel: EditorViewModel
    let importAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Медиа")
                    .font(.headline)
                Spacer()
                Button(action: importAction) {
                    Image(systemName: "plus")
                }
            }

            if viewModel.project.clips.isEmpty {
                Text("Добавьте клипы, фото или музыку.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.project.clips) { clip in
                            Button {
                                viewModel.select(clip)
                            } label: {
                                HStack {
                                    Image(systemName: clip.kind.icon)
                                        .frame(width: 28)
                                    VStack(alignment: .leading) {
                                        Text(clip.fileName)
                                            .lineLimit(1)
                                        Text(clip.playbackDuration.formattedDuration)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(9)
                                .background(
                                    viewModel.selectedClipID == clip.id ? Color.blue.opacity(0.22) : Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
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
                    Toggle(
                        "Без звука",
                        isOn: Binding(
                            get: { clip.isMuted },
                            set: { _ in viewModel.toggleMuteSelected() }
                        )
                    )
                }

                Section("Обрезка") {
                    Slider(
                        value: Binding(
                            get: { clip.trimStart },
                            set: { viewModel.setTrim(start: $0) }
                        ),
                        in: 0...max(0.05, clip.trimEnd - 0.05)
                    )
                    Slider(
                        value: Binding(
                            get: { clip.trimEnd },
                            set: { viewModel.setTrim(end: $0) }
                        ),
                        in: min(clip.sourceDuration, clip.trimStart + 0.05)...clip.sourceDuration
                    )
                }

                Section {
                    Button("Открыть Speed Ramp") { viewModel.openSpeedRamp() }
                    Button("Эффекты, переход и keyframes") { viewModel.openClipTools() }
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
