import Foundation

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [EditProject] = []
    @Published var lastError: String?

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    let rootDirectory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDirectory = base.appendingPathComponent("EditFlow", isDirectory: true)
        createDirectories()
        load()
    }

    @discardableResult
    func createProject(title: String = "Новый эдит", aspectRatio: ProjectAspectRatio = .portrait) -> EditProject {
        let project = EditProject(title: title, aspectRatio: aspectRatio)
        projects.insert(project, at: 0)
        createProjectDirectory(project.id)
        persist()
        return project
    }

    func update(_ project: EditProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project
        updated.modifiedAt = Date()
        projects[index] = updated
        projects.sort { $0.modifiedAt > $1.modifiedAt }
        persist()
    }

    func delete(_ project: EditProject) {
        projects.removeAll { $0.id == project.id }
        let directory = projectDirectory(project.id)
        try? fileManager.removeItem(at: directory)
        persist()
    }

    func duplicate(_ project: EditProject) -> EditProject {
        var copy = project
        copy.id = UUID()
        copy.title += " — копия"
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        let sourceDirectory = projectDirectory(project.id)
        let destinationDirectory = projectDirectory(copy.id)
        do {
            if fileManager.fileExists(atPath: sourceDirectory.path) {
                try fileManager.copyItem(at: sourceDirectory, to: destinationDirectory)
            } else {
                createProjectDirectory(copy.id)
            }
        } catch {
            lastError = "Не удалось скопировать медиа проекта: \(error.localizedDescription)"
            createProjectDirectory(copy.id)
        }
        projects.insert(copy, at: 0)
        persist()
        return copy
    }

    func projectDirectory(_ id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func mediaDirectory(_ id: UUID) -> URL {
        projectDirectory(id).appendingPathComponent("Media", isDirectory: true)
    }

    private var projectsFile: URL { rootDirectory.appendingPathComponent("projects.json") }

    private func createDirectories() {
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        } catch {
            lastError = "Не удалось создать хранилище: \(error.localizedDescription)"
        }
    }

    private func createProjectDirectory(_ id: UUID) {
        do {
            try fileManager.createDirectory(at: mediaDirectory(id), withIntermediateDirectories: true)
        } catch {
            lastError = "Не удалось создать папку проекта: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: projectsFile.path) else { return }
        do {
            projects = try decoder.decode([EditProject].self, from: Data(contentsOf: projectsFile))
        } catch {
            lastError = "Не удалось открыть проекты: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            let data = try encoder.encode(projects)
            try data.write(to: projectsFile, options: .atomic)
        } catch {
            lastError = "Не удалось сохранить проекты: \(error.localizedDescription)"
        }
    }
}
