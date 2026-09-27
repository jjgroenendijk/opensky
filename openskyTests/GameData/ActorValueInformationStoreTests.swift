// Synthetic two-plugin AVIF override coverage plus the actor-value-index join.

import Foundation
@testable import opensky
import Testing

struct ActorValueInformationStoreTests {
    @Test
    func laterOverrideWinsAndEditorLookupIsCaseInsensitive() throws {
        let base = try plugin(records: [
            information(formID: 0x42, editorID: "AVBlock", name: "Block")
        ])
        let patch = try plugin(
            masters: ["Base.esm"],
            records: [information(formID: 0x42, editorID: "AVBlocking", name: "Blocking")]
        )
        let store = ActorValueInformationStore(
            plugins: [("Base.esm", base), ("Patch.esp", patch)]
        )

        let resolved = try #require(
            store.information(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.information.editorID == "AVBlocking")
        #expect(resolved.displayName == "Blocking")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.information(editorID: "avblocking")?.id == resolved.id)
        #expect(store.information(editorID: "AVBlock") == nil)
    }

    @Test
    func joinsRecordsToVanillaActorValueIndices() throws {
        let base = try plugin(records: [
            information(formID: 1, editorID: "AVOneHanded", name: "One-Handed", skill: true),
            information(formID: 2, editorID: "AVDestruction", name: "Destruction", skill: true),
            information(formID: 3, editorID: "AVHealth", name: "Health"),
            information(formID: 4, editorID: "ModAddedValue", name: "Nothing vanilla names")
        ])
        let store = ActorValueInformationStore(plugins: [("Base.esm", base)])

        #expect(store.information(actorValueIndex: 6)?.information.editorID == "AVOneHanded")
        #expect(store.information(actorValueIndex: 20)?.information.editorID == "AVDestruction")
        #expect(store.information(actorValueIndex: 24)?.information.editorID == "AVHealth")
        #expect(store.information(editorID: "ModAddedValue")?.actorValueIndex == nil)
        #expect(store.information(actorValueIndex: ActorValueIdentity.noneIndex) == nil)

        // Only the two records carrying both AVSK and a perk tree are skills,
        // and they come back in actor-value index order.
        #expect(store.skills.map(\.information.editorID) == ["AVOneHanded", "AVDestruction"])
        #expect(store.perkTreeRecords == store.skills)
        for skill in store.skills {
            let index = try #require(skill.actorValueIndex)
            #expect(ActorValueIdentity.isSkill(index: index))
        }
    }

    /// A perk tree is not the same thing as a skill: Dawnguard hangs the
    /// vampire and werewolf trees off actor values outside the skill range, and
    /// this is that shape synthetically.
    @Test
    func perkTreeRecordsAreWiderThanTheSkills() throws {
        let base = try plugin(records: [
            information(formID: 1, editorID: "AVSneak", name: "Sneak", skill: true),
            information(
                formID: 2,
                editorID: "AVSomethingElse",
                name: "Nothing vanilla names",
                skill: true
            )
        ])
        let store = ActorValueInformationStore(plugins: [("Base.esm", base)])

        #expect(store.perkTreeRecords.map(\.information.editorID)
            == ["AVSneak", "AVSomethingElse"])
        #expect(store.skills.map(\.information.editorID) == ["AVSneak"])
        #expect(store.information(editorID: "AVSomethingElse")?.information.hasPerkTree == true)
    }

    @Test
    func resolvesLinksRelativeToTheAuthoringPlugin() throws {
        let base = try plugin(records: [
            information(formID: 1, editorID: "AVSneak", name: "Sneak", skill: true)
        ])
        let patch = try plugin(masters: ["Base.esm"], records: [])
        let store = ActorValueInformationStore(
            plugins: [("Base.esm", base), ("Patch.esp", patch)]
        )

        let resolved = try #require(store.resolve(FormID(1), fromPlugin: "Base.esm"))
        #expect(resolved.information.editorID == "AVSneak")
        #expect(store.displayString(for: FormID(1), fromPlugin: "Base.esm") == "Sneak")
        #expect(
            store.displayString(for: FormID(0x0BAD), fromPlugin: "Base.esm")
                .hasPrefix("[UNRESOLVED]")
        )
    }

    private func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        if !records.isEmpty {
            data += ESMFixture.topGroup("AVIF", contents: records.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    private func information(
        formID: UInt32,
        editorID: String,
        name: String,
        skill: Bool = false
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        fields += ESMFixture.field("FULL", ESMFixture.zstring(name))
        if skill {
            fields += ESMFixture.field("CNAM", ActorValueInformationFixture.words([1]))
            fields += ESMFixture.field("AVSK", ActorValueInformationFixture.skillUse())
            fields += ActorValueInformationFixture.node(perk: 0, index: 0)
        }
        return ESMFixture.record("AVIF", formID: formID, data: fields)
    }
}
