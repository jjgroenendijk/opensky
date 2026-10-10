// Scene-owned interaction metadata built from synthetic REFR/model-base
// records. No game data is embedded in these fixtures.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldInterface
import Testing

extension CellSceneBuilderTests {
    @Test(.enabled(if: Self.hasDevice))
    func resolvesInteractionNamesActionsAndOverride() throws {
        let cases: [(String, InteractionAction)] = [
            ("ACTI", .activate),
            ("CONT", .search),
            ("TREE", .harvest),
            ("FURN", .use),
            ("DOOR", .open),
            ("FLOR", .harvest),
            ("TACT", .talk)
        ]
        let voiceTypeField = ESMFixture.field("VNAM", Data([0xD5, 0x3A, 0x01, 0x00]))
        var refs = Data()
        var records: [String: Data] = [:]
        for (index, entry) in cases.enumerated() {
            let base = UInt32(0x300 + index)
            refs += refrRecord(formID: base + 0x100, base: base)
            records[entry.0, default: Data()] += modelBaseRecord(
                type: entry.0,
                formID: base,
                modelPath: nil,
                displayName: "\(entry.0) Name",
                activateTextOverride: entry.0 == "ACTI" ? "Mine" : nil,
                extraFields: entry.0 == "TACT" ? voiceTypeField : Data()
            )
        }
        let scene = try build(pluginData: plugin(
            temporaryRefs: refs,
            modelBaseRecords: records
        ))

        #expect(scene.interactions.count == cases.count)
        for (index, entry) in cases.enumerated() {
            let interaction = scene.interactions[FormID(UInt32(0x400 + index))]
            #expect(interaction?.name == "\(entry.0) Name")
            #expect(interaction?.action == entry.1)
        }
        #expect(scene.interactions[FormID(0x400)]?.actionLabel == "Mine")
        #expect(scene.interactions[FormID(0x404)]?.actionLabel == "Open")
        #expect(scene.interactions[FormID(0x405)]?.actionLabel == "Harvest")
        #expect(scene.interactions[FormID(0x406)]?.voiceType == FormID(0x0001_3AD5))
        #expect(scene.interactions[FormID(0x404)]?.voiceType == nil)
    }
}
