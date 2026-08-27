import SwiftUI

// v0.6 universal timeline foundation. Media/effects/transitions/animation can share one lane model.
enum UniversalItemKind: String, Codable, CaseIterable { case video, photo, audio, text, effect, transition, speedFX, animation }

struct UniversalTrack: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var colorHex: String = "#6C6C70"
    var bypassed = false
    var collapsed = false
    var order: Int
}

struct UniversalTimelineItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var trackID: UUID
    var kind: UniversalItemKind
    var name: String
    var start: Double
    var duration: Double
}

enum AnimationInterpolation: String, Codable, CaseIterable { case linear, smooth, sharp, hold }
struct AnimationKey: Identifiable, Codable, Equatable {
    var id = UUID()
    var time: Double
    var value: Double
    var interpolation: AnimationInterpolation = .smooth
}
struct AnimationParameterLane: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var keys: [AnimationKey] = []
}
struct AnimationClipV6: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = "Animation"
    var start: Double = 0
    var duration: Double = 1
    var parameterLanes: [AnimationParameterLane] = []
}
