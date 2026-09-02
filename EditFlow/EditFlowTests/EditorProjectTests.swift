import XCTest
@testable import EditFlow

final class EditorProjectTests: XCTestCase {
    func testLinearSpeedKeepsDuration() {
        let clip = MediaClip(fileName: "clip.mov", relativePath: "Media/clip.mov", kind: .video, sourceDuration: 10, timelineStart: 0, trimEnd: 10)
        XCTAssertEqual(clip.playbackDuration, 10, accuracy: 0.001)
    }

    func testConstantDoubleSpeedHalvesDuration() {
        var clip = MediaClip(fileName: "clip.mov", relativePath: "Media/clip.mov", kind: .video, sourceDuration: 10, timelineStart: 0, trimEnd: 10)
        clip.speedPoints = [SpeedPoint(position: 0, rate: 2), SpeedPoint(position: 1, rate: 2)]
        XCTAssertEqual(clip.playbackDuration, 5, accuracy: 0.001)
    }

    func testProjectDurationUsesLatestClipEnd() {
        let first = MediaClip(fileName: "one.mov", relativePath: "Media/one.mov", kind: .video, sourceDuration: 4, timelineStart: 0, trimEnd: 4)
        let second = MediaClip(fileName: "two.mov", relativePath: "Media/two.mov", kind: .video, sourceDuration: 3, timelineStart: 4, trimEnd: 3)
        let project = EditProject(title: "Test", clips: [first, second])
        XCTAssertEqual(project.duration, 7, accuracy: 0.001)
    }

    func testNewEffectsAreNeutral() {
        XCTAssertTrue(EffectSettings().isNeutral)
        var effects = EffectSettings()
        effects.saturation = 1.2
        XCTAssertFalse(effects.isNeutral)
    }

    func testLegacyClipDecodesWithoutNewOptionalFields() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","fileName":"clip.mov","relativePath":"Media/clip.mov","kind":"video","sourceDuration":5,"timelineStart":0,"trimStart":0,"trimEnd":5,"layer":0,"isMuted":false,"transform":{"positionX":0,"positionY":0,"scale":1,"rotation":0,"opacity":1},"speedPoints":[{"id":"00000000-0000-0000-0000-000000000002","position":0,"rate":1},{"id":"00000000-0000-0000-0000-000000000003","position":1,"rate":1}]}"#
        let clip = try JSONDecoder().decode(MediaClip.self, from: Data(json.utf8))
        XCTAssertTrue(clip.resolvedEffects.isNeutral)
        XCTAssertEqual(clip.resolvedTransition.style, .none)
        XCTAssertEqual(clip.resolvedKeyframes.count, 2)
    }
}
