import SwiftUI

struct InlineEditorSettings: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.08))
            Group {
                if viewModel.showingSpeedRamp {
                    InlineSpeedRampEditor(viewModel: viewModel)
                } else if viewModel.showingClipTools {
                    InlineClipToolsEditor(viewModel: viewModel)
                }
            }
        }
        .background(Color(red: 0.045, green: 0.045, blue: 0.052))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.closeInlineEditor()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.showingSpeedRamp ? "Speed Ramp" : viewModel.clipToolsSection.rawValue)
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.selectedClip?.fileName ?? "Клип не выбран")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if viewModel.showingSpeedRamp, let clip = viewModel.selectedClip {
                Text(clip.playbackDuration.formattedDuration)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }
}

private struct InlineSpeedRampEditor: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var selectedPreset: SpeedPreset = .linear

    var body: some View {
        if let clip = viewModel.selectedClip {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    presetPicker

                    InlineSpeedCurveView(points: clip.speedPoints)
                        .frame(height: 116)
                        .padding(10)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    ForEach(clip.speedPoints) { point in
                        HStack(spacing: 10) {
                            Text("\(Int(point.position * 100))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { point.rate },
                                    set: { value in
                                        var updated = point
                                        updated.rate = value
                                        viewModel.updateSpeedPoint(updated)
                                    }
                                ),
                                in: 0.05...8,
                                step: 0.05
                            )
                            .tint(.blue)

                            Text("\(point.rate, specifier: "%.2f")×")
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 48, alignment: .trailing)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(12)
            }
        } else {
            ContentUnavailableView("Клип не выбран", systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    private var presetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpeedPreset.allCases) { preset in
                    Button {
                        selectedPreset = preset
                        viewModel.applySpeedPreset(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(
                                selectedPreset == preset ? Color.blue : Color.white.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct InlineSpeedCurveView: View {
    let points: [SpeedPoint]

    var body: some View {
        GeometryReader { proxy in
            let ordered = points.sorted { $0.position < $1.position }
            ZStack {
                Path { path in
                    for line in 0...3 {
                        let y = proxy.size.height * CGFloat(line) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(.white.opacity(0.08), lineWidth: 1)

                Path { path in
                    for (index, point) in ordered.enumerated() {
                        let coordinate = CGPoint(
                            x: proxy.size.width * point.position,
                            y: proxy.size.height * (1 - min(point.rate, 8) / 8)
                        )
                        if index == 0 { path.move(to: coordinate) }
                        else { path.addLine(to: coordinate) }
                    }
                }
                .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(ordered) { point in
                    Circle()
                        .fill(.white)
                        .stroke(.blue, lineWidth: 2)
                        .frame(width: 11, height: 11)
                        .position(
                            x: proxy.size.width * point.position,
                            y: proxy.size.height * (1 - min(point.rate, 8) / 8)
                        )
                }
            }
        }
    }
}

private struct InlineClipToolsEditor: View {
    @ObservedObject var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Инструмент", selection: $viewModel.clipToolsSection) {
                ForEach(ClipToolsSection.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ScrollView {
                switch viewModel.clipToolsSection {
                case .effects:
                    effectsControls
                case .transition:
                    transitionControls
                case .animation:
                    keyframeControls
                }
            }
        }
    }

    private var effectsControls: some View {
        VStack(spacing: 12) {
            InlineValueSlider(title: "Яркость", value: effectBinding(\.brightness), range: -1...1)
            InlineValueSlider(title: "Контраст", value: effectBinding(\.contrast), range: 0.25...2)
            InlineValueSlider(title: "Насыщенность", value: effectBinding(\.saturation), range: 0...2)
            InlineValueSlider(title: "Температура", value: effectBinding(\.temperature), range: -1...1)
            InlineValueSlider(title: "Виньетка", value: effectBinding(\.vignette), range: 0...2)
            InlineValueSlider(title: "Резкость", value: effectBinding(\.sharpen), range: 0...2)
            Button("Сбросить эффекты", role: .destructive) { viewModel.resetEffects() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private var transitionControls: some View {
        VStack(spacing: 14) {
            Picker(
                "Тип перехода",
                selection: Binding(
                    get: { viewModel.selectedClip?.resolvedTransition.style ?? .none },
                    set: { viewModel.updateTransition(style: $0) }
                )
            ) {
                ForEach(TransitionStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            InlineValueSlider(
                title: "Длительность",
                value: Binding(
                    get: { viewModel.selectedClip?.resolvedTransition.duration ?? 0.35 },
                    set: { viewModel.updateTransition(duration: $0) }
                ),
                range: 0.1...1.5,
                suffix: "с"
            )
        }
        .padding(12)
    }

    private var keyframeControls: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.selectedClip?.resolvedKeyframes ?? []) { frame in
                VStack(alignment: .leading, spacing: 10) {
                    Text(frame.position < 0.5 ? "Начальный keyframe" : "Конечный keyframe")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    InlineValueSlider(title: "X", value: keyframeBinding(frame.id, \.positionX), range: -600...600)
                    InlineValueSlider(title: "Y", value: keyframeBinding(frame.id, \.positionY), range: -900...900)
                    InlineValueSlider(title: "Масштаб", value: keyframeBinding(frame.id, \.scale), range: 0.2...4)
                    InlineValueSlider(title: "Поворот", value: keyframeBinding(frame.id, \.rotation), range: -180...180, suffix: "°")
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Button("Сбросить анимацию", role: .destructive) { viewModel.resetKeyframes() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
    }

    private func effectBinding(_ keyPath: WritableKeyPath<EffectSettings, Double>) -> Binding<Double> {
        Binding(
            get: {
                viewModel.selectedClip?.resolvedEffects[keyPath: keyPath]
                    ?? EffectSettings()[keyPath: keyPath]
            },
            set: { value in
                var effects = viewModel.selectedClip?.resolvedEffects ?? EffectSettings()
                effects[keyPath: keyPath] = value
                viewModel.updateEffects(effects)
            }
        )
    }

    private func keyframeBinding(_ id: UUID, _ keyPath: WritableKeyPath<ClipTransform, Double>) -> Binding<Double> {
        Binding(
            get: {
                viewModel.selectedClip?.resolvedKeyframes
                    .first(where: { $0.id == id })?
                    .transform[keyPath: keyPath] ?? 0
            },
            set: { value in
                guard var frame = viewModel.selectedClip?.resolvedKeyframes.first(where: { $0.id == id }) else { return }
                frame.transform[keyPath: keyPath] = value
                viewModel.updateKeyframe(frame)
            }
        )
    }
}

private struct InlineValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 86, alignment: .leading)
            Slider(value: $value, in: range)
            Text("\(value, specifier: "%.2f")\(suffix)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
    }
}
