import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit

enum MediaRenderError: LocalizedError {
    case invalidImage
    case cannotCreateWriter
    case cannotCreateBuffer
    case writerFailed(String)
    case effectExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Не удалось прочитать изображение."
        case .cannotCreateWriter: "Не удалось подготовить рендер фотографии."
        case .cannotCreateBuffer: "Не удалось создать видеокадр из фотографии."
        case .writerFailed(let message): "Ошибка рендера фотографии: \(message)"
        case .effectExportFailed(let message): "Ошибка обработки эффекта: \(message)"
        }
    }
}

actor MediaRenderService {
    private let ciContext = CIContext(options: [.cacheIntermediates: true])

    func prepareAsset(
        for clip: MediaClip,
        projectDirectory: URL,
        renderSize: CGSize,
        frameRate: Int,
        cacheDirectory: URL
    ) async throws -> URL {
        let sourceURL = projectDirectory.appendingPathComponent(clip.relativePath)
        switch clip.kind {
        case .audio:
            return sourceURL
        case .image:
            return try await renderStillImage(
                sourceURL: sourceURL,
                duration: clip.trimmedDuration,
                effects: clip.resolvedEffects,
                size: renderSize,
                frameRate: frameRate,
                outputURL: cacheDirectory.appendingPathComponent("still-\(clip.id).mov")
            )
        case .video:
            guard !clip.resolvedEffects.isNeutral else { return sourceURL }
            return try await renderEffects(
                sourceURL: sourceURL,
                effects: clip.resolvedEffects,
                outputURL: cacheDirectory.appendingPathComponent("effects-\(clip.id).mov")
            )
        }
    }

    private func renderEffects(sourceURL: URL, effects: EffectSettings, outputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoComposition = AVVideoComposition(asset: asset) { [ciContext] request in
            let output = Self.apply(effects, to: request.sourceImage.clampedToExtent())
                .cropped(to: request.sourceImage.extent)
            request.finish(with: output, context: ciContext)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaRenderError.effectExportFailed("настройки не поддерживаются")
        }
        session.outputURL = outputURL
        session.outputFileType = .mov
        session.videoComposition = videoComposition
        try await run(session)
        return outputURL
    }

    private func renderStillImage(
        sourceURL: URL,
        duration: Double,
        effects: EffectSettings,
        size: CGSize,
        frameRate: Int,
        outputURL: URL
    ) async throws -> URL {
        guard let image = UIImage(contentsOfFile: sourceURL.path), let sourceCGImage = image.cgImage else {
            throw MediaRenderError.invalidImage
        }
        let source = CIImage(cgImage: sourceCGImage)
        let filtered = Self.apply(effects, to: source)
        guard let filteredCGImage = ciContext.createCGImage(filtered, from: filtered.extent) else {
            throw MediaRenderError.invalidImage
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoExpectedSourceFrameRateKey: frameRate
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw MediaRenderError.cannotCreateWriter }
        writer.add(input)
        guard writer.startWriting() else {
            throw MediaRenderError.writerFailed(writer.error?.localizedDescription ?? "неизвестная ошибка")
        }
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool,
              let buffer = makePixelBuffer(from: filteredCGImage, size: size, pool: pool) else {
            throw MediaRenderError.cannotCreateBuffer
        }
        let fps = max(1, frameRate)
        let frameCount = max(2, Int(ceil(duration * Double(fps))))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw MediaRenderError.writerFailed(writer.error?.localizedDescription ?? "кадр не записан")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw MediaRenderError.writerFailed(writer.error?.localizedDescription ?? "неизвестная ошибка")
        }
        return outputURL
    }

    private func makePixelBuffer(from image: CGImage, size: CGSize, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let destination = CGRect(
            x: (size.width - imageSize.width * scale) / 2,
            y: (size.height - imageSize.height * scale) / 2,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        context.draw(image, in: destination)
        return buffer
    }

    nonisolated private static func apply(_ effects: EffectSettings, to source: CIImage) -> CIImage {
        var image = source
        let color = CIFilter.colorControls()
        color.inputImage = image
        color.brightness = Float(effects.brightness)
        color.contrast = Float(effects.contrast)
        color.saturation = Float(effects.saturation)
        image = color.outputImage ?? image

        if abs(effects.temperature) > 0.001 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = image
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: CGFloat(6500 + effects.temperature * 2500), y: 0)
            image = temperature.outputImage ?? image
        }
        if effects.vignette > 0.001 {
            let vignette = CIFilter.vignette()
            vignette.inputImage = image
            vignette.intensity = Float(effects.vignette)
            vignette.radius = Float(max(source.extent.width, source.extent.height) * 0.45)
            image = vignette.outputImage ?? image
        }
        if effects.sharpen > 0.001 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = image
            sharpen.sharpness = Float(effects.sharpen)
            image = sharpen.outputImage ?? image
        }
        return image
    }

    private func run(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed: continuation.resume(returning: ())
                case .failed: continuation.resume(throwing: MediaRenderError.effectExportFailed(session.error?.localizedDescription ?? "неизвестная ошибка"))
                case .cancelled: continuation.resume(throwing: VideoExportError.cancelled)
                default: continuation.resume(throwing: MediaRenderError.effectExportFailed("экспорт завершился неожиданно"))
                }
            }
        }
    }
}
