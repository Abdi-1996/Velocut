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
        case .noVideo: "Добавьте хотя бы один видеоклип или фотографию перед экспортом."
        case .cannotCreateTrack: "Не удалось создать видеодорожку."
        case .cannotCreateSession: "Эти настройки экспорта не поддерживаются устройством."
        case .failed(let message): "Экспорт остановлен: \(message)"
        case .cancelled: "Экспорт отменён."
        }
    }
}

actor VideoExportService {
    private let mediaRenderer = MediaRenderService()
    private let timescale: CMTimeScale = 600

    private struct Placement {
        let clip: MediaClip
        let start: Double
        let slot: Int
        let preparedURL: URL
        let sourceStartsAtZero: Bool
    }

    func export(project: EditProject, rootDirectory: URL, quality: ExportQuality) async throws -> URL {
        let visualClips = project.clips.filter { $0.kind != .audio }
        guard !visualClips.isEmpty else { throw VideoExportError.noVideo }
        let cacheDirectory = rootDirectory.appendingPathComponent("RenderCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let placements = try await preparePlacements(visualClips: visualClips, project: project, rootDirectory: rootDirectory, cacheDirectory: cacheDirectory)
        let composition = AVMutableComposition()
        var videoTracks: [Int: AVMutableCompositionTrack] = [:]
        var audioTracks: [Int: AVMutableCompositionTrack] = [:]
        var layerInstructions: [Int: AVMutableVideoCompositionLayerInstruction] = [:]

        for placement in placements {
            if videoTracks[placement.slot] == nil {
                guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw VideoExportError.cannotCreateTrack
                }
                videoTracks[placement.slot] = track
                layerInstructions[placement.slot] = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            }
            let asset = AVURLAsset(url: placement.preparedURL)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
                  let destination = videoTracks[placement.slot],
                  let layerInstruction = layerInstructions[placement.slot] else { continue }
            let sourceStart = placement.sourceStartsAtZero ? 0 : placement.clip.trimStart
            try await insertRamp(clip: placement.clip, sourceTrack: sourceVideo, into: destination, destinationStart: placement.start, sourceStart: sourceStart)
            try await applyTransforms(clip: placement.clip, sourceTrack: sourceVideo, instruction: layerInstruction, start: placement.start, renderSize: project.aspectRatio.size)

            if !placement.clip.isMuted, let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                if audioTracks[placement.slot] == nil {
                    audioTracks[placement.slot] = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                if let destinationAudio = audioTracks[placement.slot] {
                    try await insertRamp(clip: placement.clip, sourceTrack: sourceAudio, into: destinationAudio, destinationStart: placement.start, sourceStart: sourceStart)
                }
            }
        }

        applyTransitions(placements: placements, instructions: layerInstructions)
        try await insertStandaloneAudio(project: project, rootDirectory: rootDirectory, composition: composition)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = project.aspectRatio.size
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(project.frameRate))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        instruction.layerInstructions = layerInstructions.keys.sorted(by: >).compactMap { layerInstructions[$0] }
        videoComposition.instructions = [instruction]

        let outputDirectory = rootDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let output = outputDirectory.appendingPathComponent("EditFlow-\(UUID().uuidString).mov")
        guard let session = AVAssetExportSession(asset: composition, presetName: quality.preset) else { throw VideoExportError.cannotCreateSession }
        session.outputURL = output
        session.outputFileType = .mov
        session.shouldOptimizeForNetworkUse = true
        session.videoComposition = videoComposition
        try await run(session)
        return output
    }

    private func preparePlacements(visualClips: [MediaClip], project: EditProject, rootDirectory: URL, cacheDirectory: URL) async throws -> [Placement] {
        let primary = visualClips.filter { $0.layer == 0 }.sorted { $0.timelineStart < $1.timelineStart }
        var starts: [UUID: Double] = [:]
        var cursor = 0.0
        var previous: MediaClip?
        for clip in primary {
            if let previous, previous.resolvedTransition.style == .crossDissolve { cursor -= safeTransitionDuration(previous, next: clip) }
            starts[clip.id] = max(0, cursor)
            cursor = max(0, cursor) + clip.playbackDuration
            previous = clip
        }
        var result: [Placement] = []
        for clip in visualClips.sorted(by: { $0.timelineStart < $1.timelineStart }) {
            let url = try await mediaRenderer.prepareAsset(for: clip, projectDirectory: rootDirectory, renderSize: project.aspectRatio.size, frameRate: project.frameRate, cacheDirectory: cacheDirectory)
            let index = primary.firstIndex(where: { $0.id == clip.id }) ?? 0
            result.append(Placement(clip: clip, start: starts[clip.id] ?? clip.timelineStart, slot: clip.layer == 0 ? index % 2 : clip.layer + 2, preparedURL: url, sourceStartsAtZero: clip.kind == .image))
        }
        return result
    }

    private func insertStandaloneAudio(project: EditProject, rootDirectory: URL, composition: AVMutableComposition) async throws {
        let clips = project.clips.filter { $0.kind == .audio }.sorted { $0.timelineStart < $1.timelineStart }
        guard !clips.isEmpty, let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
        for clip in clips {
            let asset = AVURLAsset(url: rootDirectory.appendingPathComponent(clip.relativePath))
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            try await insertRamp(clip: clip, sourceTrack: source, into: destination, destinationStart: clip.timelineStart, sourceStart: clip.trimStart)
        }
    }

    private func insertRamp(clip: MediaClip, sourceTrack: AVAssetTrack, into destination: AVMutableCompositionTrack, destinationStart: Double, sourceStart: Double) async throws {
        let start = CMTime(seconds: sourceStart, preferredTimescale: timescale)
        let sourceDuration = CMTime(seconds: clip.trimmedDuration, preferredTimescale: timescale)
        var cursor = CMTime(seconds: destinationStart, preferredTimescale: timescale)
        let points = clip.speedPoints.sorted { $0.position < $1.position }
        guard points.count > 1 else {
            try destination.insertTimeRange(CMTimeRange(start: start, duration: sourceDuration), of: sourceTrack, at: cursor)
            return
        }
        for index in 0..<(points.count - 1) {
            let left = points[index], right = points[index + 1]
            let fraction = max(0, right.position - left.position)
            guard fraction > 0 else { continue }
            let segmentStart = start + CMTimeMultiplyByFloat64(sourceDuration, multiplier: left.position)
            let segmentDuration = CMTimeMultiplyByFloat64(sourceDuration, multiplier: fraction)
            let rate = max(0.05, (left.rate + right.rate) / 2)
            let targetDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1 / rate)
            let insertedRange = CMTimeRange(start: cursor, duration: segmentDuration)
            try destination.insertTimeRange(CMTimeRange(start: segmentStart, duration: segmentDuration), of: sourceTrack, at: cursor)
            destination.scaleTimeRange(insertedRange, toDuration: targetDuration)
            cursor = cursor + targetDuration
        }
    }

    private func applyTransforms(clip: MediaClip, sourceTrack: AVAssetTrack, instruction: AVMutableVideoCompositionLayerInstruction, start: Double, renderSize: CGSize) async throws {
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let preferred = try await sourceTrack.load(.preferredTransform)
        let base = fitTransform(naturalSize: naturalSize, preferred: preferred, renderSize: renderSize)
        let frames = clip.resolvedKeyframes.sorted { $0.position < $1.position }
        guard frames.count > 1 else { instruction.setTransform(base, at: CMTime(seconds: start, preferredTimescale: timescale)); return }
        for index in 0..<(frames.count - 1) {
            let left = frames[index], right = frames[index + 1]
            instruction.setTransformRamp(fromStart: userTransform(left.transform, base: base, renderSize: renderSize), toEnd: userTransform(right.transform, base: base, renderSize: renderSize), timeRange: CMTimeRange(start: CMTime(seconds: start + clip.playbackDuration * left.position, preferredTimescale: timescale), duration: CMTime(seconds: clip.playbackDuration * max(0.001, right.position - left.position), preferredTimescale: timescale)))
        }
    }

    private func applyTransitions(placements: [Placement], instructions: [Int: AVMutableVideoCompositionLayerInstruction]) {
        let primary = placements.filter { $0.clip.layer == 0 }.sorted { $0.start < $1.start }
        for placement in primary {
            instructions[placement.slot]?.setOpacity(1, at: CMTime(seconds: placement.start, preferredTimescale: timescale))
            instructions[placement.slot]?.setOpacity(0, at: CMTime(seconds: placement.start + placement.clip.playbackDuration + 0.001, preferredTimescale: timescale))
        }
        guard primary.count > 1 else { return }
        for index in 0..<(primary.count - 1) {
            let current = primary[index], next = primary[index + 1]
            let transition = current.clip.resolvedTransition
            let duration = safeTransitionDuration(current.clip, next: next.clip)
            guard transition.style != .none, duration > 0 else { continue }
            switch transition.style {
            case .none: break
            case .crossDissolve:
                let range = CMTimeRange(start: CMTime(seconds: next.start, preferredTimescale: timescale), duration: CMTime(seconds: duration, preferredTimescale: timescale))
                instructions[current.slot]?.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: range)
                instructions[next.slot]?.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: range)
            case .fadeToBlack:
                instructions[current.slot]?.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: CMTimeRange(start: CMTime(seconds: current.start + current.clip.playbackDuration - duration, preferredTimescale: timescale), duration: CMTime(seconds: duration, preferredTimescale: timescale)))
                instructions[next.slot]?.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: CMTimeRange(start: CMTime(seconds: next.start, preferredTimescale: timescale), duration: CMTime(seconds: duration, preferredTimescale: timescale)))
            }
        }
    }

    private func safeTransitionDuration(_ clip: MediaClip, next: MediaClip) -> Double {
        min(max(0, clip.resolvedTransition.duration), clip.playbackDuration * 0.45, next.playbackDuration * 0.45)
    }

    private func fitTransform(naturalSize: CGSize, preferred: CGAffineTransform, renderSize: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let oriented = CGSize(width: abs(rect.width), height: abs(rect.height))
        let scale = min(renderSize.width / max(1, oriented.width), renderSize.height / max(1, oriented.height))
        let x = (renderSize.width - oriented.width * scale) / 2, y = (renderSize.height - oriented.height * scale) / 2
        return preferred.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY)).concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: x, y: y))
    }

    private func userTransform(_ value: ClipTransform, base: CGAffineTransform, renderSize: CGSize) -> CGAffineTransform {
        let center = CGPoint(x: renderSize.width / 2, y: renderSize.height / 2)
        var user = CGAffineTransform(translationX: value.positionX, y: value.positionY)
        user = user.translatedBy(x: center.x, y: center.y).rotated(by: value.rotation * .pi / 180).scaledBy(x: max(0.05, value.scale), y: max(0.05, value.scale)).translatedBy(x: -center.x, y: -center.y)
        return base.concatenating(user)
    }

    private func run(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed: continuation.resume(returning: ())
                case .cancelled: continuation.resume(throwing: VideoExportError.cancelled)
                case .failed: continuation.resume(throwing: VideoExportError.failed(session.error?.localizedDescription ?? "Неизвестная ошибка"))
                default: continuation.resume(throwing: VideoExportError.failed("Экспорт завершился в неожиданном состоянии"))
                }
            }
        }
    }
}

