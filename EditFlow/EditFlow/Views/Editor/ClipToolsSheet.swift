import SwiftUI

struct ClipToolsSheet: View {
    @ObservedObject var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var section: ToolSection = .effects

    private enum ToolSection: String, CaseIterable, Identifiable {
        case effects = "Эффекты"
        case transition = "Переход"
        case animation = "Keyframes"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Инструмент", selection: $section) {
                    ForEach(ToolSection.allCases) { item in Text(item.rawValue).tag(item) }
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch section {
                    case .effects: effectsForm
                    case .transition: transitionForm
                    case .animation: keyframeForm
                    }
                }
            }
            .navigationTitle(viewModel.selectedClip?.fileName ?? "Настройки клипа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var effectsForm: some View {
        Form {
            Section("Цвет") {
                EffectSlider(title: "Яркость", value: effectBinding(\.brightness), range: -1...1)
                EffectSlider(title: "Контраст", value: effectBinding(\.contrast), range: 0.25...2)
                EffectSlider(title: "Насыщенность", value: effectBinding(\.saturation), range: 0...2)
                EffectSlider(title: "Температура", value: effectBinding(\.temperature), range: -1...1)
            }
            Section("Детали") {
                EffectSlider(title: "Виньетка", value: effectBinding(\.vignette), range: 0...2)
                EffectSlider(title: "Резкость", value: effectBinding(\.sharpen), range: 0...2)
            }
            Section {
                Button("Сбросить эффекты", role: .destructive) { viewModel.resetEffects() }
            } footer: {
                Text("Настройки применяются к выбранному клипу или фотографии и входят в итоговый экспорт.")
            }
        }
    }

    private var transitionForm: some View {
        Form {
            Section("После выбранного клипа") {
                Picker("Тип", selection: Binding(
                    get: { viewModel.selectedClip?.resolvedTransition.style ?? .none },
                    set: { viewModel.updateTransition(style: $0) }
                )) {
                    ForEach(TransitionStyle.allCases) { style in Text(style.rawValue).tag(style) }
                }
                EffectSlider(title: "Длительность", value: Binding(
                    get: { viewModel.selectedClip?.resolvedTransition.duration ?? 0.35 },
                    set: { viewModel.updateTransition(duration: $0) }
                ), range: 0.1...1.5, suffix: "с")
            } footer: {
                Text("Растворение накладывает соседние клипы друг на друга. Затемнение сохраняет их последовательность.")
            }
        }
    }

    private var keyframeForm: some View {
        Form {
            ForEach(viewModel.selectedClip?.resolvedKeyframes ?? []) { frame in
                Section(frame.position < 0.5 ? "Начальный keyframe" : "Конечный keyframe") {
                    EffectSlider(title: "Позиция X", value: keyframeBinding(frame.id, \.positionX), range: -600...600)
                    EffectSlider(title: "Позиция Y", value: keyframeBinding(frame.id, \.positionY), range: -900...900)
                    EffectSlider(title: "Масштаб", value: keyframeBinding(frame.id, \.scale), range: 0.2...4)
                    EffectSlider(title: "Поворот", value: keyframeBinding(frame.id, \.rotation), range: -180...180, suffix: "°")
                }
            }
            Section {
                Button("Сбросить анимацию", role: .destructive) { viewModel.resetKeyframes() }
            } footer: {
                Text("Позиция, масштаб и поворот плавно интерполируются между началом и концом клипа.")
            }
        }
    }

    private func effectBinding(_ keyPath: WritableKeyPath<EffectSettings, Double>) -> Binding<Double> {
        Binding(
            get: { viewModel.selectedClip?.resolvedEffects[keyPath: keyPath] ?? EffectSettings()[keyPath: keyPath] },
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
                viewModel.selectedClip?.resolvedKeyframes.first(where: { $0.id == id })?.transform[keyPath: keyPath] ?? 0
            },
            set: { value in
                guard var frame = viewModel.selectedClip?.resolvedKeyframes.first(where: { $0.id == id }) else { return }
                frame.transform[keyPath: keyPath] = value
                viewModel.updateKeyframe(frame)
            }
        )
    }
}

private struct EffectSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value, specifier: "%.2f")\(suffix)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
        }
    }
}

