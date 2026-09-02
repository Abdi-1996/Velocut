import AVFoundation
import Foundation
import SwiftUI

enum ProjectAspectRatio: String, Codable, CaseIterable, Identifiable {
    case portrait = "9:16"
    case square = "1:1"
    case landscape = "16:9"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .portrait: CGSize(width: 1080, height: 1920)
        case .square: CGSize(width: 1080, height: 1080)
        case .landscape: CGSize(width: 1920, height: 1080)
        }
    }
}

enum MediaKind: String, Codable {
    case video
    case image
    case audio
}

struct SpeedPoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var position: Double
    var rate: Double

    static let linear = [
        SpeedPoint(position: 0, rate: 1),
        SpeedPoint(position: 1, rate: 1)
    ]
}

struct ClipTransform: Codable, Equatable {
    var positionX: Double = 0
    var positionY: Double = 0
    var scale: Double = 1
    var rotation: Double = 0
    var opacity: Double = 1
}

struct MediaClip: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileName: String
    var relativePath: String
    var kind: MediaKind
    var sourceDuration: Double
    var timelineStart: Double
    var trimStart: Double = 0
    var trimEnd: Double
    var layer: Int = 0
    var isMuted: Bool = false
    var transform = ClipTransform()
    var speedPoints = SpeedPoint.linear

    var trimmedDuration: Double { max(0.05, trimEnd - trimStart) }

    var playbackDuration: Double {
        guard speedPoints.count > 1 else { return trimmedDuration }
        let points = speedPoints.sorted { $0.position < $1.position }
        var duration = 0.0
        for index in 0..<(points.count - 1) {
            let left = points[index]
            let right = points[index + 1]
            let fraction = max(0, right.position - left.position)
            let rate = max(0.05, (left.rate + right.rate) / 2)
            duration += trimmedDuration * fraction / rate
        }
        return max(0.05, duration)
    }

    var timelineEnd: Double { timelineStart + playbackDuration }
}

struct EditProject: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var modifiedAt = Date()
    var aspectRatio: ProjectAspectRatio = .portrait
    var frameRate: Int = 30
    var clips: [MediaClip] = []

    var duration: Double {
        clips.map(\.timelineEnd).max() ?? 0
    }
}

enum SpeedPreset: String, CaseIterable, Identifiable {
    case linear = "Linear"
    case velocity = "Velocity"
    case impact = "Impact"
    case flash = "Flash"
    case hero = "Hero"

    var id: String { rawValue }

    var points: [SpeedPoint] {
        switch self {
        case .linear: SpeedPoint.linear
        case .velocity:
            [SpeedPoint(position: 0, rate: 0.55), SpeedPoint(position: 0.32, rate: 4.2), SpeedPoint(position: 0.58, rate: 0.35), SpeedPoint(position: 1, rate: 2.4)]
        case .impact:
            [SpeedPoint(position: 0, rate: 1), SpeedPoint(position: 0.42, rate: 1), SpeedPoint(position: 0.5, rate: 5), SpeedPoint(position: 0.64, rate: 0.25), SpeedPoint(position: 1, rate: 1)]
        case .flash:
            [SpeedPoint(position: 0, rate: 1), SpeedPoint(position: 0.45, rate: 3.5), SpeedPoint(position: 0.55, rate: 0.45), SpeedPoint(position: 1, rate: 1)]
        case .hero:
            [SpeedPoint(position: 0, rate: 0.4), SpeedPoint(position: 0.48, rate: 0.8), SpeedPoint(position: 0.72, rate: 2.8), SpeedPoint(position: 1, rate: 1)]
        }
    }
}

