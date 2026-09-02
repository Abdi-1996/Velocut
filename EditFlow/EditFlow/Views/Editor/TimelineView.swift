import SwiftUI

struct TimelineView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var zoom: CGFloat = 54

    private let labelWidth: CGFloat = 42

    var body: some View {
        VStack(spacing: 0) {
            timelineHeader
            ruler
            if viewModel.project.clips.isEmpty {
                ContentUnavailableView("Таймлайн пуст", systemImage: "timeline.selection", description: Text("Добавьте медиа, чтобы начать монтаж."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(trackNumbers, id: \.self) { layer in
                                track(layer)
                            }
                        }
                        playhead
                    }
                    .padding(.leading, labelWidth)
                    .padding(.vertical, 7)
                    .frame(minWidth: max(330, CGFloat(max(viewModel.project.duration, 5)) * zoom), alignment: .leading)
                }
                .scrollIndicators(.visible)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.58))
    }

    private var trackNumbers: [Int] {
        let values = Set(viewModel.project.clips.map(\.layer))
        return values.isEmpty ? [0] : values.sorted()
    }

    private var timelineHeader: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.playhead = max(0, viewModel.playhead - 1 / Double(viewModel.project.frameRate))
            } label: { Image(systemName: "backward.frame") }
                .accessibilityLabel("Предыдущий кадр")
            Text("\(viewModel.playhead.formattedDuration) / \(viewModel.project.duration.formattedDuration)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
            Slider(value: $zoom, in: 32...130)
                .frame(maxWidth: 130)
                .accessibilityLabel("Масштаб таймлайна")
            Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            Button {
                viewModel.playhead = min(viewModel.project.duration, viewModel.playhead + 1 / Double(viewModel.project.frameRate))
            } label: { Image(systemName: "forward.frame") }
                .accessibilityLabel("Следующий кадр")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(height: 42)
    }

    private var ruler: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let seconds = max(1, Int(ceil(Double(size.width / zoom))))
                for second in 0...seconds {
                    let x = CGFloat(second) * zoom
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 14))
                    path.addLine(to: CGPoint(x: x, y: 24))
                    context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                    context.draw(Text("\(second)s").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x + 9, y: 7))
                }
            }
            .offset(x: labelWidth)
        }
        .frame(height: 26)
    }

    private func track(_ layer: Int) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9)
                .fill(.white.opacity(0.035))
                .frame(height: 46)
            Text(layerName(layer))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: labelWidth - 8)
                .offset(x: -labelWidth + 4)
            ForEach(viewModel.project.clips.filter { $0.layer == layer }) { clip in
                ClipBlock(clip: clip, selected: viewModel.selectedClipID == clip.id)
                    .frame(width: max(30, CGFloat(clip.playbackDuration) * zoom), height: 40)
                    .offset(x: CGFloat(clip.timelineStart) * zoom)
                    .onTapGesture { viewModel.select(clip) }
                    .accessibilityLabel("\(clip.fileName), \(clip.playbackDuration.formattedDuration)")
            }
        }
        .frame(height: 46)
    }

    private var playhead: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: CGFloat(trackNumbers.count) * 53)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .offset(y: -5)
            }
            .offset(x: CGFloat(viewModel.playhead) * zoom)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewModel.playhead = min(max(0, Double(value.location.x / zoom)), viewModel.project.duration)
                    }
            )
    }

    private func layerName(_ layer: Int) -> String {
        layer == 2 ? "A1" : "V\(layer + 1)"
    }
}

private struct ClipBlock: View {
    let clip: MediaClip
    let selected: Bool

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
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(clipColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(selected ? .white : .clear, lineWidth: 2)
        }
    }

    private var clipColor: Color {
        switch clip.kind {
        case .video: .indigo.opacity(0.78)
        case .image: .cyan.opacity(0.72)
        case .audio: .green.opacity(0.68)
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
