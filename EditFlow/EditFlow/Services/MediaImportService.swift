import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct ImportedMedia {
    let fileName: String
    let relativePath: String
    let kind: MediaKind
    let duration: Double
}

enum MediaImportError: LocalizedError {
    case unsupportedType
    case inaccessibleFile

    var errorDescription: String? {
        switch self {
        case .unsupportedType: "Этот формат пока не поддерживается."
        case .inaccessibleFile: "Приложение не получило доступ к выбранному файлу."
        }
    }
}

actor MediaImportService {
    func importFiles(_ urls: [URL], into destination: URL) async throws -> [ImportedMedia] {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var imported: [ImportedMedia] = []
        for url in urls {
            imported.append(try await importFile(url, into: destination))
        }
        return imported
    }

    private func importFile(_ source: URL, into destination: URL) async throws -> ImportedMedia {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        guard accessed || FileManager.default.isReadableFile(atPath: source.path) else {
            throw MediaImportError.inaccessibleFile
        }

        let values = try source.resourceValues(forKeys: [.contentTypeKey])
        let type = values.contentType ?? UTType(filenameExtension: source.pathExtension)
        let kind: MediaKind
        if type?.conforms(to: .movie) == true { kind = .video }
        else if type?.conforms(to: .image) == true { kind = .image }
        else if type?.conforms(to: .audio) == true { kind = .audio }
        else { throw MediaImportError.unsupportedType }

        let safeName = "\(UUID().uuidString)-\(source.lastPathComponent)"
        let target = destination.appendingPathComponent(safeName)
        try FileManager.default.copyItem(at: source, to: target)

        let duration: Double
        if kind == .image {
            duration = 3
        } else {
            let asset = AVURLAsset(url: target)
            duration = try await asset.load(.duration).seconds
        }
        return ImportedMedia(fileName: source.lastPathComponent, relativePath: "Media/\(safeName)", kind: kind, duration: max(0.05, duration))
    }
}

