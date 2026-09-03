from pathlib import Path

root = Path(__file__).resolve().parents[1]
vm_path = root / "EditFlow/EditFlow/ViewModels/EditorViewModel.swift"
timeline_path = root / "EditFlow/EditFlow/Views/Editor/TimelineView.swift"
thumb_path = root / "EditFlow/EditFlow/Services/TimelineThumbnailService.swift"

vm = vm_path.read_text()

state_old = """    private var playbackWasActive = false
    private var resumePlaybackAfterPreviewBuild = false
"""
state_new = """    private var playbackWasActive = false
    private var resumePlaybackAfterPreviewBuild = false
    private var trimSessionOrigin: MediaClip?
    private var lastTrimSnapGuide: Double?
"""
if state_old in vm:
    vm = vm.replace(state_old, state_new, 1)

trim_old = """    func previewNonRippleTrim(_ updatedClip: MediaClip) {
        guard updatedClip.id == selectedClipID,
              let index = project.clips.firstIndex(where: { $0.id == updatedClip.id }) else { return }
        project.clips[index] = updatedClip
    }

    func finishNonRippleTrim() {
        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
    }
"""
trim_new = """    func previewNonRippleTrim(_ updatedClip: MediaClip) {
        guard updatedClip.id == selectedClipID,
              let index = project.clips.firstIndex(where: { $0.id == updatedClip.id }) else { return }

        if trimSessionOrigin?.id != updatedClip.id {
            trimSessionOrigin = project.clips[index]
            lastTrimSnapGuide = nil
        }

        guard let origin = trimSessionOrigin else {
            project.clips[index] = updatedClip
            return
        }

        let leftChange = abs(updatedClip.trimStart - origin.trimStart)
        let rightChange = abs(updatedClip.trimEnd - origin.trimEnd)
        var resolved = updatedClip
        var snapGuide: Double?

        if leftChange > rightChange + 0.000_001 {
            let result = resolvedLeftTrim(proposed: updatedClip, origin: origin)
            resolved = result.clip
            snapGuide = result.guide
        } else if rightChange > 0.000_001 {
            let result = resolvedRightTrim(proposed: updatedClip, origin: origin)
            resolved = result.clip
            snapGuide = result.guide
        }

        if snapGuide != lastTrimSnapGuide {
            if snapGuide != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            lastTrimSnapGuide = snapGuide
        }

        project.clips[index] = resolved
    }

    func finishNonRippleTrim() {
        trimSessionOrigin = nil
        lastTrimSnapGuide = nil
        invalidatePreview()
        commit()
        scrubTimeline(to: min(playhead, project.duration))
    }
"""
if trim_old in vm:
    vm = vm.replace(trim_old, trim_new, 1)

helper_marker = """    private func mutateSelected(_ change: (inout MediaClip) -> Void) {
"""
helpers = """    private func resolvedLeftTrim(proposed: MediaClip, origin: MediaClip) -> (clip: MediaClip, guide: Double?) {
        let originalEnd = origin.timelineEnd
        let rawBoundary = proposed.timelineStart
        guard let snap = nearestTrimSnap(to: rawBoundary, for: origin) else {
            return (proposed, nil)
        }

        var shortest = origin
        shortest.trimStart = max(0, origin.trimEnd - 0.05)
        var longest = origin
        longest.trimStart = 0
        let targetDuration = originalEnd - snap
        let minimumDuration = shortest.playbackDuration
        let maximumDuration = longest.playbackDuration

        guard targetDuration >= minimumDuration - 0.000_5,
              targetDuration <= maximumDuration + 0.000_5 else {
            return (proposed, nil)
        }

        var resolved = proposed
        resolved.trimStart = trimStart(forPlaybackDuration: targetDuration, origin: origin)
        resolved.timelineStart = snap
        return (resolved, snap)
    }

    private func resolvedRightTrim(proposed: MediaClip, origin: MediaClip) -> (clip: MediaClip, guide: Double?) {
        let rawBoundary = proposed.timelineEnd
        guard let snap = nearestTrimSnap(to: rawBoundary, for: origin) else {
            return (proposed, nil)
        }

        var shortest = origin
        shortest.trimEnd = min(origin.sourceDuration, origin.trimStart + 0.05)
        var longest = origin
        longest.trimEnd = origin.sourceDuration
        let targetDuration = snap - origin.timelineStart
        let minimumDuration = shortest.playbackDuration
        let maximumDuration = longest.playbackDuration

        guard targetDuration >= minimumDuration - 0.000_5,
              targetDuration <= maximumDuration + 0.000_5 else {
            return (proposed, nil)
        }

        var resolved = proposed
        resolved.trimEnd = trimEnd(forPlaybackDuration: targetDuration, origin: origin)
        resolved.timelineStart = origin.timelineStart
        return (resolved, snap)
    }

    private func nearestTrimSnap(to boundary: Double, for clip: MediaClip) -> Double? {
        let compatible = project.clips.filter {
            guard $0.id != clip.id else { return false }
            if clip.kind == .audio { return $0.kind == .audio }
            return $0.kind != .audio
        }

        let sameLayerTargets = compatible
            .filter { $0.layer == clip.layer }
            .flatMap { [$0.timelineStart, $0.timelineEnd] }
        let otherTargets = compatible
            .filter { $0.layer != clip.layer }
            .flatMap { [$0.timelineStart, $0.timelineEnd] }
        let threshold = 0.12

        if let nearest = sameLayerTargets.min(by: { abs($0 - boundary) < abs($1 - boundary) }),
           abs(nearest - boundary) <= threshold {
            return nearest
        }
        if let nearest = otherTargets.min(by: { abs($0 - boundary) < abs($1 - boundary) }),
           abs(nearest - boundary) <= threshold {
            return nearest
        }
        return nil
    }

    private func trimStart(forPlaybackDuration target: Double, origin: MediaClip) -> Double {
        var low = 0.0
        var high = max(0, origin.trimEnd - 0.05)
        for _ in 0..<20 {
            let middle = (low + high) * 0.5
            var candidate = origin
            candidate.trimStart = middle
            if candidate.playbackDuration > target {
                low = middle
            } else {
                high = middle
            }
        }
        return min(max(0, (low + high) * 0.5), origin.trimEnd - 0.05)
    }

    private func trimEnd(forPlaybackDuration target: Double, origin: MediaClip) -> Double {
        var low = min(origin.sourceDuration, origin.trimStart + 0.05)
        var high = origin.sourceDuration
        for _ in 0..<20 {
            let middle = (low + high) * 0.5
            var candidate = origin
            candidate.trimEnd = middle
            if candidate.playbackDuration < target {
                low = middle
            } else {
                high = middle
            }
        }
        return max(origin.trimStart + 0.05, min(origin.sourceDuration, (low + high) * 0.5))
    }

"""
if helpers not in vm and helper_marker in vm:
    vm = vm.replace(helper_marker, helpers + helper_marker, 1)

vm_path.write_text(vm)

timeline = timeline_path.read_text()
timeline = timeline.replace(
    """    private func trimGesture(edge: TrimEdge) -> some Gesture {
        DragGesture(minimumDistance: 0)
""",
    """    private func trimGesture(edge: TrimEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
""",
    1,
)
timeline = timeline.replace(
    ".contentShape(Rectangle().inset(by: -10))",
    ".contentShape(Rectangle().inset(by: -14))",
    2,
)
timeline_path.write_text(timeline)

thumb_path.write_text("""import AVFoundation
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
""")

print("Applied EditFlow 1.6.1 trim fixes")
