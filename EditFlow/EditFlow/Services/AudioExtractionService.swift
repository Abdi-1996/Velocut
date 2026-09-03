import AVFoundation
import Foundation

enum AudioExtractionError: LocalizedError {
    case noAudioTrack
    case cannotCreateExporter
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "В выбранном видео нет звуковой дорожки."
        case .cannotCreateExporter:
            return "Не удалось подготовить извлечение аудио."
        case .exportFailed(let message):
            return "Не удалось извлечь аудио: \(message)"
        }
    }
}

actor AudioExtractionService {
    static let shared = AudioExtractionService()

    func extractAudio(from sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw AudioExtractionError.noAudioTrack
        }

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioExtractionError.cannotCreateExporter
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditFlowExtractedAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = baseName.isEmpty ? "audio" : baseName
        let outputURL = directory
            .appendingPathComponent("\(UUID().uuidString)-\(safeBaseName)")
            .appendingPathExtension("m4a")

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        switch exporter.status {
        case .completed:
            return outputURL
        case .failed, .cancelled:
            throw AudioExtractionError.exportFailed(
                exporter.error?.localizedDescription ?? "неизвестная ошибка"
            )
        default:
            throw AudioExtractionError.exportFailed("экспорт не завершён")
        }
    }
}
