// Each change form encoder against its decoder: a written change decodes to the value
// that was written, with the flags the decoder needs.

import Foundation
@testable import OpenSkyFormatsESS
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSChangeFormWriterTests {
    private static let cell = ESSRefID(kind: .default, value: 0x133C6)
    private static let sword = ESSRefID(kind: .default, value: 0x12EB7)
    private static let quest = ESSRefID(kind: .formIDArray, value: 2)

    @Test func movedReferenceReadsBack() throws {
        let written = ESSReferenceChange(
            form: ESSRefID(kind: .formIDArray, value: 1), isActor: false,
            placement: ESSPlacement(
                space: Self.cell, position: SIMD3(1, 2, 3), rotation: SIMD3(0, 0, 1.5)
            ),
            formFlags: 0x800, baseObject: Self.sword, scale: 1.25,
            extraData: ESSExtraDataList(entries: [
                .ownership(Self.cell), .count(3), .lock(level: 50, key: Self.sword),
                .aliasInstances([ESSAliasInstance(quest: Self.quest, aliasID: 4)])
            ]),
            inventory: [
                ESSInventoryItem(item: Self.sword, count: -1),
                ESSInventoryItem(
                    item: Self.sword, count: 1,
                    extraData: [ESSExtraDataList(entries: [.worn, .enchantment(Self.cell)])]
                )
            ]
        )
        let form = try written.changeForm()
        #expect(form.type?.signature == "REFR")
        #expect(form.has(ESSChangeFlag.Reference.move))
        #expect(form.has(ESSChangeFlag.Reference.inventory))
        #expect(try ESSReferenceChange(form) == written)
    }

    @Test func actorAndCreatedReferencesReadBack() throws {
        let actor = ESSReferenceChange(
            form: ESSRefID(kind: .default, value: 0x14), isActor: true,
            placement: ESSPlacement(space: Self.cell, position: .zero, rotation: SIMD3(0, 0, 2)),
            inventory: [ESSInventoryItem(item: Self.sword, count: 2)]
        )
        let actorForm = try actor.changeForm()
        #expect(actorForm.type?.signature == "ACHR")
        #expect(try ESSReferenceChange(actorForm) == actor)
        let created = ESSReferenceChange(
            form: ESSRefID(kind: .created, value: 1), isActor: false,
            placement: ESSPlacement(
                space: Self.cell, position: SIMD3(5, 6, 7), rotation: .zero, createdBase: Self.sword
            ),
            scale: 2
        )
        #expect(try ESSReferenceChange(created.changeForm()) == created)
    }

    @Test func actorBaseReadsBack() throws {
        var base = ESSActorBaseChange(form: ESSActorBaseChange.playerBase)
        base.factions = [ESSFactionRank(faction: Self.quest, rank: -1)]
        base.spells = [Self.sword]
        base.leveledSpells = []
        base.shouts = []
        base.name = "Dovahkiin"
        base.race = Self.cell
        base.face = ESSFace(
            hairColor: Self.sword, headParts: [Self.quest], morphs: [0.5, -0.25], presets: [1, 2]
        )
        base.isFemale = true
        let form = try base.changeForm()
        #expect(!form.has(ESSChangeFlag.ActorBase.attributes))
        #expect(try ESSActorBaseChange(form) == base)
    }

    @Test func questAndTopicReadBack() throws {
        var quest = ESSQuestChange(form: Self.quest)
        quest.questFlags = 0x3
        quest.stages = [10, 20].map { ESSQuestStage(index: $0, isDone: true) }
        quest.alreadyRun = true
        #expect(try ESSQuestChange(quest.changeForm()) == quest)
        let topic = ESSTopicChange(form: Self.sword, saidOnce: true)
        #expect(try ESSTopicChange(topic.changeForm()).saidOnce)
    }

    @Test(arguments: [(10, 1), (300, 2), (70000, 4)])
    func lengthSizeFitsTheData(_ size: Int, _ expected: Int) throws {
        let form = try ESSChangeForm(
            form: Self.sword, flags: 0, signature: "MISC", data: Data(count: size)
        )
        #expect(form.lengthSize == expected)
        var writer = ESSWriter()
        try form.write(into: &writer)
        var reader = ESSReader(writer.data)
        #expect(try ESSChangeForm.read(&reader, count: 1) == [form])
    }

    @Test func refusesExtraDataWithNoValue() {
        let extra = ESSExtraDataList(entries: [.other(type: 24)])
        let change = ESSReferenceChange(form: Self.sword, isActor: false, extraData: extra)
        #expect(throws: ESSError.self) { try change.changeForm() }
    }
}
