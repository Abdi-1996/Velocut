import AVFoundation
import Foundation
import Photos
import SwiftUI

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var project: EditProject
    @Published var selectedClipID: UUID?
    @Published var playhead: Double = 0
    @Published var player = AVPlayer()
    @Published var isImporting = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var errorMessage: String?
    @Published var exportedURL: URL?
    @Published var showingSpeedRamp = false
    @Published var showingExport = false

    private let store: ProjectStore
    private let importer = MediaImportService()
    private let exporter = VideoExportService()

    init(project: EditProject, store: ProjectStore) {
        self.project = project
        self.store = store
        selectedClipID = project.clips.first?.id
        refreshPlayer()
    }

    var selectedClip: MediaClip? {
        guard let selectedClipID else { return nil }
        return project.clips.first { $0.id == selectedClipID }
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        let mediaDirectory = store.mediaDirectory(project.id)
        Task {
            do {
                let items = try await importer.importFiles(urls, into: mediaDirectory)
                var videoCursor = project.clips.filter { $0.layer == 0 && $0.kind != .audio }.map(\.timelineEnd).max() ?? 0
                var audioCursor = project.clips.filter { $0.kind == .audio }.map(\.timelineEnd).max() ?? 0
                for item in items {
                    let start = item.kind == .audio ? audioCursor : videoCursor
                    let layer = item.kind == .audio ? 2 : 0
                    let clip = MediaClip(fileName: item.fileName, relativePath: item.relativePath, kind: item.kind, sourceDuration: item.duration, timelineStart: start, trimEnd: item.duration, layer: layer)
                    project.clips.append(clip)
                    if item.kind == .audio { audioCursor += clip.playbackDuration } else { videoCursor += clip.playbackDuration }
                    selectedClipID = clip.id
                }
                commit()
                refreshPlayer()
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }

    func select(_ clip: MediaClip) {
        selectedClipID = clip.id
        playhead = clip.timelineStart
        refreshPlayer()
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
        commit()
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
        commit()
        refreshPlayer()
    }

    func toggleMuteSelected() {
        mutateSelected { $0.isMuted.toggle() }
    }

    func setTrim(start: Double? = nil, end: Double? = nil) {
        mutateSelected { clip in
            if let start { clip.trimStart = min(max(0, start), clip.trimEnd - 0.05) }
            if let end { clip.trimEnd = max(clip.trimStart + 0.05, min(clip.sourceDuration, end)) }
        }
        compactPrimaryTrack()
        commit()
    }

    func applySpeedPreset(_ preset: SpeedPreset) {
        mutateSelected { $0.speedPoints = preset.points }
        compactPrimaryTrack()
        commit()
    }

    func updateSpeedPoint(_ point: SpeedPoint) {
        mutateSelected { clip in
            guard let index = clip.speedPoints.firstIndex(where: { $0.id == point.id }) else { return }
            clip.speedPoints[index] = point
            clip.speedPoints.sort { $0.position < $1.position }
        }
        compactPrimaryTrack()
        commit()
    }

    func export(quality: ExportQuality, saveToPhotos: Bool) {
        isExporting = true
        errorMessage = nil
        Task {
            do {
                let output = try await exporter.export(project: project, rootDirectory: store.projectDirectory(project.id), quality: quality)
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
        guard let clip = selectedClip, clip.kind == .video else {
            player.replaceCurrentItem(with: nil)
            return
        }
        let url = store.projectDirectory(project.id).appendingPathComponent(clip.relativePath)
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.seek(to: CMTime(seconds: clip.trimStart, preferredTimescale: 600))
    }

    private func mutateSelected(_ change: (inout MediaClip) -> Void) {
        guard let id = selectedClipID,
              let index = project.clips.firstIndex(where: { $0.id == id }) else { return }
        change(&project.clips[index])
    }

    private func compactPrimaryTrack() {
        var cursor = 0.0
        let orderedIDs = project.clips.filter { $0.layer == 0 }.sorted { $0.timelineStart < $1.timelineStart }.map(\.id)
        for id in orderedIDs {
            guard let index = project.clips.firstIndex(where: { $0.id == id }) else { continue }
            project.clips[index].timelineStart = cursor
            cursor += project.clips[index].playbackDuration
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

