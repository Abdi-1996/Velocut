import AVFoundation
import UIKit

final class TimelineThumbnailService {
    static let shared = TimelineThumbnailService()

    private let cache = NSCache<NSString, NSArray>()
    private let workQueue = DispatchQueue(label: "kz.colorize.editflow.timeline-thumbnails", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "kz.colorize.editflow.timeline-thumbnails-state")
    private var latestRequest: [UUID: UUID] = [:]
    private var latestImages: [UUID: [UIImage]] = [:]

    private init() {
        cache.countLimit = 160
    }

    func thumbnails(
        for clip: MediaClip,
        url: URL,
        count: Int,
        pixelHeight: CGFloat
    ) async -> [UIImage] {
        guard clip.kind == .video, count > 0 else { return [] }

        let normalizedCount = min(16, max(1, count))
        let normalizedHeight = max(40, Int(pixelHeight.rounded()))
        let key = cacheKey(
            clip: clip,
            url: url,
            count: normalizedCount,
            pixelHeight: normalizedHeight
        ) as NSString
        let requestID = UUID()

        stateQueue.sync {
            latestRequest[clip.id] = requestID
        }

        if let cached = cache.object(forKey: key) as? [UIImage] {
            stateQueue.sync { latestImages[clip.id] = cached }
            return cached
        }

        return await withCheckedContinuation { continuation in
            workQueue.async { [self] in
                guard isLatest(requestID, for: clip.id) else {
                    continuation.resume(returning: lastImages(for: clip.id))
                    return
                }

                if let cached = cache.object(forKey: key) as? [UIImage] {
                    stateQueue.sync { latestImages[clip.id] = cached }
                    continuation.resume(returning: cached)
                    return
                }

                let asset = AVURLAsset(url: url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
                generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
                generator.maximumSize = CGSize(width: normalizedHeight * 2, height: normalizedHeight * 2)

                var images: [UIImage] = []
                images.reserveCapacity(normalizedCount)

                for index in 0..<normalizedCount {
                    guard isLatest(requestID, for: clip.id) else {
                        continuation.resume(returning: lastImages(for: clip.id))
                        return
                    }

                    autoreleasepool {
                        let fraction: Double
                        if normalizedCount == 1 {
                            fraction = 0.5
                        } else {
                            fraction = Double(index) / Double(normalizedCount - 1)
                        }
                        let sourceTime = clip.trimStart + clip.trimmedDuration * fraction
                        let time = CMTime(seconds: sourceTime, preferredTimescale: 600)
                        if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                            images.append(UIImage(cgImage: cgImage))
                        }
                    }
                }

                guard isLatest(requestID, for: clip.id) else {
                    continuation.resume(returning: lastImages(for: clip.id))
                    return
                }

                if !images.isEmpty {
                    cache.setObject(images as NSArray, forKey: key)
                    stateQueue.sync { latestImages[clip.id] = images }
                }
                continuation.resume(returning: images.isEmpty ? lastImages(for: clip.id) : images)
            }
        }
    }

    private func isLatest(_ requestID: UUID, for clipID: UUID) -> Bool {
        stateQueue.sync { latestRequest[clipID] == requestID }
    }

    private func lastImages(for clipID: UUID) -> [UIImage] {
        stateQueue.sync { latestImages[clipID] ?? [] }
    }

    private func cacheKey(
        clip: MediaClip,
        url: URL,
        count: Int,
        pixelHeight: Int
    ) -> String {
        [
            url.path,
            clip.id.uuidString,
            String(format: "%.4f", clip.trimStart),
            String(format: "%.4f", clip.trimEnd),
            String(count),
            String(pixelHeight)
        ].joined(separator: "|")
    }
}
