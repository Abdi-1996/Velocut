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
}

