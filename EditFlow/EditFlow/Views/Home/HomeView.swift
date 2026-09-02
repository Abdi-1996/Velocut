import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: ProjectStore
    @StateObject private var viewModel = HomeViewModel()
    @State private var path: [UUID] = []

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Ваши эдиты")
                        .font(.largeTitle.bold())

                    createCard

                    HStack {
                        Text("Недавние")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(store.projects.count)")
                            .foregroundStyle(.secondary)
                    }

                    if store.projects.isEmpty {
                        ContentUnavailableView(
                            "Проектов пока нет",
                            systemImage: "square.stack.3d.up",
                            description: Text("Создайте первый проект и добавьте свои клипы.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                        .glassCard()
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.projects) { project in
                                ProjectCard(project: project) {
                                    path.append(project.id)
                                }
                                .contextMenu {
                                    Button {
                                        let copy = store.duplicate(project)
                                        path.append(copy.id)
                                    } label: {
                                        Label("Создать копию", systemImage: "plus.square.on.square")
                                    }
                                    Button(role: .destructive) {
                                        store.delete(project)
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background {
                LinearGradient(colors: [.black, Color.blue.opacity(0.12), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .navigationTitle("EditFlow")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showingNewProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Новый проект")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let project = store.projects.first(where: { $0.id == id }) {
                    EditorView(viewModel: EditorViewModel(project: project, store: store))
                } else {
                    ContentUnavailableView("Проект не найден", systemImage: "exclamationmark.folder")
                }
            }
            .sheet(isPresented: $viewModel.showingNewProject) {
                NewProjectSheet(viewModel: viewModel) {
                    let project = viewModel.create(in: store)
                    path.append(project.id)
                }
                .presentationDetents([.medium])
            }
            .alert("EditFlow", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("OK", role: .cancel) { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
        }
        .tint(.blue)
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title2)
                .foregroundStyle(.blue)
            Text("Создайте новый проект")
                .font(.title2.weight(.semibold))
            Text("Импортируйте видео, фото и музыку. Монтаж и экспорт работают локально на устройстве.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                viewModel.showingNewProject = true
            } label: {
                Label("Новый проект", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .glassCard()
    }
}

private struct ProjectCard: View {
    let project: EditProject
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LinearGradient(colors: [.indigo.opacity(0.8), .pink.opacity(0.65), .orange.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(.black.opacity(0.3), in: Circle())
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                Text(project.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(project.aspectRatio.rawValue) · \(project.frameRate) fps · \(project.duration.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .glassCard()
    }
}

private struct NewProjectSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    let create: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Проект") {
                    TextField("Название", text: $viewModel.newProjectTitle)
                    Picker("Формат", selection: $viewModel.selectedRatio) {
                        ForEach(ProjectAspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Новый проект")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        create()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

extension Double {
    var formattedDuration: String {
        guard isFinite else { return "00:00" }
        let seconds = max(0, Int(self.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

