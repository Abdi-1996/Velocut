import AVFoundation
import Foundation
import Photos
import PhotosUI
import SwiftUI

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var project: EditProject
    @Published var selectedClipID: UUID?
    @Published var playhead: Double = 0
    @Published var player = AVPlayer()
    @Published private(set) var previewClipID: UUID?
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var errorMessage: String?
    @Published var exportedURL: URL?
    @Published var showingSpeedRamp = false
    @Published var showingClipTools = false
    @Published var showingExport = false

    private let store: ProjectStore
    private let importer = MediaImportService()
    private let exporter = VideoExportService()
    private let previewPlayback = PreviewPlaybackService()

    private var loadedPreviewClipID: UUID?
    private var loadedPreviewSpeedPoints: [SpeedPoint] = []
    private var previewBuildTask: Task<Void, Never>?
    private var previewBuildGeneration = 0

    init(project: EditProject, store: ProjectStore) {
        self.project = project
        self.store = store
        selectedClipID = project.clips.first?.id
        playhead = min(project.clips.first?.timelineStart ?? 0, project.duration)
        refreshPlayer()
    }

    deinit {
        previewBuildTask?.cancel()
    }

    var selectedClip: MediaClip? {
        guard let selectedClipID else { return nil }
        return project.clips.first { $0.id == selectedClipID }
    }

    var previewClip: MediaClip? {
        guard let previewClipID else { return nil }
        return project.clips.first { $0.id == previewClipID }
    }

    var hasInlineEditor: Bool {
        showingSpeedRamp || showingClipTools
    }

    func mediaURL(for clip: MediaClip) -> URL {
        store.projectDirectory(project.id).appendingPathComponent(clip.relativePath)
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        let mediaDirectory = store.mediaDirectory(project.id)
        Task {
            do {
                let items = try await importer.importFiles(urls, into: mediaDirectory)
                appendImportedMedia(items)
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }

    func importFromGallery(_ items: [PhotosPickerItem], visualLayer: Int = 0) async {
        guard !items.isEmpty else { return }
        isImporting = true
        errorMessage = nil
        var urls: [URL] = []

        do {
            for item in items {
                guard let media = try await item.loadTransferable(type: GalleryMediaTransfer.self) else {
                    throw MediaImportError.inaccessibleFile
                }
                urls.append(media.url)
            }
            let imported = try await importer.importFiles(urls, into: store.mediaDirectory(project.id))
            appendImportedMedia(imported, targetVisualLayer: visualLayer)
        } catch {
            errorMessage = "Не удалось импортировать из галереи: \(error.localizedDescription)"
        }

        for url in urls { try? FileManager.default.removeItem(at: url) }
        isImporting = false
    }

    func select(_ clip: MediaClip) {
        selectedClipID = clip.id
    }

    func openSpeedRamp() {
        guard let clip = selectedClip, clip.kind == .video else {
            errorMessage = "Speed Ramp доступен для видеоклипов."
            return
        }
        showingClipTools = false
        showingSpeedRamp = true
        let frame = 1 / Double(max(1, project.frameRate))
        let target = min(max(playhead, clip.timelineStart), max(clip.timelineStart, clip.timelineEnd - frame))
        scrubTimeline(to: target)
    }

    func openClipTools() {
        guard selectedClip != nil else { return }
        showingSpeedRamp = false
        showingClipTools = true
    }

    func closeInlineEditor() {
        showingSpeedRamp = false
        showingClipTools = false
    }

    func stepFrame(_ direction: Int) {
        let step = Double(direction) / Double(max(1, project.frameRate))
        scrubTimeline(to: playhead + step)
    }

    func scrubTimeline(to timelineTime: Double) {
        let clamped = min(max(0, timelineTime), max(0, project.duration))
        playhead = clamped

        let activeVisual = project.clips
            .filter {
                $0.kind != .audio &&
                clamped >= $0.timelineStart &&
                (clamped < $0.timelineEnd || (clamped == project.duration && clamped <= $0.timelineEnd))
            }
            .sorted {
                if $0.layer == $1.layer { return $0.timelineStart > $1.timelineStart }
                return $0.layer > $1.layer
            }
            .first

        guard let clip = activeVisual else {
            previewBuildTask?.cancel()
            previewClipID = nil
            loadedPreviewClipID = nil
            loadedPreviewSpeedPoints = []
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        previewClipID = clip.id

        guard clip.kind == .video else {
            previewBuildTask?.cancel()
            loadedPreviewClipID = nil
            loadedPreviewSpeedPoints = []
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        let localTimeline = min(max(0, clamped - clip.timelineStart), clip.playbackDuration)
        ensurePreviewItem(for: clip, localTimeline: localTimeline)
    }

    func splitSelected(at timelineTime: Double) {
        guard let id = selectedClipID,
              let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        let original = project.clips[index]
        let localTime = timelineTime - original.timelineStart
        guard localTime > 0.08, localTime < original.playbackDuration - 0.08 else {
            errorMessage = "Переместите курсор внутрь выбранного клипа."
            return
        }
        let sourceFraction = localTime / original.playbackDuration
        let sourceSplit = original.trimStart + original.trimmedDuration * sourceFraction
        var left = original
        left.trimEnd = sourceSplit
        var right = original
        right.id = UUID()
        right.trimStart = sourceSplit
        right.timelineStart = timelineTime
        project.clips[index] = left
        project.clips.insert(right, at: index + 1)
        selectedClipID = right.id
        invalidatePreview()
        commit()
        scrubTimeline(to: playhead)
    }

    func duplicateSelected() {
        guard var clip = selectedClip else { return }
        clip.id = UUID()
        clip.timelineStart = clip.timelineEnd
        project.clips.append(clip)
        selectedClipID = clip.id
        commit()
    }

    func deleteSelected() {
        guard let selectedClipID else { return }
        project.clips.removeAll { $0.id == selectedClipID }
        self.selectedClipID = project.clips.first?.id
        compactPrimaryTrack()
        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
    }

    func toggleMuteSelected() {
        mutateSelected { $0.isMuted.toggle() }
        invalidatePreview()
        commit()
        scrubTimeline(to: playhead)
    }

    func setTrim(start: Double? = nil, end: Double? = nil) {
        mutateSelected { clip in
            if let start { clip.trimStart = min(max(0, start), clip.trimEnd - 0.05) }
            if let end { clip.trimEnd = max(clip.trimStart + 0.05, min(clip.sourceDuration, end)) }
        }
        compactPrimaryTrack()
        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
    }

    func previewNonRippleTrim(_ updatedClip: MediaClip) {
        guard updatedClip.id == selectedClipID,
              let index = project.clips.firstIndex(where: { $0.id == updatedClip.id }) else { return }
        project.clips[index] = updatedClip
    }

    func finishNonRippleTrim() {
        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
    }

    func applySpeedPreset(_ preset: SpeedPreset) {
        mutateSelected { $0.speedPoints = preset.points }
        compactPrimaryTrack()
        invalidatePreview()
        commit()
        keepPlayheadInsideSelectedClipAndRefresh()
    }

    func updateSpeedPoint(_ point: SpeedPoint) {
        mutateSelected { clip in
            guard let index = clip.speedPoints.firstIndex(where: { $0.id == point.id }) else { return }
            clip.speedPoints[index] = point
            clip.speedPoints.sort { $0.position < $1.position }
        }
        compactPrimaryTrack()
        invalidatePreview()
        commit()
        keepPlayheadInsideSelectedClipAndRefresh()
    }

    func updateEffects(_ effects: EffectSettings) {
        mutateSelected { $0.effects = effects }
        commit()
    }

    func resetEffects() {
        updateEffects(EffectSettings())
    }

    func updateTransition(style: TransitionStyle? = nil, duration: Double? = nil) {
        mutateSelected { clip in
            var transition = clip.resolvedTransition
            if let style { transition.style = style }
            if let duration { transition.duration = min(max(0.1, duration), 1.5) }
            clip.transition = transition
        }
        compactPrimaryTrack()
        commit()
    }

    func updateKeyframe(_ keyframe: ClipKeyframe) {
        mutateSelected { clip in
            var keyframes = clip.resolvedKeyframes
            guard let index = keyframes.firstIndex(where: { $0.id == keyframe.id }) else { return }
            keyframes[index] = keyframe
            keyframes.sort { $0.position < $1.position }
            clip.keyframes = keyframes
        }
        commit()
    }

    func resetKeyframes() {
        mutateSelected { $0.keyframes = ClipKeyframe.identity }
        commit()
    }

    func export(quality: ExportQuality, saveToPhotos: Bool) {
        isExporting = true
        errorMessage = nil
        Task {
            do {
                let output = try await exporter.export(
                    project: project,
                    rootDirectory: store.projectDirectory(project.id),
                    quality: quality
                )
                exportedURL = output
                if saveToPhotos { try await saveVideoToPhotos(output) }
                showingExport = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isExporting = false
        }
    }

    func refreshPlayer() {
        scrubTimeline(to: min(max(0, playhead), max(0, project.duration)))
    }

    private func ensurePreviewItem(for clip: MediaClip, localTimeline: Double) {
        if loadedPreviewClipID == clip.id,
           loadedPreviewSpeedPoints == clip.speedPoints,
           player.currentItem != nil {
            seekPreview(to: localTimeline)
            return
        }

        previewBuildGeneration += 1
        let generation = previewBuildGeneration
        previewBuildTask?.cancel()
        let url = mediaURL(for: clip)
        let snapshot = clip

        previewBuildTask = Task { [weak self] in
            guard let self else { return }
            do {
                let item = try await previewPlayback.makePlayerItem(for: snapshot, url: url)
                guard !Task.isCancelled, generation == previewBuildGeneration else { return }
                player.pause()
                player.replaceCurrentItem(with: item)
                loadedPreviewClipID = snapshot.id
                loadedPreviewSpeedPoints = snapshot.speedPoints

                let currentLocal: Double
                if previewClipID == snapshot.id {
                    currentLocal = min(max(0, playhead - snapshot.timelineStart), snapshot.playbackDuration)
                } else {
                    currentLocal = localTimeline
                }
                seekPreview(to: currentLocal)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Не удалось подготовить предпросмотр: \(error.localizedDescription)"
            }
        }
    }

    private func seekPreview(to localTimeline: Double) {
        let time = CMTime(seconds: max(0, localTimeline), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func invalidatePreview() {
        previewBuildTask?.cancel()
        previewBuildGeneration += 1
        loadedPreviewClipID = nil
        loadedPreviewSpeedPoints = []
    }

    private func keepPlayheadInsideSelectedClipAndRefresh() {
        guard let clip = selectedClip else {
            scrubTimeline(to: min(playhead, project.duration))
            return
        }
        let frame = 1 / Double(max(1, project.frameRate))
        let target = min(max(playhead, clip.timelineStart), max(clip.timelineStart, clip.timelineEnd - frame))
        scrubTimeline(to: target)
    }

    private func mutateSelected(_ change: (inout MediaClip) -> Void) {
        guard let id = selectedClipID,
              let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        change(&project.clips[index])
    }

    private func appendImportedMedia(_ items: [ImportedMedia], targetVisualLayer: Int? = nil) {
        let visualLayer = targetVisualLayer ?? 0
        var videoCursor = project.clips
            .filter { $0.layer == visualLayer && $0.kind != .audio }
            .map(\.timelineEnd)
            .max() ?? 0
        var audioCursor = project.clips
            .filter { $0.kind == .audio }
            .map(\.timelineEnd)
            .max() ?? 0

        for item in items {
            let start = item.kind == .audio ? audioCursor : videoCursor
            let layer = item.kind == .audio ? 2 : visualLayer
            let clip = MediaClip(
                fileName: item.fileName,
                relativePath: item.relativePath,
                kind: item.kind,
                sourceDuration: item.duration,
                timelineStart: start,
                trimEnd: item.duration,
                layer: layer
            )
            project.clips.append(clip)
            if item.kind == .audio {
                audioCursor += clip.playbackDuration
            } else {
                videoCursor += clip.playbackDuration
            }
            selectedClipID = clip.id
        }

        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
    }

    private func compactPrimaryTrack() {
        var cursor = 0.0
        let orderedIDs = project.clips
            .filter { $0.layer == 0 }
            .sorted { $0.timelineStart < $1.timelineStart }
            .map(\.id)
        var previous: MediaClip?

        for id in orderedIDs {
            guard let index = project.clips.firstIndex(where: { $0.id == id }) else { continue }
            if let previous, previous.resolvedTransition.style == .crossDissolve {
                cursor -= min(
                    previous.resolvedTransition.duration,
                    previous.playbackDuration * 0.45,
                    project.clips[index].playbackDuration * 0.45
                )
            }
            project.clips[index].timelineStart = cursor
            cursor += project.clips[index].playbackDuration
            previous = project.clips[index]
        }
    }

    private func commit() {
        store.update(project)
    }

    private func saveVideoToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw VideoExportError.failed("Нет разрешения на сохранение в Фото")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
