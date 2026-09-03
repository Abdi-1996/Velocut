import AVFoundation
import UIKit

final class TrimPreviewFrameService {
    static let shared = TrimPreviewFrameService()

    private let workQueue = DispatchQueue(
        label: "kz.colorize.editflow.trim-preview-frame",
        qos: .userInteractive
    )
    private let stateQueue = DispatchQueue(
        label: "kz.colorize.editflow.trim-preview-frame-state"
    )
    private var latestRequestID: UUID?

    private init() {}

    func frame(
        url: URL,
        sourceTime: Double,
        maximumSize: CGSize = CGSize(width: 1920, height: 1920)
    ) async -> UIImage? {
        let requestID = UUID()
        stateQueue.sync {
            latestRequestID = requestID
        }

        return await withCheckedContinuation { continuation in
            workQueue.async { [self] in
                guard isLatest(requestID) else {
                    continuation.resume(returning: nil)
                    return
                }

                autoreleasepool {
                    let asset = AVURLAsset(url: url)
                    let generator = AVAssetImageGenerator(asset: asset)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = maximumSize
                    generator.requestedTimeToleranceBefore = CMTime(
                        seconds: 0.015,
                        preferredTimescale: 600
                    )
                    generator.requestedTimeToleranceAfter = CMTime(
                        seconds: 0.015,
                        preferredTimescale: 600
                    )

                    let time = CMTime(
                        seconds: max(0, sourceTime),
                        preferredTimescale: 600
                    )
                    let image = try? generator.copyCGImage(at: time, actualTime: nil)

                    guard isLatest(requestID), let image else {
                        continuation.resume(returning: nil)
                        return
                    }

                    continuation.resume(returning: UIImage(cgImage: image))
                }
            }
        }
    }

    func cancelPendingRequest() {
        stateQueue.sync {
            latestRequestID = nil
        }
    }

    private func isLatest(_ requestID: UUID) -> Bool {
        stateQueue.sync { latestRequestID == requestID }
    }
}
