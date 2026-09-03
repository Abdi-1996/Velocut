from pathlib import Path


timeline_path = Path('EditFlow/EditFlow/Views/Editor/TimelineView.swift')
project_path = Path('EditFlow/project.yml')
changelog_path = Path('EditFlow/CHANGELOG.md')

timeline = timeline_path.read_text()
project = project_path.read_text()
changelog = changelog_path.read_text()

if 'MARKETING_VERSION: 1.6.8' in project and 'TimelineUnifiedTrimOverlay' in timeline:
    raise SystemExit(0)

old_handles = '''                if viewModel.selectedClipID == sourceClip.id,
                   movingClipID != sourceClip.id {
                    TimelineExternalTrimHandle(
                        edge: .left,
                        sourceClip: sourceClip,
                        zoom: zoom,
                        snappingEnabled: snappingEnabled,
                        trimmingClipID: $trimmingClipID,
                        trimPreviewClip: $trimPreviewClip,
                        trimSnapGuide: $trimSnapGuide,
                        viewModel: viewModel
                    )
                    .frame(width: 44, height: 44)
                    .offset(
                        x: playheadX + CGFloat(displayClip.timelineStart - viewModel.playhead) * zoom - 22,
                        y: 3
                    )
                    .zIndex(6000)

                    TimelineExternalTrimHandle(
                        edge: .right,
                        sourceClip: sourceClip,
                        zoom: zoom,
                        snappingEnabled: snappingEnabled,
                        trimmingClipID: $trimmingClipID,
                        trimPreviewClip: $trimPreviewClip,
                        trimSnapGuide: $trimSnapGuide,
                        viewModel: viewModel
                    )
                    .frame(width: 44, height: 44)
                    .offset(
                        x: playheadX + CGFloat(displayClip.timelineEnd - viewModel.playhead) * zoom - 22,
                        y: 3
                    )
                    .zIndex(6000)
                }
'''

new_handles = '''                if viewModel.selectedClipID == sourceClip.id,
                   movingClipID != sourceClip.id {
                    TimelineUnifiedTrimOverlay(
                        sourceClip: sourceClip,
                        zoom: zoom,
                        snappingEnabled: snappingEnabled,
                        trimmingClipID: $trimmingClipID,
                        trimPreviewClip: $trimPreviewClip,
                        trimSnapGuide: $trimSnapGuide,
                        viewModel: viewModel
                    )
                    .frame(
                        width: max(34, CGFloat(displayClip.playbackDuration) * zoom),
                        height: 44
                    )
                    .offset(
                        x: playheadX + CGFloat(displayClip.timelineStart - viewModel.playhead) * zoom,
                        y: 3
                    )
                    .zIndex(6000)
                }
'''

if old_handles not in timeline:
    raise SystemExit('Could not locate 1.6.7 external trim handle block')
timeline = timeline.replace(old_handles, new_handles, 1)

old_thumbnail = '                    clip: trimmingClipID == sourceClip.id ? sourceClip : displayClip,\n'
new_thumbnail = '                    clip: displayClip,\n'
if old_thumbnail not in timeline:
    raise SystemExit('Could not locate trim thumbnail source selection')
timeline = timeline.replace(old_thumbnail, new_thumbnail, 1)

insert_anchor = 'private struct TimelineExternalTrimHandle: View {'
if insert_anchor not in timeline:
    raise SystemExit('Could not locate external trim struct anchor')

unified_code = r'''private enum TimelineUnifiedTrimEdge {
    case left
    case right
}

private struct TimelineUnifiedTrimOverlay: View {
    let sourceClip: MediaClip
    let zoom: CGFloat
    let snappingEnabled: Bool

    @Binding var trimmingClipID: UUID?
    @Binding var trimPreviewClip: MediaClip?
    @Binding var trimSnapGuide: Double?

    @ObservedObject var viewModel: EditorViewModel

    @State private var trimOrigin: MediaClip?
    @State private var activeEdge: TimelineUnifiedTrimEdge?
    @State private var lastSnapGuide: Double?

    var body: some View {
        ZStack {
            UnifiedEdgeTrimCaptureView(
                onBegan: beginTrim,
                onChanged: updateTrim,
                onEnded: endTrim
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                trimHandle
                Spacer(minLength: 0)
                trimHandle
            }
            .allowsHitTesting(false)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var trimHandle: some View {
        Rectangle()
            .fill(handleColor)
            .frame(width: 15, height: 38)
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.96))
                    .frame(width: 2.5, height: 20)
            }
    }

    private func beginTrim(_ edge: TimelineUnifiedTrimEdge) {
        guard trimmingClipID == nil || trimmingClipID == sourceClip.id else { return }

        activeEdge = edge
        trimOrigin = sourceClip
        trimmingClipID = sourceClip.id
        trimPreviewClip = sourceClip
        trimSnapGuide = nil
        lastSnapGuide = nil

        viewModel.select(sourceClip)
        viewModel.pausePlayback()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateTrim(_ deltaX: CGFloat) {
        guard trimmingClipID == sourceClip.id,
              let origin = trimOrigin,
              let activeEdge else { return }

        let result = resolvedTrim(
            edge: activeEdge,
            origin: origin,
            deltaX: deltaX
        )
        trimPreviewClip = result.clip
        trimSnapGuide = result.guide

        if result.guide != lastSnapGuide {
            if result.guide != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            lastSnapGuide = result.guide
        }
    }

    private func endTrim() {
        guard trimmingClipID == sourceClip.id else {
            resetState()
            return
        }

        viewModel.commitNonRippleTrim(trimPreviewClip ?? sourceClip)
        resetState()
    }

    private func resetState() {
        trimOrigin = nil
        activeEdge = nil
        lastSnapGuide = nil

        if trimmingClipID == sourceClip.id {
            trimmingClipID = nil
        }
        if trimPreviewClip?.id == sourceClip.id {
            trimPreviewClip = nil
        }
        trimSnapGuide = nil
    }

    private func resolvedTrim(
        edge: TimelineUnifiedTrimEdge,
        origin: MediaClip,
        deltaX: CGFloat
    ) -> (clip: MediaClip, guide: Double?) {
        let timelineDelta = Double(deltaX / max(1, zoom))

        switch edge {
        case .left:
            var shortest = origin
            shortest.trimStart = max(0, origin.trimEnd - 0.05)

            var longest = origin
            longest.trimStart = 0

            let minimumBoundary = origin.timelineEnd - longest.playbackDuration
            let maximumBoundary = origin.timelineEnd - shortest.playbackDuration
            let proposedBoundary = origin.timelineStart + timelineDelta
            let snapped = snappedBoundary(
                proposed: proposedBoundary,
                minimum: minimumBoundary,
                maximum: maximumBoundary
            )

            let targetDuration = origin.timelineEnd - snapped.boundary
            var resolved = origin
            resolved.trimStart = trimStart(
                forPlaybackDuration: targetDuration,
                origin: origin
            )
            resolved.timelineStart = origin.timelineEnd - resolved.playbackDuration
            return (resolved, snapped.guide)

        case .right:
            var shortest = origin
            shortest.trimEnd = min(origin.sourceDuration, origin.trimStart + 0.05)

            var longest = origin
            longest.trimEnd = origin.sourceDuration

            let minimumBoundary = origin.timelineStart + shortest.playbackDuration
            let maximumBoundary = origin.timelineStart + longest.playbackDuration
            let proposedBoundary = origin.timelineEnd + timelineDelta
            let snapped = snappedBoundary(
                proposed: proposedBoundary,
                minimum: minimumBoundary,
                maximum: maximumBoundary
            )

            let targetDuration = snapped.boundary - origin.timelineStart
            var resolved = origin
            resolved.trimEnd = trimEnd(
                forPlaybackDuration: targetDuration,
                origin: origin
            )
            resolved.timelineStart = origin.timelineStart
            return (resolved, snapped.guide)
        }
    }

    private func snappedBoundary(
        proposed: Double,
        minimum: Double,
        maximum: Double
    ) -> (boundary: Double, guide: Double?) {
        let clamped = min(max(minimum, proposed), maximum)
        guard snappingEnabled else { return (clamped, nil) }

        let compatible = viewModel.project.clips.filter {
            guard $0.id != sourceClip.id else { return false }
            return sourceClip.kind == .audio ? $0.kind == .audio : $0.kind != .audio
        }

        let sameLayerTargets = compatible
            .filter { $0.layer == sourceClip.layer }
            .flatMap { [$0.timelineStart, $0.timelineEnd] }
        let otherTargets = compatible
            .filter { $0.layer != sourceClip.layer }
            .flatMap { [$0.timelineStart, $0.timelineEnd] }

        let threshold = min(0.20, max(0.04, Double(12 / max(1, zoom))))

        if let nearest = sameLayerTargets.min(by: { abs($0 - clamped) < abs($1 - clamped) }),
           abs(nearest - clamped) <= threshold,
           nearest >= minimum,
           nearest <= maximum {
            return (nearest, nearest)
        }

        if let nearest = otherTargets.min(by: { abs($0 - clamped) < abs($1 - clamped) }),
           abs(nearest - clamped) <= threshold,
           nearest >= minimum,
           nearest <= maximum {
            return (nearest, nearest)
        }

        return (clamped, nil)
    }

    private func trimStart(
        forPlaybackDuration target: Double,
        origin: MediaClip
    ) -> Double {
        var low = 0.0
        var high = max(0, origin.trimEnd - 0.05)

        for _ in 0..<24 {
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

    private func trimEnd(
        forPlaybackDuration target: Double,
        origin: MediaClip
    ) -> Double {
        var low = min(origin.sourceDuration, origin.trimStart + 0.05)
        var high = origin.sourceDuration

        for _ in 0..<24 {
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

    private var handleColor: Color {
        switch sourceClip.kind {
        case .video: .blue
        case .image: .teal
        case .audio: .green
        }
    }
}

private struct UnifiedEdgeTrimCaptureView: UIViewRepresentable {
    let onBegan: (TimelineUnifiedTrimEdge) -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UnifiedEdgeTrimHitView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.isExclusiveTouch = true
        view.isMultipleTouchEnabled = false

        let recognizer = UnifiedEdgeTrimImmediateRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDrag(_:))
        )
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: (TimelineUnifiedTrimEdge) -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: () -> Void

        init(
            onBegan: @escaping (TimelineUnifiedTrimEdge) -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc
        func handleDrag(_ recognizer: UnifiedEdgeTrimImmediateRecognizer) {
            switch recognizer.state {
            case .began:
                guard let edge = recognizer.activeEdge else { return }
                onBegan(edge)
                onChanged(0)

            case .changed:
                onChanged(recognizer.translationX)

            case .ended:
                onChanged(recognizer.translationX)
                onEnded()

            case .cancelled, .failed:
                onEnded()

            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

private final class UnifiedEdgeTrimHitView: UIView {
    private let maximumEdgeWidth: CGFloat = 44

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard bounds.contains(point), bounds.width > 0 else { return false }
        let edgeWidth = min(maximumEdgeWidth, bounds.width * 0.5)
        return point.x <= edgeWidth || point.x >= bounds.width - edgeWidth
    }
}

private final class UnifiedEdgeTrimImmediateRecognizer: UIGestureRecognizer {
    private var startWindowX: CGFloat?
    private(set) var translationX: CGFloat = 0
    private(set) var activeEdge: TimelineUnifiedTrimEdge?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible,
              touches.count == 1,
              let touch = touches.first,
              let view else {
            state = .failed
            return
        }

        let local = touch.location(in: view)
        activeEdge = local.x <= view.bounds.midX ? .left : .right
        startWindowX = touch.location(in: view.window).x
        translationX = 0
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let startWindowX, let touch = touches.first else { return }
        translationX = touch.location(in: view?.window).x - startWindowX
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let startWindowX, let touch = touches.first {
            translationX = touch.location(in: view?.window).x - startWindowX
        }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        startWindowX = nil
        translationX = 0
        activeEdge = nil
        super.reset()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

'''

timeline = timeline.replace(insert_anchor, unified_code + insert_anchor, 1)
timeline_path.write_text(timeline)

project = project.replace('MARKETING_VERSION: 1.6.7', 'MARKETING_VERSION: 1.6.8')
project = project.replace('CURRENT_PROJECT_VERSION: 16', 'CURRENT_PROJECT_VERSION: 17')
project_path.write_text(project)

header = '''## 1.6.8\n\n### Fixed\n\n- Replaced the two independent 44-point trim touch targets with one unified edge interaction layer for the selected clip.\n- Left and right trim hit regions are dynamically limited to at most half the current clip width, so they can never overlap on short clips.\n- The trim edge is locked from the initial touch position: the left half can only change trimStart and the right half can only change trimEnd until the finger is released.\n- Timeline filmstrip thumbnails now follow the live displayClip during trimming, so trimming the beginning immediately shows the new first frames instead of visually looking like an end trim.\n- Kept immediate touch-down ownership, magnetic snapping, haptic feedback, speed-ramp duration mapping, and the 0.8-second center long-press move gesture.\n\n'''
if '## 1.6.8' not in changelog:
    changelog = changelog.replace('# Changelog\n\n', '# Changelog\n\n' + header, 1)
changelog_path.write_text(changelog)
