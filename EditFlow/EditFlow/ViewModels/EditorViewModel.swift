import AVFoundation
import Foundation
import Photos
import PhotosUI
import SwiftUI

@MainActor
final class EditorViewModel: ObservableObject {
    static let audioLayerBase = 100

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
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var playbackWasActive = false
    private var resumePlaybackAfterPreviewBuild = false

    init(project: EditProject, store: ProjectStore) {
        self.store = store

        var normalizedProject = project
        var migratedLegacyAudio = false
        for index in normalizedProject.clips.indices {
            if normalizedProject.clips[index].kind == .audio,
               normalizedProject.clips[index].layer < Self.audioLayerBase {
                normalizedProject.clips[index].layer = Self.audioLayerBase
                migratedLegacyAudio = true
            }
        }

        self.project = normalizedProject
        selectedClipID = normalizedProject.clips.first?.id
        playhead = min(normalizedProject.clips.first?.timelineStart ?? 0, normalizedProject.duration)

        installPlaybackObservers()
        if migratedLegacyAudio {
            store.update(normalizedProject)
        }
        refreshPlayer()
    }

    deinit {
        previewBuildTask?.cancel()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
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
        resumePlaybackAfterPreviewBuild = false

        let activeVisual = activeVisualClip(at: clamped)

        guard let clip = activeVisual else {
            previewBuildTask?.cancel()
            previewClipID = nil
            loadedPreviewClipID = nil
            loadedPreviewSpeedPoints = []
            playbackWasActive = false
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        previewClipID = clip.id

        guard clip.kind == .video else {
            previewBuildTask?.cancel()
            loadedPreviewClipID = nil
            loadedPreviewSpeedPoints = []
            playbackWasActive = false
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        let localTimeline = min(max(0, clamped - clip.timelineStart), clip.playbackDuration)
        ensurePreviewItem(for: clip, localTimeline: localTimeline)
    }

    func moveClip(
        id: UUID,
        to timelineStart: Double,
        layer requestedLayer: Int,
        snappingEnabled: Bool
    ) {
        guard let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        let originalLayer = project.clips[index].layer
        let kind = project.clips[index].kind
        let targetLayer = normalizedLayer(requestedLayer, for: kind)
        let snappedStart = snappedMoveStart(
            for: project.clips[index],
            proposedStart: timelineStart,
            snappingEnabled: snappingEnabled
        )

        project.clips[index].timelineStart = snappedStart
        project.clips[index].layer = targetLayer
        selectedClipID = id

        if originalLayer == 0 || targetLayer == 0 {
            compactPrimaryTrack()
        }

        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
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

    private func installPlaybackObservers() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.syncPlayheadFromPlayer(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handlePreviewItemEnded(notification)
            }
        }
    }

    private func syncPlayheadFromPlayer(_ time: CMTime) {
        guard let clip = previewClip,
              loadedPreviewClipID == clip.id,
              time.seconds.isFinite else { return }

        if player.rate > 0 {
            playbackWasActive = true
        }

        let local = min(max(0, time.seconds), clip.playbackDuration)
        let projectTime = min(max(0, clip.timelineStart + local), max(project.duration, clip.timelineEnd))
        if abs(projectTime - playhead) > 0.0005 {
            playhead = projectTime
        }
    }

    private func handlePreviewItemEnded(_ notification: Notification) {
        guard playbackWasActive,
              let endedItem = notification.object as? AVPlayerItem,
              endedItem === player.currentItem,
              let clip = previewClip else { return }

        playbackWasActive = false
        let frame = 1 / Double(max(1, project.frameRate))
        let nextTime = clip.timelineEnd + frame * 0.5
        let candidates = project.clips
            .filter { $0.kind != .audio && $0.timelineEnd > nextTime }
            .sorted { lhs, rhs in
                if lhs.timelineStart == rhs.timelineStart { return lhs.layer > rhs.layer }
                return lhs.timelineStart < rhs.timelineStart
            }

        guard let next = candidates.first else {
            playhead = min(project.duration, clip.timelineEnd)
            return
        }

        let target = max(next.timelineStart, min(nextTime, next.timelineEnd - frame))
        playhead = target
        previewClipID = next.id

        guard next.kind == .video else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            return
        }

        resumePlaybackAfterPreviewBuild = true
        let localTimeline = max(0, target - next.timelineStart)
        ensurePreviewItem(for: next, localTimeline: localTimeline)
    }

    private func activeVisualClip(at time: Double) -> MediaClip? {
        project.clips
            .filter {
                $0.kind != .audio &&
                time >= $0.timelineStart &&
                (time < $0.timelineEnd || (time == project.duration && time <= $0.timelineEnd))
            }
            .sorted {
                if $0.layer == $1.layer { return $0.timelineStart > $1.timelineStart }
                return $0.layer > $1.layer
            }
            .first
    }

    private func ensurePreviewItem(for clip: MediaClip, localTimeline: Double) {
        if loadedPreviewClipID == clip.id,
           loadedPreviewSpeedPoints == clip.speedPoints,
           player.currentItem != nil {
            seekPreview(to: localTimeline, resumePlayback: resumePlaybackAfterPreviewBuild)
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
                let item = try await previewPlayback.makePlayerItem(
                    for: snapshot,
                    url: url,
                    frameRate: project.frameRate
                )
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
                seekPreview(to: currentLocal, resumePlayback: resumePlaybackAfterPreviewBuild)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Не удалось подготовить предпросмотр: \(error.localizedDescription)"
            }
        }
    }

    private func seekPreview(to localTimeline: Double, resumePlayback: Bool = false) {
        let time = CMTime(seconds: max(0, localTimeline), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            Task { @MainActor [weak self] in
                guard let self, resumePlayback, self.resumePlaybackAfterPreviewBuild else { return }
                self.resumePlaybackAfterPreviewBuild = false
                self.playbackWasActive = true
                self.player.play()
            }
        }
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

    private func normalizedLayer(_ layer: Int, for kind: MediaKind) -> Int {
        if kind == .audio {
            return max(Self.audioLayerBase, layer)
        }
        return min(max(0, layer), Self.audioLayerBase - 1)
    }

    private func snappedMoveStart(
        for clip: MediaClip,
        proposedStart: Double,
        snappingEnabled: Bool
    ) -> Double {
        let fps = max(1, project.frameRate)
        let frame = 1 / Double(fps)
        var start = max(0, proposedStart)
        start = (start / frame).rounded() * frame

        guard snappingEnabled else { return start }

        let duration = clip.playbackDuration
        var options: [(distance: Double, start: Double)] = []
        let targets = project.clips
            .filter { $0.id != clip.id }
            .flatMap { [$0.timelineStart, $0.timelineEnd] } + [playhead]

        for target in targets {
            options.append((abs(target - start), target))
            options.append((abs(target - (start + duration)), target - duration))
        }

        if let best = options.min(by: { $0.distance < $1.distance }), best.distance <= 0.10 {
            start = max(0, best.start)
        }
        return (start / frame).rounded() * frame
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
            .filter { $0.kind == .audio && $0.layer == Self.audioLayerBase }
            .map(\.timelineEnd)
            .max() ?? 0

        for item in items {
            let start = item.kind == .audio ? audioCursor : videoCursor
            let layer = item.kind == .audio ? Self.audioLayerBase : visualLayer
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
            .filter { $0.layer == 0 && $0.kind != .audio }
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
