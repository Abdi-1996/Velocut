import SwiftUI

struct SpeedRampSheet: View {
    @ObservedObject var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: SpeedPreset = .linear

    var body: some View {
        NavigationStack {
            Group {
                if let clip = viewModel.selectedClip {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            presetPicker
                            SpeedCurveView(points: clip.speedPoints)
                                .frame(height: 250)
                                .padding()
                                .glassCard()

                            Text("Точки скорости")
                                .font(.headline)
                            ForEach(clip.speedPoints) { point in
                                SpeedPointEditor(point: point) { updated in
                                    viewModel.updateSpeedPoint(updated)
                                }
                            }
                            Text("Скорость между соседними точками усредняется. При экспорте каждый участок реально растягивается или ускоряется через AVFoundation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView("Клип не выбран", systemImage: "gauge")
                }
            }
            .navigationTitle("Speed Ramp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Пресеты").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(SpeedPreset.allCases) { preset in
                        Button(preset.rawValue) {
                            selectedPreset = preset
                            viewModel.applySpeedPreset(preset)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(selectedPreset == preset ? .blue : .gray.opacity(0.4))
                    }
                }
            }
        }
    }
}

private struct SpeedPointEditor: View {
    let point: SpeedPoint
    let update: (SpeedPoint) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Позиция \(Int(point.position * 100))%")
                Spacer()
                Text("\(point.rate, specifier: "%.2f")×")
                    .monospacedDigit()
                    .foregroundStyle(.blue)
            }
            Slider(value: Binding(
                get: { point.rate },
                set: { value in
                    var updated = point
                    updated.rate = value
                    update(updated)
                }
            ), in: 0.05...8, step: 0.05)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SpeedCurveView: View {
    let points: [SpeedPoint]

    var body: some View {
        GeometryReader { proxy in
            let ordered = points.sorted { $0.position < $1.position }
            ZStack {
                Path { path in
                    for line in 0...4 {
                        let y = proxy.size.height * CGFloat(line) / 4
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(.secondary.opacity(0.18), lineWidth: 1)

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
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(ordered) { point in
                    Circle()
                        .fill(.white)
                        .stroke(Color.blue, lineWidth: 3)
                        .frame(width: 15, height: 15)
                        .position(x: proxy.size.width * point.position, y: proxy.size.height * (1 - min(point.rate, 8) / 8))
                }
            }
        }
        .accessibilityLabel("График изменения скорости")
    }
}

