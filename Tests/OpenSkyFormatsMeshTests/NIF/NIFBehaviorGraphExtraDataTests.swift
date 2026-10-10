// `BSBehaviorGraphExtraData` over synthetic files: the project an object names.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFBehaviorGraphExtraDataTests {
    private func extraData(name: UInt32, graph: UInt32, controls: UInt8) -> Data {
        var data = Data()
        data.appendUInt32(name)
        data.appendUInt32(graph)
        data.append(controls)
        return data
    }

    @Test func readsTheProjectOfAnObject() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("BSFadeNode", Data(count: 4)),
                .init("BSBehaviorGraphExtraData", extraData(name: 0, graph: 1, controls: 1))
            ],
            strings: ["BGED", "Traps\\SwingingBlade/TrapBladeSwinging01.hkx"]
        ))
        let data = try #require(NIFBehaviorGraphExtraData.first(in: file))
        #expect(data.name == "BGED")
        #expect(data.controlsBaseSkeleton)
        #expect(NIFBehaviorGraphExtraData.projectPath(in: file)
            == "meshes\\traps\\swingingblade\\trapbladeswinging01.hkx")
    }

    @Test func aShortOrEmptyBlockNamesNoProject() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("BSBehaviorGraphExtraData", Data(count: 8)),
                .init("BSBehaviorGraphExtraData", extraData(name: 0, graph: .max, controls: 0))
            ],
            strings: ["BGED"]
        ))
        #expect(NIFBehaviorGraphExtraData.first(in: file)?.graphFile == nil)
        #expect(NIFBehaviorGraphExtraData.projectPath(in: file) == nil)
    }
}
