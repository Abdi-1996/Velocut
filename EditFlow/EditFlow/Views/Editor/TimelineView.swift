import SwiftUI
import UIKit

struct TimelineView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var zoom: CGFloat = 78
    @State private var panOriginTime: Double?
    @State private var verticalOriginOffset: CGFloat?
    @State private var verticalOffset: CGFloat = 0
    @State private var panAxis: TimelinePanAxis?
    @State private var snappingEnabled = true
    @State private var movingClipID: UUID?
    @State private var movePreview: TimelineMovePreview?

    private let labelWidth: CGFloat = 44
    private let rowHeight: CGFloat = 50
    private let rowSpacing: CGFloat = 7

    var body: some View {
        VStack(spacing: 0) {
            timelineHeader
            GeometryReader { proxy in
                let playheadX = labelWidth + (proxy.size.width - labelWidth) / 2

                VStack(spacing: 0) {
                    ruler(width: proxy.size.width, playheadX: playheadX)
                    if viewModel.project.clips.isEmpty {
                        emptyTimeline(playheadX: playheadX, height: max(60, proxy.size.height - 28))
                    } else {
                        timelineTracks(
                            playheadX: playheadX,
                            viewportHeight: max(60, proxy.size.height - 28)
                        )
                    }
                }
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
        let visualLayers = viewModel.project.clips
            .filter { $0.kind != .audio }
            .map(\.layer)
        let highestVisual = max(0, visualLayers.max() ?? 0)
        let visualTop = min(8, max(1, highestVisual + 1))
        let visuals = Array(stride(from: visualTop, through: 0, by: -1))

        let audioIndices = viewModel.project.clips
            .filter { $0.kind == .audio }
            .map { max(0, $0.layer - EditorViewModel.audioLayerBase) }
        let highestAudio = max(0, audioIndices.max() ?? 0)
        let audioTop = min(7, audioIndices.isEmpty ? 0 : highestAudio + 1)
        let audios = Array(0...audioTop).map { EditorViewModel.audioLayerBase + $0 }

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

            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.white.opacity(0.42))
            Slider(value: $zoom, in: 38...150)
                .frame(maxWidth: 110)
                .tint(.white)
                .accessibilityLabel("Масштаб таймлайна")
            Image(systemName: "plus.magnifyingglass")
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
                    .allowsHitTesting(false)
            }

            fixedPlayhead(x: playheadX, height: viewportHeight)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(timelineNavigationGesture(viewportHeight: viewportHeight))
        .clipped()
    }

    private func track(_ layer: Int, playheadX: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(movePreview?.placement.layer == layer ? Color.red.opacity(0.055) : Color.white.opacity(0.025))
                .padding(.leading, labelWidth)
                .allowsHitTesting(false)

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

            ForEach(viewModel.project.clips.filter { $0.layer == layer }) { clip in
                TimelineClipView(
                    clip: clip,
                    selected: viewModel.selectedClipID == clip.id,
                    zoom: zoom,
                    rowStride: rowHeight + rowSpacing,
                    laneOrder: trackNumbers,
                    snappingEnabled: snappingEnabled,
                    movingClipID: $movingClipID,
                    movePreview: Binding(
                        get: { movePreview },
                        set: { movePreview = $0 }
                    ),
                    mediaURL: viewModel.mediaURL(for: clip),
                    viewModel: viewModel
                )
                .frame(width: max(34, CGFloat(clip.playbackDuration) * zoom), height: rowHeight - 8)
                .offset(
                    x: playheadX + CGFloat(clip.timelineStart - viewModel.playhead) * zoom,
                    y: 4
                )
                .onTapGesture {
                    guard movingClipID == nil else { return }
                    viewModel.select(clip)
                }
                .accessibilityLabel("\(clip.fileName), \(clip.playbackDuration.formattedDuration)")
                .zIndex(movingClipID == clip.id ? 1000 : 30)
            }

            Rectangle()
                .fill(Color(red: 0.072, green: 0.072, blue: 0.082))
                .frame(width: labelWidth)
                .overlay(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(layerName(layer))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))
                        Image(systemName: layer >= EditorViewModel.audioLayerBase ? "speaker.wave.1.fill" : "film.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                    .padding(.leading, 6)
                }
                .zIndex(2000)
        }
        .frame(height: rowHeight)
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
                guard movingClipID == nil else { return }

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

    private var rulerPanGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard movingClipID == nil else { return }
                if panOriginTime == nil { panOriginTime = viewModel.playhead }
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
        let candidates = viewModel.project.clips.flatMap { [$0.timelineStart, $0.timelineEnd] }
        if let nearest = candidates.min(by: { abs($0 - time) < abs($1 - time) }),
           abs(nearest - time) <= 0.08 {
            return nearest
        }
        return time
    }

    private var tickStep: Double {
        if zoom >= 120 { return 0.5 }
        if zoom >= 70 { return 1 }
        return 2
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
    let clip: MediaClip
    let selected: Bool
    let zoom: CGFloat
    let rowStride: CGFloat
    let laneOrder: [Int]
    let snappingEnabled: Bool
    @Binding var movingClipID: UUID?
    @Binding var movePreview: TimelineView.TimelineMovePreview?
    let mediaURL: URL
    @ObservedObject var viewModel: EditorViewModel

    @State private var leftDragOrigin: MediaClip?
    @State private var rightDragOrigin: MediaClip?
    @State private var isMoving = false
    @State private var moveTranslation: CGSize = .zero
    @State private var lastSnapGuide: Double?
    @GestureState private var moveGestureActive = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            clipVisual

            if clip.kind != .audio {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }

            HStack(spacing: 4) {
                Image(systemName: clip.kind.icon)
                Text(clip.fileName)
                    .lineLimit(1)
                if clip.speedPoints != SpeedPoint.linear {
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
                    isMoving ? Color.red : (selected ? Color.white : Color.white.opacity(0.14)),
                    lineWidth: isMoving ? 2 : (selected ? 2 : 1)
                )
        }
        .overlay(alignment: .leading) {
            if selected && !isMoving {
                trimHandle(edge: .left)
                    .offset(x: -7)
            }
        }
        .overlay(alignment: .trailing) {
            if selected && !isMoving {
                trimHandle(edge: .right)
                    .offset(x: 7)
            }
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
        .zIndex(isMoving ? 1000 : 0)
        .transaction { transaction in
            transaction.animation = nil
        }
        .simultaneousGesture(clipMoveGesture)
        .onChange(of: moveGestureActive) { _, active in
            if !active, isMoving {
                resetMoveState()
            }
        }
        .onChange(of: movingClipID) { _, id in
            if id != clip.id, isMoving {
                isMoving = false
                moveTranslation = .zero
                lastSnapGuide = nil
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
            switch clip.kind {
            case .video:
                TimelineThumbnailStrip(
                    clip: clip,
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
        Rectangle()
            .fill(handleColor)
            .frame(width: 14, height: 36)
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: 2, height: 18)
            }
            .contentShape(Rectangle().inset(by: -10))
            .highPriorityGesture(trimGesture(edge: edge))
            .accessibilityLabel(edge == .left ? "Обрезать начало клипа" : "Обрезать конец клипа")
    }

    private var clipMoveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.40, maximumDistance: 12)
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
                var finalPlacement: ClipMovePlacement?
                if case .second(true, let dragValue) = value,
                   let dragValue {
                    finalPlacement = placement(for: dragValue.translation)
                }

                if let finalPlacement {
                    viewModel.commitClipMove(id: clip.id, placement: finalPlacement)
                }
                resetMoveState()
            }
    }

    private func activateMoveIfNeeded() {
        guard !isMoving else { return }
        isMoving = true
        movingClipID = clip.id
        viewModel.select(clip)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateMove(with rawTranslation: CGSize) {
        guard let placement = placement(for: rawTranslation) else { return }
        movePreview = TimelineView.TimelineMovePreview(clipID: clip.id, placement: placement)

        let snappedX = CGFloat(placement.timelineStart - clip.timelineStart) * zoom
        moveTranslation = CGSize(width: snappedX, height: rawTranslation.height)

        if placement.snapGuide != lastSnapGuide {
            if placement.snapGuide != nil {
                UISelectionFeedbackGenerator().selectionChanged()
            }
            lastSnapGuide = placement.snapGuide
        }
    }

    private func placement(for rawTranslation: CGSize) -> ClipMovePlacement? {
        let rawStart = clip.timelineStart + Double(rawTranslation.width / zoom)
        let targetLayer = moveTargetLayer(for: rawTranslation.height)
        return viewModel.previewClipMove(
            id: clip.id,
            proposedStart: rawStart,
            requestedLayer: targetLayer,
            snappingEnabled: snappingEnabled
        )
    }

    private func resetMoveState() {
        isMoving = false
        moveTranslation = .zero
        lastSnapGuide = nil
        if movingClipID == clip.id {
            movingClipID = nil
        }
        if movePreview?.clipID == clip.id {
            movePreview = nil
        }
    }

    private func moveTargetLayer(for verticalTranslation: CGFloat) -> Int {
        let validLanes = laneOrder.filter { layer in
            clip.kind == .audio
                ? layer >= EditorViewModel.audioLayerBase
                : layer < EditorViewModel.audioLayerBase
        }
        guard !validLanes.isEmpty else { return clip.layer }

        let sourceIndex = validLanes.firstIndex(of: clip.layer) ?? 0
        let deltaRows = Int((verticalTranslation / max(1, rowStride)).rounded())
        let targetIndex = min(max(0, sourceIndex + deltaRows), validLanes.count - 1)
        return validLanes[targetIndex]
    }

    private func trackName(_ layer: Int) -> String {
        if layer >= EditorViewModel.audioLayerBase {
            return "A\(layer - EditorViewModel.audioLayerBase + 1)"
        }
        return "V\(layer + 1)"
    }

    private func trimGesture(edge: TrimEdge) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch edge {
                case .left:
                    if leftDragOrigin == nil { leftDragOrigin = clip }
                    guard let origin = leftDragOrigin else { return }
                    previewLeftTrim(origin: origin, translation: value.translation.width)
                case .right:
                    if rightDragOrigin == nil { rightDragOrigin = clip }
                    guard let origin = rightDragOrigin else { return }
                    previewRightTrim(origin: origin, translation: value.translation.width)
                }
            }
            .onEnded { _ in
                leftDragOrigin = nil
                rightDragOrigin = nil
                viewModel.finishNonRippleTrim()
            }
    }

    private func previewLeftTrim(origin: MediaClip, translation: CGFloat) {
        guard origin.playbackDuration > 0.001 else { return }
        let timelineDelta = Double(translation / zoom)
        let sourcePerTimeline = origin.trimmedDuration / origin.playbackDuration
        let sourceDelta = timelineDelta * sourcePerTimeline
        var updated = origin
        updated.trimStart = min(max(0, origin.trimStart + sourceDelta), origin.trimEnd - 0.05)
        let durationDifference = origin.playbackDuration - updated.playbackDuration
        updated.timelineStart = max(0, origin.timelineStart + durationDifference)
        viewModel.previewNonRippleTrim(updated)
    }

    private func previewRightTrim(origin: MediaClip, translation: CGFloat) {
        guard origin.playbackDuration > 0.001 else { return }
        let timelineDelta = Double(translation / zoom)
        let sourcePerTimeline = origin.trimmedDuration / origin.playbackDuration
        let sourceDelta = timelineDelta * sourcePerTimeline
        var updated = origin
        updated.trimEnd = max(origin.trimStart + 0.05, min(origin.sourceDuration, origin.trimEnd + sourceDelta))
        viewModel.previewNonRippleTrim(updated)
    }

    private var handleColor: Color {
        switch clip.kind {
        case .video: Color.blue
        case .image: Color.teal
        case .audio: Color.green
        }
    }

    private var clipColor: Color {
        switch clip.kind {
        case .video: Color(red: 0.16, green: 0.18, blue: 0.22)
        case .image: Color(red: 0.15, green: 0.32, blue: 0.34)
        case .audio: Color(red: 0.12, green: 0.34, blue: 0.22)
        }
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
                        .frame(width: max(1, width / CGFloat(images.count)), height: height)
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
                let phase = sin(index * 0.72) * 0.45 + cos(index * 0.31) * 0.25
                let amplitude = max(3, abs(phase) * size.height * 0.40)
                var path = Path()
                path.move(to: CGPoint(x: x, y: centerY - amplitude))
                path.addLine(to: CGPoint(x: x, y: centerY + amplitude))
                context.stroke(path, with: .color(.white.opacity(0.58)), lineWidth: 1.2)
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
                action("Разделить", icon: "scissors") { viewModel.splitSelected(at: viewModel.playhead) }
                    .disabled(viewModel.selectedClip == nil)
                action("Скорость", icon: "gauge.with.dots.needle.67percent") { viewModel.openSpeedRamp() }
                    .disabled(viewModel.selectedClip == nil)
                action("Эффекты", icon: "slider.horizontal.3") { viewModel.openClipTools() }
                    .disabled(viewModel.selectedClip == nil)
                action("Копия", icon: "plus.square.on.square") { viewModel.duplicateSelected() }
                    .disabled(viewModel.selectedClip == nil)
                action(viewModel.selectedClip?.isMuted == true ? "Включить звук" : "Без звука", icon: "speaker.slash") { viewModel.toggleMuteSelected() }
                    .disabled(viewModel.selectedClip == nil)
                action("Удалить", icon: "trash", role: .destructive) { viewModel.deleteSelected() }
                    .disabled(viewModel.selectedClip == nil)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 70)
        .background(.ultraThinMaterial)
    }

    private func action(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }
            .frame(minWidth: 62, minHeight: 48)
        }
        .buttonStyle(.plain)
    }
}
