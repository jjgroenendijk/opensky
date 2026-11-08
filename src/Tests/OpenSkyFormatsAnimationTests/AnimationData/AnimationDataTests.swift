import OpenSkyFormatsAnimation
import OpenSkyTagsTesting
import simd
import Testing

@Suite("Animation data project and motion table text files", .tags(.parser))
struct AnimationDataTests {
    private static let project = [
        "1", "2", "Behaviors\\A.hkx", "Characters\\B.hkx", "1",
        "Seat_Enter", "7", "1", "0.25", "0.5", "2", "SoundPlay:0", "SitIdle:1.25", "",
        "Seat_Exit", "8", "1.5", "0", "0", "0", ""
    ].joined(separator: "\r\n")

    private static let motions = [
        "7", "2", "1", "2 0 50 0", "1", "2 0 0 0.7071068 0.7071068", "",
        "8", "1", "2", "0.5 -10 0 0", "1 -20 0 0", "0", "",
        "7", "9", "0", "0", ""
    ].joined(separator: "\r\n")

    @Test("a project lists its behavior files and its clips by generator name")
    func project() throws {
        let data = try AnimationDataProject(text: Self.project)
        #expect(data.behaviorFiles == ["Behaviors\\A.hkx", "Characters\\B.hkx"])
        let enter = try #require(data.clip(named: "seat_enter"))
        #expect(enter.motionIndex == 7)
        #expect(enter.cropStart == 0.25 && enter.cropEnd == 0.5)
        #expect(enter.triggers.map(\.name) == ["SoundPlay", "SitIdle"])
        #expect(enter.triggers.map(\.time) == [0, 1.25])
        #expect(data.clip(named: "Seat_Exit")?.playbackSpeed == 1.5)
    }

    @Test("a project without clip data has no clips")
    func projectWithoutClips() throws {
        let data = try AnimationDataProject(text: "1\n1\nBehaviors\\A.hkx\n0\n")
        #expect(data.clips.isEmpty)
    }

    @Test("a cut-off project throws with the line it stopped at")
    func truncatedProject() {
        #expect(throws: AnimationDataError.self) {
            try AnimationDataProject(text: "1\n2\nBehaviors\\A.hkx\n1\nSeat\n7\n")
        }
        #expect(throws: AnimationDataError.malformed(
            line: 2,
            expected: "the behavior file count"
        )) {
            try AnimationDataProject(text: "1\n999\n")
        }
    }

    @Test("motion keys interpolate from the clip start, and the first block wins")
    func motion() throws {
        let table = try AnimationMotionTable(text: Self.motions)
        let enter = try #require(table.motions[7])
        #expect(enter.duration == 2)
        #expect(simd_distance(enter.offset(at: 1), SIMD3(0, 25, 0)) < 1e-4)
        #expect(simd_distance(enter.offset(at: 5), SIMD3(0, 50, 0)) < 1e-4)
        #expect(abs(enter.yaw(at: 2) - .pi / 2) < 1e-4)
        #expect(abs(enter.yaw(at: 1) - .pi / 4) < 1e-4)
        let exit = try #require(table.motions[8])
        #expect(simd_distance(exit.offset(at: 0.75), SIMD3(-15, 0, 0)) < 1e-4)
        #expect(exit.yaw(at: 1) == 0)
    }

    @Test("a key line with the wrong number of values throws")
    func malformedKey() {
        #expect(throws: AnimationDataError.self) {
            try AnimationMotionTable(text: "1\n1\n1\n1 2 3\n0\n")
        }
    }
}
