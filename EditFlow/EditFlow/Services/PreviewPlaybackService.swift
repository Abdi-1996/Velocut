import AVFoundation
import Foundation

@MainActor
final class PreviewPlaybackService {
    private let timescale: CMTimeScale = 600

    func makePlayerItem(for clip: MediaClip, url: URL, frameRate: Int) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
            return AVPlayerItem(asset: asset)
        }

        let composition = AVMutableComposition()
        guard let destinationVideo = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return AVPlayerItem(asset: asset)
        }

        let preferredTransform = try await sourceVideo.load(.preferredTransform)
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let renderSize = CGSize(
            width: max(1, abs(orientedRect.width)),
            height: max(1, abs(orientedRect.height))
        )
        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY)
        )

        let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first
        let destinationAudio: AVMutableCompositionTrack?
        if clip.isMuted || sourceAudio == nil {
            destinationAudio = nil
        } else {
            destinationAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        let trimStart = CMTime(seconds: clip.trimStart, preferredTimescale: timescale)
        let trimDuration = CMTime(seconds: clip.trimmedDuration, preferredTimescale: timescale)
        var cursor = CMTime.zero
        let points = clip.speedPoints.sorted { $0.position < $1.position }

        if points.count < 2 {
            let range = CMTimeRange(start: trimStart, duration: trimDuration)
            try destinationVideo.insertTimeRange(range, of: sourceVideo, at: .zero)
            if let sourceAudio, let destinationAudio {
                try? destinationAudio.insertTimeRange(range, of: sourceAudio, at: .zero)
            }
        } else {
            for index in 0..<(points.count - 1) {
                let left = points[index]
                let right = points[index + 1]
                let fraction = max(0, right.position - left.position)
                guard fraction > 0 else { continue }

                let segmentStart = trimStart + CMTimeMultiplyByFloat64(trimDuration, multiplier: left.position)
                let segmentDuration = CMTimeMultiplyByFloat64(trimDuration, multiplier: fraction)
                let sourceRange = CMTimeRange(start: segmentStart, duration: segmentDuration)
                let rate = max(0.05, (left.rate + right.rate) / 2)
                let targetDuration = CMTimeMultiplyByFloat64(segmentDuration, multiplier: 1 / rate)
                let insertedRange = CMTimeRange(start: cursor, duration: segmentDuration)

                try destinationVideo.insertTimeRange(sourceRange, of: sourceVideo, at: cursor)
                destinationVideo.scaleTimeRange(insertedRange, toDuration: targetDuration)

                if let sourceAudio, let destinationAudio {
                    do {
                        try destinationAudio.insertTimeRange(sourceRange, of: sourceAudio, at: cursor)
                        destinationAudio.scaleTimeRange(insertedRange, toDuration: targetDuration)
                    } catch {
                        // A few phone videos have an audio stream that is shorter than video.
                        // Keep the visual preview working even when that happens.
                    }
                }

                cursor = cursor + targetDuration
            }
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: destinationVideo)
        layerInstruction.setTransform(normalizedTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return item
    }
}
