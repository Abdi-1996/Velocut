import SwiftUI

struct TimelineView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var zoom: CGFloat = 78
    @State private var panOriginTime: Double?
    @State private var snappingEnabled = true

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
                        ContentUnavailableView(
                            "Таймлайн пуст",
                            systemImage: "timeline.selection",
                            description: Text("Добавьте медиа, чтобы начать монтаж.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(timelinePanGesture)

                            ScrollView(.vertical, showsIndicators: trackNumbers.count > 4) {
                                VStack(spacing: rowSpacing) {
                                    ForEach(trackNumbers, id: \.self) { layer in
                                        track(layer, playheadX: playheadX)
                                    }
                                }
                                .padding(.vertical, 8)
                            }

                            fixedPlayhead(x: playheadX)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
        .background(Color(red: 0.045, green: 0.045, blue: 0.052))
    }

    private var trackNumbers: [Int] {
        let values = Set(viewModel.project.clips.map(\.layer))
        return values.isEmpty ? [0] : values.sorted()
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
            let visibleRight = min(
                max(viewModel.project.duration, viewModel.playhead),
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
        .gesture(timelinePanGesture)
    }

    private func track(_ layer: Int, playheadX: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.025))
                .padding(.leading, labelWidth)
                .allowsHitTesting(false)

            ForEach(viewModel.project.clips.filter { $0.layer == layer }) { clip in
                TimelineClipView(
                    clip: clip,
                    selected: viewModel.selectedClipID == clip.id,
                    zoom: zoom,
                    viewModel: viewModel
                )
                .frame(width: max(34, CGFloat(clip.playbackDuration) * zoom), height: rowHeight - 8)
                .offset(
                    x: playheadX + CGFloat(clip.timelineStart - viewModel.playhead) * zoom,
                    y: 4
                )
                .onTapGesture { viewModel.select(clip) }
                .accessibilityLabel("\(clip.fileName), \(clip.playbackDuration.formattedDuration)")
            }

            Rectangle()
                .fill(Color(red: 0.072, green: 0.072, blue: 0.082))
                .frame(width: labelWidth)
                .overlay(alignment: .leading) {
                    HStack(spacing: 4) {
                        Text(layerName(layer))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.72))
                        Image(systemName: layer == 2 ? "speaker.wave.1.fill" : "film.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.34))
                    }
                    .padding(.leading, 6)
                }
        }
        .frame(height: rowHeight)
        .clipped()
    }

    private func fixedPlayhead(x: CGFloat) -> some View {
        let tracksHeight = CGFloat(trackNumbers.count) * rowHeight + CGFloat(max(0, trackNumbers.count - 1)) * rowSpacing + 16

        return VStack(spacing: 0) {
            Image(systemName: "triangle.fill")
                .font(.system(size: 11))
                .rotationEffect(.degrees(180))
                .foregroundStyle(Color.red)
                .offset(y: -1)
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: max(60, tracksHeight - 8))
        }
        .position(x: x, y: max(34, tracksHeight / 2))
    }

    private var timelinePanGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
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
        layer == 2 ? "A1" : "V\(layer + 1)"
    }
}

private struct TimelineClipView: View {
    let clip: MediaClip
    let selected: Bool
    let zoom: CGFloat
    @ObservedObject var viewModel: EditorViewModel

    @State private var leftDragOrigin: MediaClip?
    @State private var rightDragOrigin: MediaClip?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: clip.kind.icon)
            Text(clip.fileName)
                .lineLimit(1)
            if clip.speedPoints != SpeedPoint.linear {
                Image(systemName: "gauge.with.dots.needle.67percent")
            }
        }
        .font(.caption2)
        .padding(.horizontal, selected ? 14 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(clipColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(selected ? Color.white : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1)
        }
        .overlay(alignment: .leading) {
            if selected {
                trimHandle(edge: .left)
                    .offset(x: -7)
            }
        }
        .overlay(alignment: .trailing) {
            if selected {
                trimHandle(edge: .right)
                    .offset(x: 7)
            }
        }
    }

    private enum TrimEdge {
        case left
        case right
    }

    private func trimHandle(edge: TrimEdge) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
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
        case .video: Color(red: 0.28, green: 0.34, blue: 0.46)
        case .image: Color(red: 0.20, green: 0.42, blue: 0.44)
        case .audio: Color(red: 0.17, green: 0.40, blue: 0.28)
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
                action("Скорость", icon: "gauge.with.dots.needle.67percent") { viewModel.showingSpeedRamp = true }
                    .disabled(viewModel.selectedClip == nil)
                action("Эффекты", icon: "slider.horizontal.3") { viewModel.showingClipTools = true }
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
