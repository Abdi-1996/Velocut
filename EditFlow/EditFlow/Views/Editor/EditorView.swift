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
                await viewModel.importFromGallery(items)
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
            Menu {
                Button {
                    showingGallery = true
                } label: {
                    Label("Фото и видео из галереи", systemImage: "photo.on.rectangle.angled")
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("Файл или аудио", systemImage: "folder")
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Добавить медиа")

            Button {
                viewModel.showingExport = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Экспорт")
            .disabled(viewModel.project.clips.allSatisfy { $0.kind != .video })
        }
    }

    private var preview: some View {
        Group {
            if let clip = viewModel.selectedClip, clip.kind == .image,
               let image = UIImage(contentsOfFile: viewModel.mediaURL(for: clip).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else if viewModel.player.currentItem == nil {
                EmptyPreview()
            } else {
                PlayerContainer(player: viewModel.player)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            preview.frame(minHeight: 240, idealHeight: 300)
            TimelineView(viewModel: viewModel)
            ClipActionBar(viewModel: viewModel, importAction: { showingGallery = true })
        }
    }

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            MediaSidebar(viewModel: viewModel, importAction: { showingGallery = true })
                .frame(width: 220)
            VStack(spacing: 0) {
                preview
                TimelineView(viewModel: viewModel)
                    .frame(height: 300)
            }
            ClipInspector(viewModel: viewModel)
                .frame(width: 260)
        }
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
