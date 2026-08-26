import SwiftUI
import AVFoundation
import Accelerate

struct VeloCutBeatMarker: Identifiable, Equatable, Sendable {
    let id: UUID
    let time: Double
    let strength: Double
    let isStrong: Bool

    init(id: UUID = UUID(), time: Double, strength: Double, isStrong: Bool) {
        self.id = id
        self.time = time
        self.strength = strength
        self.isStrong = isStrong
    }
}

struct VeloCutBeatResult: Sendable {
    let bpm: Double
    let markers: [VeloCutBeatMarker]
}

enum VeloCutAudioTools {
    static func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "VeloCut.Audio", code: 101, userInfo: [NSLocalizedDescriptionKey: "В выбранном видео нет аудиодорожки"])
        }

        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw NSError(domain: "VeloCut.Audio", code: 102, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать аудиодорожку"])
        }

        let duration = try await asset.load(.duration)
        try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceAudio, at: .zero)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("VeloCut-Extracted-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: output)

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "VeloCut.Audio", code: 103, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать экспорт аудио"])
        }
        session.outputURL = output
        session.outputFileType = .m4a
        session.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw session.error ?? NSError(domain: "VeloCut.Audio", code: 104, userInfo: [NSLocalizedDescriptionKey: "Извлечение аудио не завершено"])
        }
        return output
    }

    static func detectBeats(in audioURL: URL, sensitivity: Double) async throws -> VeloCutBeatResult {
        try await Task.detached(priority: .userInitiated) {
            try detectBeatsSync(in: audioURL, sensitivity: sensitivity)
        }.value
    }

    private static func detectBeatsSync(in audioURL: URL, sensitivity: Double) throws -> VeloCutBeatResult {
        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        guard sampleRate > 0, channelCount > 0 else {
            throw NSError(domain: "VeloCut.Beat", code: 201, userInfo: [NSLocalizedDescriptionKey: "Неподдерживаемый формат аудио"])
        }

        let windowFrames = 1024
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(windowFrames)) else {
            throw NSError(domain: "VeloCut.Beat", code: 202, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать PCM-буфер"])
        }

        var envelope: [Float] = []
        envelope.reserveCapacity(max(1, Int(file.length) / windowFrames + 1))

        while file.framePosition < file.length {
            let remaining = file.length - file.framePosition
            let count = AVAudioFrameCount(min(Int64(windowFrames), remaining))
            try file.read(into: buffer, frameCount: count)
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { break }
            guard let channels = buffer.floatChannelData else {
                throw NSError(domain: "VeloCut.Beat", code: 203, userInfo: [NSLocalizedDescriptionKey: "Beat Detector требует PCM Float32"])
            }

            var energy: Float = 0
            for channel in 0..<channelCount {
                var meanMagnitude: Float = 0
                vDSP_meamgv(channels[channel], 1, &meanMagnitude, vDSP_Length(frames))
                energy += meanMagnitude
            }
            envelope.append(energy / Float(channelCount))
        }

        guard envelope.count > 8 else {
            throw NSError(domain: "VeloCut.Beat", code: 204, userInfo: [NSLocalizedDescriptionKey: "Аудио слишком короткое для анализа"])
        }

        var flux = [Float](repeating: 0, count: envelope.count)
        for i in 1..<envelope.count {
            flux[i] = max(0, envelope[i] - envelope[i - 1])
        }

        let envelopeRate = sampleRate / Double(windowFrames)
        let clampedSensitivity = min(max(sensitivity, 0.05), 1.0)
        let thresholdMultiplier = Float(2.45 - clampedSensitivity * 1.25)
        let localRadius = max(3, Int(envelopeRate * 0.18))
        let minimumPeakDistance = max(2, Int(envelopeRate * 0.16))

        var candidates: [(index: Int, time: Double, value: Float)] = []
        var lastPeak = -minimumPeakDistance
        if flux.count > 2 {
            for i in 1..<(flux.count - 1) {
                let lower = max(0, i - localRadius)
                let upper = min(flux.count, i + localRadius + 1)
                var localSum: Float = 0
                for j in lower..<upper { localSum += flux[j] }
                let localMean = localSum / Float(max(1, upper - lower))
                let threshold = max(0.00001, localMean * thresholdMultiplier)
                guard flux[i] >= threshold, flux[i] >= flux[i - 1], flux[i] >= flux[i + 1] else { continue }
                if i - lastPeak < minimumPeakDistance {
                    if let last = candidates.last, flux[i] > last.value {
                        candidates[candidates.count - 1] = (i, Double(i) / envelopeRate, flux[i])
                        lastPeak = i
                    }
                    continue
                }
                candidates.append((i, Double(i) / envelopeRate, flux[i]))
                lastPeak = i
            }
        }

        let lagMin = max(1, Int((60.0 / 200.0) * envelopeRate))
        let lagMax = min(flux.count / 2, max(lagMin + 1, Int((60.0 / 60.0) * envelopeRate)))
        var bestLag = 0
        var bestScore = -Double.infinity
        if lagMax >= lagMin {
            for lag in lagMin...lagMax {
                var score = 0.0
                var count = 0
                for i in lag..<flux.count {
                    score += Double(flux[i] * flux[i - lag])
                    count += 1
                }
                if count > 0 { score /= Double(count) }
                if score > bestScore {
                    bestScore = score
                    bestLag = lag
                }
            }
        }

        var bpm = bestLag > 0 ? 60.0 * envelopeRate / Double(bestLag) : 0
        while bpm > 0 && bpm < 70 { bpm *= 2 }
        while bpm > 190 { bpm /= 2 }

        if !bpm.isFinite || bpm <= 0 {
            let intervals = zip(candidates.dropFirst(), candidates).map { $0.0.time - $0.1.time }.filter { $0 > 0.2 && $0 < 1.2 }.sorted()
            if !intervals.isEmpty {
                let median = intervals[intervals.count / 2]
                bpm = 60.0 / median
                while bpm < 70 { bpm *= 2 }
                while bpm > 190 { bpm /= 2 }
            }
        }

        guard bpm.isFinite, bpm >= 40, bpm <= 240 else {
            throw NSError(domain: "VeloCut.Beat", code: 205, userInfo: [NSLocalizedDescriptionKey: "Не удалось уверенно определить BPM"])
        }

        let duration = Double(file.length) / sampleRate
        let interval = 60.0 / bpm
        let maxFlux = max(candidates.map(\.value).max() ?? 0.00001, 0.00001)

        guard !candidates.isEmpty else {
            var markers: [VeloCutBeatMarker] = []
            var time = 0.0
            var index = 0
            while time <= duration {
                markers.append(VeloCutBeatMarker(time: time, strength: index % 4 == 0 ? 1 : 0.45, isStrong: index % 4 == 0))
                time += interval
                index += 1
            }
            return VeloCutBeatResult(bpm: bpm, markers: markers)
        }

        let anchor = candidates
            .filter { $0.time <= min(duration, 8.0) }
            .max(by: { $0.value < $1.value }) ?? candidates[0]
        var phase = anchor.time
        while phase - interval >= 0 { phase -= interval }

        var markers: [VeloCutBeatMarker] = []
        var gridTime = phase
        var gridIndex = 0
        let snapWindow = min(0.14, interval * 0.32)
        while gridTime <= duration + 0.001 {
            var chosenTime = gridTime
            var strength = 0.35
            if let nearest = candidates.min(by: { abs($0.time - gridTime) < abs($1.time - gridTime) }), abs(nearest.time - gridTime) <= snapWindow {
                chosenTime = nearest.time
                strength = min(1, max(0.15, Double(nearest.value / maxFlux)))
            }
            let strong = gridIndex % 4 == 0 || strength >= 0.88
            markers.append(VeloCutBeatMarker(time: chosenTime, strength: strength, isStrong: strong))
            gridTime += interval
            gridIndex += 1
        }

        return VeloCutBeatResult(bpm: bpm, markers: markers)
    }
}

struct BeatTimelineMarkersV49: View {
    let markers: [VeloCutBeatMarker]
    let projectTime: Double
    let pps: Double
    let center: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(markers) { marker in
                Rectangle()
                    .fill(Color.orange.opacity(marker.isStrong ? 0.82 : 0.42))
                    .frame(width: marker.isStrong ? 2 : 1, height: marker.isStrong ? height : 18)
                    .position(
                        x: center + CGFloat((marker.time - projectTime) * pps),
                        y: marker.isStrong ? height / 2 : 9
                    )
            }
        }
        .allowsHitTesting(false)
    }
}
