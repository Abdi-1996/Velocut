import AVFoundation
import Foundation

enum ExportQuality: String, CaseIterable, Identifiable {
    case medium = "Среднее"
    case high = "Высокое"
    case maximum = "Максимальное"

    var id: String { rawValue }

    var preset: String {
        switch self {
        case .medium: AVAssetExportPreset1280x720
        case .high: AVAssetExportPreset1920x1080
        case .maximum: AVAssetExportPresetHighestQuality
        }
    }
}

enum VideoExportError: LocalizedError {
    case noVideo
    case cannotCreateTrack
    case cannotCreateSession
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideo: "Добавьте хотя бы один видеоклип перед экспортом."
        case .cannotCreateTrack: "Не удалось создать видеодорожку."
        case .cannotCreateSession: "Эти настройки экспорта не поддерживаются устройством."
        case .failed(let message): "Экспорт остановлен: \(message)"
        case .cancelled: "Экспорт отменён."
        }
    }
}

actor VideoExportService {
    func export(project: EditProject, rootDirectory: URL, quality: ExportQuality) async throws -> URL {
        let videoClips = project.clips.filter { $0.kind == .video }.sorted {
            if $0.layer == $1.layer { return $0.timelineStart < $1.timelineStart }
            return $0.layer < $1.layer
        }
        guard !videoClips.isEmpty else { throw VideoExportError.noVideo }

        let composition = AVMutableComposition()
        let layerNumbers = Set(videoClips.map(\.layer)).sorted()
        var compositionTracks: [Int: AVMutableCompositionTrack] = [:]
        for layer in layerNumbers {
            guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw VideoExportError.cannotCreateTrack
            }
            compositionTracks[layer] = track
        }

        var audioTrack: AVMutableCompositionTrack?
        var preferredTransform = CGAffineTransform.identity

        for clip in videoClips {
            let url = rootDirectory.appendingPathComponent(clip.relativePath)
            let asset = AVURLAsset(url: url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
                  let destination = compositionTracks[clip.layer] else { continue }
            preferredTransform = try await sourceVideo.load(.preferredTransform)
            try await insertRamp(clip: clip, sourceTrack: sourceVideo, into: destination)

            if !clip.isMuted, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                if audioTrack == nil {
                    audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                if let audioTrack {
                    try await insertRamp(clip: clip, sourceTrack: sourceAudio, into: audioTrack)
                }
            }
        }

        for clip in project.clips.filter({ $0.kind == .audio }).sorted(by: { $0.timelineStart < $1.timelineStart }) {
            let url = rootDirectory.appendingPathComponent(clip.relativePath)
            let asset = AVURLAsset(url: url)
            guard let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            if audioTrack == nil {
                audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            }
            if let audioTrack {
                try await insertRamp(clip: clip, sourceTrack: sourceAudio, into: audioTrack)
            }
        }

        compositionTracks.values.forEach { $0.preferredTransform = preferredTransform }
        let outputDirectory = rootDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let output = outputDirectory.appendingPathComponent("EditFlow-\(UUID().uuidString).mov")

        guard let session = AVAssetExportSession(asset: composition, presetName: quality.preset) else {
            throw VideoExportError.cannotCreateSession
        }
        session.outputURL = output
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = true
        try await run(session)
        return output
    }

    private func insertRamp(
        clip: MediaClip,
        sourceTrack: AVAssetTrack,
        into destination: AVMutableCompositionTrack
    ) async throws {
        let timescale: CMTimeScale = 600
        let sourceStart = CMTime(seconds: clip.trimStart, preferredTimescale: timescale)
        let sourceDuration = CMTime(seconds: clip.trimmedDuration, preferredTimescale: timescale)
        var destinationCursor = CMTime(seconds: clip.timelineStart, preferredTimescale: timescale)
        let points = clip.speedPoints.sorted { $0.position < $1.position }

        guard points.count > 1 else {
            try destination.insertTimeRange(CMTimeRange(start: sourceStart, duration: sourceDuration), of: sourceTrack, at: destinationCursor)
            return
        }

        for index in 0..<(points.count - 1) {
            let left = points[index]
            let right = points[index + 1]
            let fraction = max(0, right.position - left.position)
            guard fraction > 0 else { continue }
            let segmentStart = sourceStart + CMTimeMultiplyByFloat64(sourceDuration, multiplier: left.position)
            let segmentDuration = CMTimeMultiplyByFloat64(sourceDuration, multiplier: fraction)
            let rate = max(0.05, (left.rate + right.rate) / 2)
            let targetDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1 / rate)
            let insertedRange = CMTimeRange(start: destinationCursor, duration: segmentDuration)
            try destination.insertTimeRange(CMTimeRange(start: segmentStart, duration: segmentDuration), of: sourceTrack, at: destinationCursor)
            destination.scaleTimeRange(insertedRange, toDuration: targetDuration)
            destinationCursor = destinationCursor + targetDuration
        }
    }

    private func run(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .cancelled:
                    continuation.resume(throwing: VideoExportError.cancelled)
                case .failed:
                    continuation.resume(throwing: VideoExportError.failed(session.error?.localizedDescription ?? "Неизвестная ошибка"))
                default:
                    continuation.resume(throwing: VideoExportError.failed("Экспорт завершился в неожиданном состоянии"))
                }
            }
        }
    }
}
