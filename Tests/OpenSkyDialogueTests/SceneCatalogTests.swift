// The scene catalog over a load order: a scene and its PNAM quest take the
// FormIDs of the quest store's load-order space.

import Foundation
@testable import OpenSkyDialogue
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct SceneCatalogTests {
    /// `Extra.esm` loads third but lists one master, so its own index 1 becomes 0x02.
    @Test func translatesASceneQuestIntoTheLoadOrderSpace() throws {
        let scene = ESMFixture.recordBytes("SCEN", formID: 0x0100_0900, fields: [
            ("EDID", ESMFixture.zstring("ExtraScene")), ("PNAM", ESMFixture.u32(0x0100_0300))
        ])
        let plugins = try [
            (name: "Base.esm", file: ESMFixture.plugin(records: [])),
            (name: "Patch.esm", file: ESMFixture.plugin(masters: ["Base.esm"], records: [])),
            (name: "Extra.esm", file: ESMFixture.plugin(masters: ["Base.esm"], records: [scene]))
        ]
        let catalog = SceneCatalog(
            store: SceneStore(plugins: plugins),
            resolver: .loadOrder(plugins.map(\.name))
        )

        let entry = try #require(catalog.scene(editorID: "ExtraScene"))
        #expect(entry.formID == FormID(0x0200_0900))
        #expect(entry.key == .plugin(name: "extra.esm", objectID: 0x900))
        #expect(entry.quest == FormID(0x0200_0300))
        #expect(entry.scene.quest == FormID(0x0100_0300))
        #expect(catalog.scenes(ofQuest: FormID(0x0200_0300)).map(\.formID) == [entry.formID])
    }
}
