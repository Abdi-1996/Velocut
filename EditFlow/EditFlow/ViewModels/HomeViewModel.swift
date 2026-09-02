import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var showingNewProject = false
    @Published var newProjectTitle = "Новый эдит"
    @Published var selectedRatio: ProjectAspectRatio = .portrait

    func create(in store: ProjectStore) -> EditProject {
        let cleanTitle = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = store.createProject(title: cleanTitle.isEmpty ? "Новый эдит" : cleanTitle, aspectRatio: selectedRatio)
        newProjectTitle = "Новый эдит"
        selectedRatio = .portrait
        showingNewProject = false
        return project
    }
}

