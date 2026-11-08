// The install's speed file parses, and the human walk maps a body speed to the blend
// speed whose feet match it (docs/formats/speed-data.md).

import Foundation
import OpenSkyFormatsAnimation
@testable import OpenSkyGameData
import Testing

struct SpeedSampleTableRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theHumanWalkSamplesItsGroundSpeed() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let table = try SpeedSampleTable(
            data: vfs.contents(forPath: "meshes\\speeddatasinglefile.txt")
        )
        #expect(table.projects.count > 40)
        let human = try #require(
            table.project(forBehaviorPath: "meshes\\actors\\character\\defaultmale.hkx")
        )
        let walk = try #require(human.blendSpeed(state: 0, direction: 0, goal: 100))
        #expect(walk > 120 && walk < 150, "blend \(walk)")
        #expect(table.projects["horseproject"]?.states[60] != nil)
    }
}
