import SwiftUI

struct ExportSheet: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var quality: ExportQuality = .high
    @State private var saveToPhotos = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Видео") {
                    Picker("Качество", selection: $quality) {
                        ForEach(ExportQuality.allCases) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    LabeledContent("Частота кадров", value: "\(viewModel.project.frameRate) fps")
                    LabeledContent("Формат проекта", value: viewModel.project.aspectRatio.rawValue)
                    LabeledContent("Длительность", value: viewModel.project.duration.formattedDuration)
                }
                Section("Сохранение") {
                    Toggle("Добавить в Фото", isOn: $saveToPhotos)
                    if let exportedURL = viewModel.exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("Поделиться последним экспортом", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                Section {
                    Button {
                        viewModel.export(quality: quality, saveToPhotos: saveToPhotos)
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isExporting {
                                ProgressView().padding(.trailing, 6)
                                Text("Экспорт…")
                            } else {
                                Label("Экспортировать видео", systemImage: "arrow.up.circle.fill")
                            }
                            Spacer()
                        }
                    }
                    .disabled(viewModel.isExporting)
                } footer: {
                    Text("Монтаж выполняется локально. Исходные файлы не загружаются на сервер.")
                }
            }
            .navigationTitle("Экспорт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}

