import SwiftUI
import UIKit

struct TimelineView: View {
    @ObservedObject var viewModel: EditorViewModel

    @State private var zoom: CGFloat = 78
    @State private var trackHeight: CGFloat = 50
    @State private var panOriginTime: Double?
    @State private var verticalOriginOffset: CGFloat?
    @State private var verticalOffset: CGFloat = 0
    @State private var panAxis: TimelinePanAxis?
    @State private var snappingEnabled = true
    @State private var isPinching = false
    @State private var pinchOriginZoom: CGFloat?
    @State private var pinchAnchorX: CGFloat?
    @State private var pinchAnchorTime: Double?

    @State private var movingClipID: UUID?
    @State private var movePreview: TimelineMovePreview?

    @State private var trimmingClipID: UUID?
    @State private var trimPreviewClip: MediaClip?
    @State private var trimSnapGuide: Double?

    private let labelWidth: CGFloat = 44
    private let rowSpacing: CGFloat = 7

    private var rowHeight: CGFloat { trackHeight }

    var body: some View {
        VStack(spacing: 0) {
            timelineHeader

            GeometryReader { proxy in
                let playheadX = labelWidth + (proxy.size.width - labelWidth) / 2

                VStack(spacing: 0) {
                    ruler(width: proxy.size.width, playheadX: playheadX)

                    if viewModel.project.clips.isEmpty {
                        emptyTimeline(
                            playheadX: playheadX,
                            height: max(60, proxy.size.height - 28)
                        )
                    } else {
                        timelineTracks(
                            playheadX: playheadX,
                            viewportHeight: max(60, proxy.size.height - 28)
                        )
                    }
                }
                .simultaneousGesture(
                    timelineMagnifyGesture(
                        viewportWidth: proxy.size.width,
                        playheadX: playheadX
                    )
                )
            }
        }
        .background(Color(red: 0.045, green: 0.045, blue: 0.052))
        .onChange(of: trackNumbers.count) { _, _ in
            verticalOffset = min(0, verticalOffset)
        }
    }

    private enum TimelinePanAxis {
        case horizontal
        case vertical
    }

    fileprivate struct TimelineMovePreview: Equatable {
        var clipID: UUID
        var placement: ClipMovePlacement
    }

    private var trackNumbers: [Int] {
        var visualLayers = viewModel.project.clips
            .filter { $0.kind != .audio }
            .map(\.layer)
        var audioIndices = viewModel.project.clips
            .filter { $0.kind == .audio }
            .map { max(0, $0.layer - EditorViewModel.audioLayerBase) }

        if let previewLayer = movePreview?.placement.layer {
            if previewLayer >= EditorViewModel.audioLayerBase {
                audioIndices.append(max(0, previewLayer - EditorViewModel.audioLayerBase))
            } else {
                visualLayers.append(max(0, previewLayer))
            }
        }

        let visuals: [Int]
        if let highestVisual = visualLayers.max() {
            let visualTop = min(8, max(0, highestVisual))
            visuals = Array(stride(from: visualTop, through: 0, by: -1))
        } else {
            visuals = []
        }

        let audios: [Int]
        if let highestAudio = audioIndices.max() {
            let audioTop = min(7, max(0, highestAudio))
            audios = Array(0...audioTop).map { EditorViewModel.audioLayerBase + $0 }
        } else {
            audios = []
        }

        return visuals + audios
    }

    private var contentHeight: CGFloat {
        let rows = CGFloat(trackNumbers.count)
        return rows * rowHeight + max(0, rows - 1) * rowSpacing + 16
    }

    private var timelineHeader: some View {
        HStack(spacing: 10) {
            Text("CUT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.09), in: Capsule())

            Text(viewModel.playhead.formattedDuration)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))

            Spacer()

            Button {
                snappingEnabled.toggle()
            } label: {
                Image(systemName: "magnet.fill")
                    .foregroundStyle(snappingEnabled ? Color.orange : Color.white.opacity(0.42))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(snappingEnabled ? "Отключить привязку" : "Включить привязку")

            Text("−H")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))

            Slider(value: $trackHeight, in: 46...86)
                .frame(maxWidth: 110)
                .tint(.white)
                .accessibilityLabel("Высота дорожек")

            Text("+H")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(Color(red: 0.063, green: 0.063, blue: 0.072))
    }

    private func ruler(width: CGFloat, playheadX: CGFloat) -> some View {
        Canvas { context, size in
            let step = tickStep
            let visibleLeft = max(0, viewModel.playhead - Double(playheadX / zoom))
            let visibleRight = max(
                visibleLeft,
                viewModel.playhead + Double((width - playheadX) / zoom)
            )
            let firstTick = floor(visibleLeft / step) * step
            var time = firstTick

            while time <= visibleRight + step {
                let x = playheadX + CGFloat(time - viewModel.playhead) * zoom
                if x >= labelWidth - 1 && x <= size.width + 1 {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 15))
                    path.addLine(to: CGPoint(x: x, y: 26))
                    context.stroke(path, with: .color(.white.opacity(0.24)), lineWidth: 1)
                    context.draw(
                        Text(timeLabel(time))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.48)),
                        at: CGPoint(x: x + 16, y: 7)
                    )
                }
                time += step
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(red: 0.063, green: 0.063, blue: 0.072))
                .frame(width: labelWidth)
                .overlay {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                }
        }
        .frame(height: 28)
        .background(Color(red: 0.052, green: 0.052, blue: 0.06))
        .contentShape(Rectangle())
        .gesture(rulerPanGesture)
    }

    private func emptyTimeline(playheadX: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ContentUnavailableView(
                "Таймлайн пуст",
                systemImage: "timeline.selection",
                description: Text("Добавьте медиа, чтобы начать монтаж.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            fixedPlayhead(x: playheadX, height: height)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(rulerPanGesture)
    }

    private func timelineTracks(playheadX: CGFloat, viewportHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())

            VStack(spacing: rowSpacing) {
                ForEach(trackNumbers, id: \.self) { layer in
                    track(layer, playheadX: playheadX)
                }
            }
            .padding(.vertical, 8)
            .offset(y: verticalOffset)

            if let guide = movePreview?.placement.snapGuide {
                let guideX = playheadX + CGFloat(guide - viewModel.playhead) * zoom
                Rectangle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 1.5, height: viewportHeight)
                    .position(x: guideX, y: viewportHeight / 2)
                    .mask(alignment: .leading) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: labelWidth)
                            Rectangle().fill(.white)
                        }
                    }
                    .allowsHitTesting(false)
            }

            if let guide = trimSnapGuide {
                let guideX = playheadX + CGFloat(guide - viewModel.playhead) * zoom
                Rectangle()
                    .fill(Color.orange.opacity(0.95))
                    .frame(width: 1.5, height: viewportHeight)
                    .position(x: guideX, y: viewportHeight / 2)
                    .mask(alignment: .leading) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: labelWidth)
                            Rectangle().fill(.white)
                        }
                    }
                    .allowsHitTesting(false)
            }

            fixedPlayhead(x: playheadX, height: viewportHeight)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(
            timelineNavigationGesture(viewportHeight: viewportHeight),
            including: trimmingClipID == nil ? .all : .none
        )
        .clipped()
    }

    @ViewBuilder
    private func track(_ layer: Int, playheadX: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(
                    viewModel.selectedTrackLayer == layer
                        ? Color.blue.opacity(0.10)
                        : (movePreview?.placement.layer == layer ? Color.red.opacity(0.055) : Color.white.opacity(0.025))
                )
                .padding(.leading, labelWidth)
                .allowsHitTesting(false)

            ZStack(alignment: .leading) {
                if let preview = movePreview,
                   preview.placement.layer == layer,
                   let clip = viewModel.project.clips.first(where: { $0.id == preview.clipID }) {
                Rectangle()
                    .fill(Color.red.opacity(0.10))
                    .overlay {
                        Rectangle()
                            .stroke(
                                Color.red.opacity(0.8),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                            )
                    }
                    .frame(
                        width: max(34, CGFloat(clip.playbackDuration) * zoom),
                        height: rowHeight - 8
                    )
                    .offset(
                        x: playheadX + CGFloat(preview.placement.timelineStart - viewModel.playhead) * zoom,
                        y: 4
                    )
                    .allowsHitTesting(false)
                    .zIndex(20)
            }

            ForEach(viewModel.project.clips.filter { $0.layer == layer }) { sourceClip in
                let displayClip = displayedClip(for: sourceClip)

                TimelineClipView(
                    sourceClip: sourceClip,
                    displayClip: displayClip,
                    selected: viewModel.selectedClipID == sourceClip.id,
                    zoom: zoom,
                    rowStride: rowHeight + rowSpacing,
                    laneOrder: trackNumbers,
                    snappingEnabled: snappingEnabled,
                    movingClipID: $movingClipID,
                    movePreview: $movePreview,
                    trimmingClipID: $trimmingClipID,
                    trimPreviewClip: $trimPreviewClip,
                    trimSnapGuide: $trimSnapGuide,
                    mediaURL: viewModel.mediaURL(for: sourceClip),
                    viewModel: viewModel
                )
                .frame(
                    width: max(34, CGFloat(displayClip.playbackDuration) * zoom),
                    height: rowHeight - 8
                )
                .offset(
                    x: playheadX + CGFloat(displayClip.timelineStart - viewModel.playhead) * zoom,
                    y: 4
                )
                .onTapGesture {
                    guard movingClipID == nil, trimmingClipID == nil, !isPinching else { return }
                    viewModel.select(sourceClip)
                }
                .accessibilityLabel("\(sourceClip.fileName), \(displayClip.playbackDuration.formattedDuration)")
                .zIndex(
                    movingClipID == sourceClip.id || trimmingClipID == sourceClip.id
                        ? 1000
                        : 30
                )


                if viewModel.selectedClipID == sourceClip.id,
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
            }

            }
            .mask(alignment: .leading) {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: labelWidth)
                    Rectangle()
                        .fill(.white)
                }
            }

            Button {
                guard movingClipID == nil, trimmingClipID == nil, !isPinching else { return }
                viewModel.selectTrack(layer)
            } label: {
                Rectangle()
                    .fill(
                        viewModel.selectedTrackLayer == layer
                            ? Color.blue.opacity(0.28)
                            : Color(red: 0.072, green: 0.072, blue: 0.082)
                    )
                    .frame(width: labelWidth)
                    .overlay(alignment: .leading) {
                        HStack(spacing: 4) {
                            Text(layerName(layer))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(
                                    viewModel.selectedTrackLayer == layer
                                        ? Color.white
                                        : Color.white.opacity(0.72)
                                )

                            Image(systemName: layer >= EditorViewModel.audioLayerBase ? "speaker.wave.1.fill" : "film.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(
                                    viewModel.selectedTrackLayer == layer
                                        ? Color.white.opacity(0.82)
                                        : Color.white.opacity(0.34)
                                )
                        }
                        .padding(.leading, 6)
                    }
            }
            .buttonStyle(.plain)
            .frame(width: labelWidth, height: rowHeight)
            .contentShape(Rectangle())
            .accessibilityLabel("Выбрать дорожку \(layerName(layer))")
            .zIndex(10000)
        }
        .frame(height: rowHeight)
    }

    private func displayedClip(for sourceClip: MediaClip) -> MediaClip {
        if let trimPreviewClip, trimPreviewClip.id == sourceClip.id {
            return trimPreviewClip
        }
        return sourceClip
    }

    private func fixedPlayhead(x: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 11))
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color.red)
                .offset(y: -1)

            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: max(48, height - 12))
        }
        .position(x: x, y: max(30, height / 2))
    }

    private func timelineNavigationGesture(viewportHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard movingClipID == nil, trimmingClipID == nil, !isPinching else { return }

                let dx = value.translation.width
                let dy = value.translation.height

                if panAxis == nil {
                    guard max(abs(dx), abs(dy)) >= 7 else { return }

                    if abs(dx) >= abs(dy) {
                        panAxis = .horizontal
                        panOriginTime = viewModel.playhead
                    } else {
                        panAxis = .vertical
                        verticalOriginOffset = verticalOffset
                    }
                }

                switch panAxis {
                case .horizontal:
                    guard let origin = panOriginTime else { return }
                    let rawTime = origin - Double(dx / zoom)
                    viewModel.scrubTimeline(to: snappedTime(rawTime))

                case .vertical:
                    guard let origin = verticalOriginOffset else { return }
                    let minimumOffset = min(0, viewportHeight - contentHeight)
                    verticalOffset = min(0, max(minimumOffset, origin + dy))

                case .none:
                    break
                }
            }
            .onEnded { _ in
                panOriginTime = nil
                verticalOriginOffset = nil
                panAxis = nil
            }
    }

    private func timelineMagnifyGesture(
        viewportWidth: CGFloat,
        playheadX: CGFloat
    ) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard movingClipID == nil, trimmingClipID == nil else { return }

                if pinchOriginZoom == nil {
                    isPinching = true
                    pinchOriginZoom = zoom
                    let anchorX = min(max(labelWidth, value.startLocation.x), viewportWidth)
                    pinchAnchorX = anchorX
                    pinchAnchorTime = viewModel.playhead + Double((anchorX - playheadX) / max(1, zoom))
                    viewModel.pausePlayback()
                }

                guard let originZoom = pinchOriginZoom,
                      let anchorX = pinchAnchorX,
                      let anchorTime = pinchAnchorTime else { return }

                let newZoom = min(220, max(30, originZoom * value.magnification))
                zoom = newZoom

                let anchoredPlayhead = anchorTime - Double((anchorX - playheadX) / max(1, newZoom))
                viewModel.playhead = min(
                    max(0, anchoredPlayhead),
                    max(0, viewModel.project.duration)
                )
            }
            .onEnded { _ in
                let finalTime = viewModel.playhead
                isPinching = false
                pinchOriginZoom = nil
                pinchAnchorX = nil
                pinchAnchorTime = nil
                viewModel.scrubTimeline(to: finalTime)
            }
    }

    private var rulerPanGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard movingClipID == nil, trimmingClipID == nil, !isPinching else { return }

                if panOriginTime == nil {
                    panOriginTime = viewModel.playhead
                }

                guard let origin = panOriginTime else { return }
                let rawTime = origin - Double(value.translation.width / zoom)
                viewModel.scrubTimeline(to: snappedTime(rawTime))
            }
            .onEnded { _ in
                panOriginTime = nil
            }
    }

    private func snappedTime(_ value: Double) -> Double {
        let duration = max(0, viewModel.project.duration)
        var time = min(max(0, value), duration)
        let fps = max(1, viewModel.project.frameRate)
        time = (time * Double(fps)).rounded() / Double(fps)

        guard snappingEnabled else { return time }

        var candidates = viewModel.project.clips.flatMap { [$0.timelineStart, $0.timelineEnd] }
        candidates.append(time.rounded())
        let threshold = min(0.20, max(0.04, Double(10 / max(1, zoom))))

        if let nearest = candidates.min(by: { abs($0 - time) < abs($1 - time) }),
           abs(nearest - time) <= threshold {
            return min(max(0, nearest), duration)
        }

        return time
    }

    private var tickStep: Double {
        if zoom >= 120 { return 0.5 }
        return 1
    }

    private func timeLabel(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.1f", seconds)
        }

        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    private func layerName(_ layer: Int) -> String {
        if layer >= EditorViewModel.audioLayerBase {
            return "A\(layer - EditorViewModel.audioLayerBase + 1)"
        }
        return "V\(layer + 1)"
    }
}

private struct TimelineClipView: View {
    let sourceClip: MediaClip
    let displayClip: MediaClip
    let selected: Bool
    let zoom: CGFloat
    let rowStride: CGFloat
    let laneOrder: [Int]
    let snappingEnabled: Bool

    @Binding var movingClipID: UUID?
    @Binding var movePreview: TimelineView.TimelineMovePreview?

    @Binding var trimmingClipID: UUID?
    @Binding var trimPreviewClip: MediaClip?
    @Binding var trimSnapGuide: Double?

    let mediaURL: URL
    @ObservedObject var viewModel: EditorViewModel

    @State private var isMoving = false
    @State private var moveTranslation: CGSize = .zero
    @State private var lastMoveSnapGuide: Double?
    @GestureState private var moveGestureActive = false

    @State private var trimOrigin: MediaClip?
    @State private var activeTrimEdge: TrimEdge?
    @State private var lastTrimSnapGuide: Double?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            clipVisual

            if sourceClip.kind != .audio {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }

            HStack(spacing: 4) {
                Image(systemName: sourceClip.kind.icon)

                Text(sourceClip.fileName)
                    .lineLimit(1)

                if sourceClip.speedPoints != SpeedPoint.linear {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.8), radius: 2)
            .padding(.horizontal, selected ? 13 : 5)
            .padding(.bottom, 3)
        }
        .background(clipColor)
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .strokeBorder(
                    isMoving
                        ? Color.red
                        : (selected ? Color.white : Color.white.opacity(0.14)),
                    lineWidth: isMoving ? 2 : (selected ? 2 : 1)
                )
        }
        .overlay(alignment: .topTrailing) {
            if isMoving, let placement = movePreview?.placement {
                Text(trackName(placement.layer))
                    .font(.caption2.monospaced().weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(3)
            }
        }
        .scaleEffect(1, anchor: .center)
        .offset(isMoving ? moveTranslation : .zero)
        .zIndex(isMoving || trimmingClipID == sourceClip.id ? 1000 : 0)
        .transaction { transaction in
            transaction.animation = nil
        }
        .overlay {
            GeometryReader { proxy in
                let edgeExclusion = selected
                    ? min(44, max(18, proxy.size.width * 0.28))
                    : 0

                Color.clear
                    .frame(
                        width: max(0, proxy.size.width - edgeExclusion * 2),
                        height: proxy.size.height
                    )
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height / 2
                    )
                    .contentShape(Rectangle())
                    .simultaneousGesture(clipMoveGesture)
            }
        }
        .onChange(of: moveGestureActive) { _, active in
            if !active, isMoving {
                resetMoveState()
            }
        }
        .onChange(of: movingClipID) { _, id in
            if id != sourceClip.id, isMoving {
                isMoving = false
                moveTranslation = .zero
                lastMoveSnapGuide = nil
            }
        }
    }

    private enum TrimEdge {
        case left
        case right
    }

    @ViewBuilder
    private var clipVisual: some View {
        GeometryReader { proxy in
            switch sourceClip.kind {
            case .video:
                TimelineThumbnailStrip(
                    clip: displayClip,
                    url: mediaURL,
                    width: proxy.size.width,
                    height: proxy.size.height
                )

            case .image:
                if let image = UIImage(contentsOfFile: mediaURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Rectangle().fill(clipColor)
                }

            case .audio:
                TimelineWaveformPlaceholder()
                    .padding(.horizontal, 4)
            }
        }
    }

    private func trimHandle(edge: TrimEdge) -> some View {
        ZStack(alignment: edge == .left ? .leading : .trailing) {
            EdgeTrimPanCaptureView(
                onBegan: {
                    beginTrim(edge: edge)
                },
                onChanged: { deltaX in
                    updateTrim(edge: edge, deltaX: deltaX)
                },
                onEnded: {
                    endTrim()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(handleColor)
                .frame(width: 15, height: 38)
                .overlay {
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: 2.5, height: 20)
                }
                .allowsHitTesting(false)
        }
        .frame(width: trimTouchWidth, height: 44)
        .contentShape(Rectangle())
        .zIndex(5000)
        .accessibilityLabel(edge == .left ? "Обрезать начало клипа" : "Обрезать конец клипа")
    }

    private var trimTouchWidth: CGFloat {
        44
    }

    private func beginTrim(edge: TrimEdge) {
        guard !isMoving else { return }

        activeTrimEdge = edge
        trimOrigin = sourceClip
        trimmingClipID = sourceClip.id
        trimPreviewClip = sourceClip
        trimSnapGuide = nil
        lastTrimSnapGuide = nil

        viewModel.select(sourceClip)
        viewModel.pausePlayback()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func updateTrim(edge: TrimEdge, deltaX: CGFloat) {
        guard activeTrimEdge == edge,
              let origin = trimOrigin,
              trimmingClipID == sourceClip.id else {
            return
        }

        let result = resolvedTrim(edge: edge, origin: origin, deltaX: deltaX)
        trimPreviewClip = result.clip
        trimSnapGuide = result.guide

        if result.guide != lastTrimSnapGuide {
            if result.guide != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            lastTrimSnapGuide = result.guide
        }
    }

    private func endTrim() {
        guard trimmingClipID == sourceClip.id else {
            resetTrimState()
            return
        }

        let finalClip = trimPreviewClip ?? sourceClip

        viewModel.commitNonRippleTrim(finalClip)

        resetTrimState()
    }

    private func resetTrimState() {
        activeTrimEdge = nil
        trimOrigin = nil
        lastTrimSnapGuide = nil

        if trimmingClipID == sourceClip.id {
            trimmingClipID = nil
        }

        if trimPreviewClip?.id == sourceClip.id {
            trimPreviewClip = nil
        }

        trimSnapGuide = nil
    }

    private func resolvedTrim(
        edge: TrimEdge,
        origin: MediaClip,
        deltaX: CGFloat
    ) -> (clip: MediaClip, guide: Double?) {
        let timelineDelta = Double(deltaX / max(1, zoom))
        let sourcePerTimeline = origin.trimmedDuration / max(0.000_001, origin.playbackDuration)

        switch edge {
        case .left:
            var minimumSource = origin
            minimumSource.trimStart = max(0, origin.trimEnd - 0.05)

            var maximumSource = origin
            maximumSource.trimStart = 0

            let minimumBoundary = origin.timelineEnd - maximumSource.playbackDuration
            let maximumBoundary = origin.timelineEnd - minimumSource.playbackDuration
            let proposedBoundary = origin.timelineStart + timelineDelta
            let snapped = snappedTrimBoundary(
                proposed: proposedBoundary,
                minimum: minimumBoundary,
                maximum: maximumBoundary
            )

            let effectiveTimelineDelta = snapped.boundary - origin.timelineStart
            let sourceDelta = effectiveTimelineDelta * sourcePerTimeline

            var resolved = origin
            resolved.trimStart = min(
                max(0, origin.trimStart + sourceDelta),
                origin.trimEnd - 0.05
            )
            resolved.timelineStart = origin.timelineEnd - resolved.playbackDuration
            return (resolved, snapped.guide)

        case .right:
            var minimumSource = origin
            minimumSource.trimEnd = min(origin.sourceDuration, origin.trimStart + 0.05)

            var maximumSource = origin
            maximumSource.trimEnd = origin.sourceDuration

            let minimumBoundary = origin.timelineStart + minimumSource.playbackDuration
            let maximumBoundary = origin.timelineStart + maximumSource.playbackDuration
            let proposedBoundary = origin.timelineEnd + timelineDelta
            let snapped = snappedTrimBoundary(
                proposed: proposedBoundary,
                minimum: minimumBoundary,
                maximum: maximumBoundary
            )

            let effectiveTimelineDelta = snapped.boundary - origin.timelineEnd
            let sourceDelta = effectiveTimelineDelta * sourcePerTimeline

            var resolved = origin
            resolved.trimEnd = max(
                origin.trimStart + 0.05,
                min(origin.sourceDuration, origin.trimEnd + sourceDelta)
            )
            resolved.timelineStart = origin.timelineStart
            return (resolved, snapped.guide)
        }
    }

    private func snappedTrimBoundary(
        proposed: Double,
        minimum: Double,
        maximum: Double
    ) -> (boundary: Double, guide: Double?) {
        guard snappingEnabled else {
            return (min(max(minimum, proposed), maximum), nil)
        }

        let compatible = viewModel.project.clips.filter {
            guard $0.id != sourceClip.id else { return false }

            if sourceClip.kind == .audio {
                return $0.kind == .audio
            }

            return $0.kind != .audio
        }

        let sameLayerTargets = compatible
            .filter { $0.layer == sourceClip.layer }
            .flatMap { [$0.timelineStart, $0.timelineEnd] }

        let otherTargets = compatible
            .filter { $0.layer != sourceClip.layer }
            .flatMap { [$0.timelineStart, $0.timelineEnd] }

        let threshold = min(0.20, max(0.04, Double(12 / max(1, zoom))))

        if let nearest = sameLayerTargets.min(by: {
            abs($0 - proposed) < abs($1 - proposed)
        }),
           abs(nearest - proposed) <= threshold,
           nearest >= minimum,
           nearest <= maximum {
            return (nearest, nearest)
        }

        if let nearest = otherTargets.min(by: {
            abs($0 - proposed) < abs($1 - proposed)
        }),
           abs(nearest - proposed) <= threshold,
           nearest >= minimum,
           nearest <= maximum {
            return (nearest, nearest)
        }

        return (min(max(minimum, proposed), maximum), nil)
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

        return min(
            max(0, (low + high) * 0.5),
            origin.trimEnd - 0.05
        )
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

        return max(
            origin.trimStart + 0.05,
            min(origin.sourceDuration, (low + high) * 0.5)
        )
    }

    private var clipMoveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.50, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($moveGestureActive) { value, state, _ in
                switch value {
                case .first(true), .second(true, _):
                    state = true
                default:
                    state = false
                }
            }
            .onChanged { value in
                guard trimmingClipID == nil else { return }

                switch value {
                case .first(true):
                    activateMoveIfNeeded()

                case .second(true, let dragValue):
                    activateMoveIfNeeded()
                    guard let dragValue else { return }
                    updateMove(with: dragValue.translation)

                default:
                    break
                }
            }
            .onEnded { value in
                guard trimmingClipID == nil else {
                    resetMoveState()
                    return
                }

                var finalPlacement: ClipMovePlacement?

                if case .second(true, let dragValue) = value,
                   let dragValue {
                    finalPlacement = placement(for: dragValue.translation)
                }

                if let finalPlacement {
                    viewModel.commitClipMove(
                        id: sourceClip.id,
                        placement: finalPlacement
                    )
                }

                resetMoveState()
            }
    }

    private func activateMoveIfNeeded() {
        guard !isMoving, trimmingClipID == nil else { return }

        isMoving = true
        movingClipID = sourceClip.id
        viewModel.select(sourceClip)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateMove(with rawTranslation: CGSize) {
        guard let placement = placement(for: rawTranslation) else { return }

        movePreview = TimelineView.TimelineMovePreview(
            clipID: sourceClip.id,
            placement: placement
        )

        let snappedX = CGFloat(
            placement.timelineStart - sourceClip.timelineStart
        ) * zoom

        moveTranslation = CGSize(
            width: snappedX,
            height: rawTranslation.height
        )

        if placement.snapGuide != lastMoveSnapGuide {
            if placement.snapGuide != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            lastMoveSnapGuide = placement.snapGuide
        }
    }

    private func placement(for rawTranslation: CGSize) -> ClipMovePlacement? {
        let rawStart = sourceClip.timelineStart + Double(rawTranslation.width / zoom)
        let targetLayer = moveTargetLayer(for: rawTranslation.height)

        return viewModel.previewClipMove(
            id: sourceClip.id,
            proposedStart: rawStart,
            requestedLayer: targetLayer,
            snappingEnabled: snappingEnabled
        )
    }

    private func resetMoveState() {
        isMoving = false
        moveTranslation = .zero
        lastMoveSnapGuide = nil

        if movingClipID == sourceClip.id {
            movingClipID = nil
        }

        if movePreview?.clipID == sourceClip.id {
            movePreview = nil
        }
    }

    private func moveTargetLayer(for verticalTranslation: CGFloat) -> Int {
        let deltaRows = Int(
            (verticalTranslation / max(1, rowStride)).rounded()
        )

        if sourceClip.kind == .audio {
            let highestIndex = viewModel.project.clips
                .filter { $0.kind == .audio }
                .map { max(0, $0.layer - EditorViewModel.audioLayerBase) }
                .max() ?? max(0, sourceClip.layer - EditorViewModel.audioLayerBase)
            let lanes = Array(0...max(0, highestIndex)).map { EditorViewModel.audioLayerBase + $0 }
            let sourceIndex = lanes.firstIndex(of: sourceClip.layer) ?? 0
            let rawTargetIndex = sourceIndex + deltaRows

            if rawTargetIndex >= lanes.count, highestIndex < 7 {
                return EditorViewModel.audioLayerBase + highestIndex + 1
            }

            return lanes[min(max(0, rawTargetIndex), lanes.count - 1)]
        }

        let highestVisual = viewModel.project.clips
            .filter { $0.kind != .audio }
            .map(\.layer)
            .max() ?? sourceClip.layer
        let visualTop = min(8, max(0, highestVisual))
        let lanes = Array(stride(from: visualTop, through: 0, by: -1))
        let sourceIndex = lanes.firstIndex(of: sourceClip.layer) ?? 0
        let rawTargetIndex = sourceIndex + deltaRows

        if rawTargetIndex < 0, visualTop < 8 {
            return visualTop + 1
        }

        return lanes[min(max(0, rawTargetIndex), lanes.count - 1)]
    }

    private func trackName(_ layer: Int) -> String {
        if layer >= EditorViewModel.audioLayerBase {
            return "A\(layer - EditorViewModel.audioLayerBase + 1)"
        }

        return "V\(layer + 1)"
    }

    private var handleColor: Color {
        switch sourceClip.kind {
        case .video:
            return .blue
        case .image:
            return .teal
        case .audio:
            return .green
        }
    }

    private var clipColor: Color {
        switch sourceClip.kind {
        case .video:
            return Color(red: 0.16, green: 0.18, blue: 0.22)
        case .image:
            return Color(red: 0.15, green: 0.32, blue: 0.34)
        case .audio:
            return Color(red: 0.12, green: 0.34, blue: 0.22)
        }
    }
}

private enum TimelineUnifiedTrimEdge {
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
        viewModel.updateTrimPreviewFrame(
            for: sourceClip,
            showingStart: edge == .left
        )
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
        viewModel.updateTrimPreviewFrame(
            for: result.clip,
            showingStart: activeEdge == .left
        )

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
        viewModel.clearTrimPreviewFrame()
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

        let wholeSecond = clamped.rounded()
        if abs(wholeSecond - clamped) <= threshold,
           wholeSecond >= minimum,
           wholeSecond <= maximum {
            return (wholeSecond, wholeSecond)
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

private struct TimelineExternalTrimHandle: View {
    enum Edge {
        case left
        case right
    }

    let edge: Edge
    let sourceClip: MediaClip
    let zoom: CGFloat
    let snappingEnabled: Bool

    @Binding var trimmingClipID: UUID?
    @Binding var trimPreviewClip: MediaClip?
    @Binding var trimSnapGuide: Double?

    @ObservedObject var viewModel: EditorViewModel

    @State private var trimOrigin: MediaClip?
    @State private var lastSnapGuide: Double?

    var body: some View {
        ZStack {
            EdgeTrimPanCaptureView(
                onBegan: beginTrim,
                onChanged: updateTrim,
                onEnded: endTrim
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(handleColor)
                .frame(width: 15, height: 38)
                .overlay {
                    Capsule()
                        .fill(.white.opacity(0.96))
                        .frame(width: 2.5, height: 20)
                }
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityLabel(edge == .left ? "Обрезать начало клипа" : "Обрезать конец клипа")
    }

    private func beginTrim() {
        guard trimmingClipID == nil || trimmingClipID == sourceClip.id else { return }

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
              let origin = trimOrigin else { return }

        let result = resolvedTrim(origin: origin, deltaX: deltaX)
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

private struct EdgeTrimPanCaptureView: UIViewRepresentable {
    let onBegan: () -> Void
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
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.isExclusiveTouch = true
        view.isMultipleTouchEnabled = false

        let recognizer = EdgeTrimImmediateDragRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
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
        var onBegan: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: () -> Void

        init(
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGFloat) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc
        func handlePan(_ recognizer: EdgeTrimImmediateDragRecognizer) {
            let translationX = recognizer.translationX

            switch recognizer.state {
            case .began:
                onBegan()
                onChanged(translationX)

            case .changed:
                onChanged(translationX)

            case .ended:
                onChanged(translationX)
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

private final class EdgeTrimImmediateDragRecognizer: UIGestureRecognizer {
    private var startX: CGFloat?
    private(set) var translationX: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible, touches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }

        startX = touch.location(in: view?.window).x
        translationX = 0
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let startX, let touch = touches.first else { return }
        translationX = touch.location(in: view?.window).x - startX
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let startX, let touch = touches.first {
            translationX = touch.location(in: view?.window).x - startX
        }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        startX = nil
        translationX = 0
        super.reset()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}

private struct TimelineThumbnailStrip: View {
    let clip: MediaClip
    let url: URL
    let width: CGFloat
    let height: CGFloat

    @State private var images: [UIImage] = []

    private var count: Int {
        min(16, max(1, Int(ceil(width / 52))))
    }

    private var requestKey: String {
        "\(clip.id.uuidString)-\(String(format: "%.3f", clip.trimStart))-\(String(format: "%.3f", clip.trimEnd))-\(count)-\(Int(height))"
    }

    var body: some View {
        HStack(spacing: 1) {
            if images.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        Image(systemName: "film")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.28))
                    }
            } else {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: max(1, width / CGFloat(images.count)),
                            height: height
                        )
                        .clipped()
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: requestKey) {
            images = await TimelineThumbnailService.shared.thumbnails(
                for: clip,
                url: url,
                count: count,
                pixelHeight: height * UIScreen.main.scale
            )
        }
    }
}

private struct TimelineWaveformPlaceholder: View {
    var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            var x: CGFloat = 1
            var index: CGFloat = 0

            while x < size.width {
                let phase =
                    sin(index * 0.72) * 0.45 +
                    cos(index * 0.31) * 0.25
                let amplitude = max(
                    3,
                    abs(phase) * size.height * 0.40
                )

                var path = Path()
                path.move(
                    to: CGPoint(
                        x: x,
                        y: centerY - amplitude
                    )
                )
                path.addLine(
                    to: CGPoint(
                        x: x,
                        y: centerY + amplitude
                    )
                )

                context.stroke(
                    path,
                    with: .color(.white.opacity(0.58)),
                    lineWidth: 1.2
                )

                x += 3
                index += 1
            }
        }
    }
}

struct ClipActionBar: View {
    @ObservedObject var viewModel: EditorViewModel
    let importAction: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                action("Добавить", icon: "plus", action: importAction)

                action("Разделить", icon: "scissors") {
                    viewModel.splitSelected(at: viewModel.playhead)
                }
                .disabled(viewModel.selectedClip == nil)

                action("Скорость", icon: "gauge.with.dots.needle.67percent") {
                    viewModel.openSpeedRamp()
                }
                .disabled(viewModel.selectedClip == nil)

                action("Эффекты", icon: "slider.horizontal.3") {
                    viewModel.openClipTools()
                }
                .disabled(viewModel.selectedClip == nil)

                action("Копия", icon: "plus.square.on.square") {
                    viewModel.duplicateSelected()
                }
                .disabled(viewModel.selectedClip == nil)

                action(
                    viewModel.selectedClip?.isMuted == true
                        ? "Включить звук"
                        : "Без звука",
                    icon: "speaker.slash"
                ) {
                    viewModel.toggleMuteSelected()
                }
                .disabled(viewModel.selectedClip == nil)

                action("Удалить", icon: "trash", role: .destructive) {
                    viewModel.deleteSelected()
                }
                .disabled(viewModel.selectedClip == nil)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 70)
        .background(.ultraThinMaterial)
    }

    private func action(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)

                Text(title)
                    .font(.caption2)
            }
            .frame(minWidth: 62, minHeight: 48)
        }
        .buttonStyle(.plain)
    }
}
