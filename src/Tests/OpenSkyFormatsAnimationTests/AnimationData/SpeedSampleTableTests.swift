import Foundation
import OpenSkyFormatsAnimation
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite("Speed sample table", .tags(.parser))
struct SpeedSampleTableTests {
    private static let walk: [(blend: Float, ground: Float)] = [
        (0, 8), (82.5, 82), (144, 102), (324.5, 306)
    ]

    private static func table() throws -> SpeedSampleTable {
        try SpeedSampleTable(data: SpeedSampleFixture.file(projects: [
            (name: "DefaultMaleData\\DefaultMale.spd", states: [
                SpeedSampleFixture.State(key: 0, directions: [
                    (key: 0, pairs: walk),
                    (key: 0.5, pairs: [(50, 100)])
                ])
            ]),
            (name: "HorseProjectData\\HorseProject.spd", states: [])
        ]))
    }

    @Test("each project is keyed by its file stem, the way a behaviour path names it")
    func keysProjectsByStem() throws {
        let table = try Self.table()
        #expect(Set(table.projects.keys) == ["defaultmale", "horseproject"])
        #expect(table.project(forBehaviorPath: "meshes\\actors\\character\\DefaultMale.hkx") != nil)
    }

    @Test("a goal between two ground speeds blends their blend speeds")
    func interpolatesBetweenPairs() throws {
        let project = try #require(Self.table().projects["defaultmale"])
        let value = try #require(project.blendSpeed(state: 0, direction: 0, goal: 92))
        #expect(abs(value - (82.5 + 0.5 * 61.5)) < 0.001)
        let low = try #require(project.blendSpeed(state: 0, direction: 0, goal: 4))
        #expect(abs(low - 0) < 0.001, "below the first pair, from (0, 0)")
    }

    @Test("past the table the goal passes through, and a missing state answers nil")
    func edges() throws {
        let project = try #require(Self.table().projects["defaultmale"])
        #expect(project.blendSpeed(state: 0, direction: 0, goal: 400) == 400)
        #expect(project.blendSpeed(state: 3, direction: 0, goal: 80) == nil)
    }

    @Test("the direction is the first key at or above the input, and wraps past the last")
    func directionCeiling() throws {
        let project = try #require(Self.table().projects["defaultmale"])
        #expect(project.blendSpeed(state: 0, direction: 0.25, goal: 100) == 50)
        #expect(project.blendSpeed(state: 0, direction: 0.75, goal: 82) == 82.5)
    }

    @Test("a wrong version or a truncated block throws")
    func malformed() {
        let wrong = SpeedSampleFixture.file(
            projects: [(name: "A.spd", states: [])], version: 2
        )
        #expect(throws: SpeedSampleError.unsupportedVersion(2)) {
            try SpeedSampleTable(data: wrong)
        }
        #expect(throws: (any Error).self) {
            try SpeedSampleTable(data: Data("1\r\nA.spd\r\n".utf8))
        }
    }
}
