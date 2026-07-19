// Actor record decoder + template resolver tests (ACHR, NPC_, LVLN) over
// synthetic in-code records (ESMFixture) — never extracted game files
// (AGENTS.md "Legal & IP boundary"). Layouts: UESP "Skyrim Mod:Mod File
// Format" per-record pages; see docs/formats/actors.md.

import Foundation
@testable import opensky
import Testing

struct ActorRecordDecodeTests {
    // MARK: - ACHR

    @Test func decodesPlacedActor() throws {
        let fields = achrFields(
            base: 0x0001_3BBF,
            position: [4096.5, -8192.25, 128],
            rotation: [0.5, -1.5, 3.14],
            scale: 1.5
        )
        let actor = try PlacedActor(
            record: record(ESMFixture.record("ACHR", formID: 0x2000, data: fields))
        )
        #expect(actor.formID == FormID(0x2000))
        #expect(actor.base == FormID(0x0001_3BBF))
        #expect(actor.placement.position == SIMD3(4096.5, -8192.25, 128))
        #expect(actor.placement.rotation == SIMD3(0.5, -1.5, 3.14))
        #expect(actor.scale == 1.5)
    }

    @Test func placedActorScaleDefaultsToOne() throws {
        let actor = try PlacedActor(
            record: record(ESMFixture.record("ACHR", formID: 1, data: achrFields()))
        )
        #expect(actor.scale == 1)
    }

    @Test func placedActorRequiresBaseAndPlacement() throws {
        var name = Data()
        name.appendUInt32(0x1000)
        let baseOnly = ESMFixture.record("ACHR", formID: 1, data: ESMFixture.field("NAME", name))
        #expect(throws: ESMError.self) {
            _ = try PlacedActor(record: record(baseOnly))
        }
        var data = Data()
        for _ in 0 ..< 6 {
            data.appendUInt32(Float(0).bitPattern)
        }
        let dataOnly = ESMFixture.record("ACHR", formID: 1, data: ESMFixture.field("DATA", data))
        #expect(throws: ESMError.self) {
            _ = try PlacedActor(record: record(dataOnly))
        }
    }

    @Test func placedActorRejectsOtherRecordTypes() throws {
        let refr = ESMFixture.record("REFR", formID: 1, data: achrFields())
        #expect(throws: ESMError.self) {
            _ = try PlacedActor(record: record(refr))
        }
    }

    // MARK: - NPC_

    @Test func decodesActorBase() throws {
        let actor = try npc(
            formID: 0x0001_3BBF,
            editorID: "Adrianne",
            flags: 0x0000_0001,
            templateFlags: 0x0101,
            template: 0x0001_B0B0,
            race: 0x0001_3746,
            wornArmor: 0x0009_BAAC,
            headParts: [0x0005_1111, 0x0005_2222],
            defaultOutfit: 0x000C_BE2E
        )
        #expect(actor.formID == FormID(0x0001_3BBF))
        #expect(actor.editorID == "Adrianne")
        #expect(actor.isFemale)
        #expect(actor.templateFlags == [.useTraits, .useInventory])
        #expect(actor.template == FormID(0x0001_B0B0))
        #expect(actor.race == FormID(0x0001_3746))
        #expect(actor.wornArmor == FormID(0x0009_BAAC))
        #expect(actor.headParts == [FormID(0x0005_1111), FormID(0x0005_2222)])
        #expect(actor.defaultOutfit == FormID(0x000C_BE2E))
    }

    @Test func actorBaseRequiresACBS() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("NoACBS"))
        let bytes = ESMFixture.record("NPC_", formID: 1, data: fields)
        #expect(throws: ESMError.self) {
            _ = try ActorBase(record: record(bytes), localized: false)
        }
    }

    @Test func actorBaseRejectsTruncatedACBS() throws {
        let fields = ESMFixture.field("ACBS", Data(count: 8))
        let bytes = ESMFixture.record("NPC_", formID: 1, data: fields)
        #expect(throws: ESMError.self) {
            _ = try ActorBase(record: record(bytes), localized: false)
        }
    }

    // MARK: - LVLN

    @Test func decodesLeveledList() throws {
        let list = try lvln(
            formID: 0x3000,
            chanceNone: 25,
            flags: 0x01,
            entries: [
                LeveledList.Entry(level: 1, reference: FormID(0x10), count: 1),
                LeveledList.Entry(level: 4, reference: FormID(0x20), count: 1)
            ]
        )
        #expect(list.formID == FormID(0x3000))
        #expect(list.editorID == "TestLeveled")
        #expect(list.chanceNone == 25)
        #expect(list.flags == .calculateFromAllLevels)
        #expect(list.entries.count == 2)
        #expect(list.entries[0] == LeveledList.Entry(level: 1, reference: FormID(0x10), count: 1))
    }

    @Test func leveledActorRejectsShortEntry() throws {
        let fields = ESMFixture.field("LVLO", Data(count: 4))
        let bytes = ESMFixture.record("LVLN", formID: 1, data: fields)
        #expect(throws: ESMError.self) {
            _ = try LeveledList(record: record(bytes))
        }
    }

    @Test func leveledActorAcceptsEightByteEntryWithDefaultCount() throws {
        // xEdit's lenient shape: uint16 level + 2 pad + formid, count -> 1.
        var data = Data()
        data.appendUInt16(7)
        data.appendUInt16(0)
        data.appendUInt32(0x40)
        let fields = ESMFixture.field("LVLO", data)
        let list = try LeveledList(
            record: record(ESMFixture.record("LVLN", formID: 1, data: fields))
        )
        #expect(list.entries == [LeveledList.Entry(level: 7, reference: FormID(0x40), count: 1)])
    }

    @Test func deterministicEntryPicksHighestLevelFirstAmongTies() throws {
        let list = try lvln(formID: 1, entries: [
            LeveledList.Entry(level: 1, reference: FormID(0x10), count: 1),
            LeveledList.Entry(level: 4, reference: FormID(0x20), count: 1),
            LeveledList.Entry(level: 4, reference: FormID(0x30), count: 1)
        ])
        #expect(list.deterministicEntry?.reference == FormID(0x20))
    }
}

struct ActorTemplateResolverTests {
    @Test func resolvesDirectActorWithoutTemplate() throws {
        let base = try npc(
            formID: 0x100,
            flags: 0x0000_0001,
            race: 0xA,
            wornArmor: 0xB,
            headParts: [0xC],
            defaultOutfit: 0xD
        )
        let resolved = try resolver(npcs: [base]).resolve(base: FormID(0x100))
        #expect(resolved.chain == [.npc(FormID(0x100))])
        #expect(resolved.isFemale == ActorSourcedField(value: true, source: FormID(0x100)))
        #expect(resolved.race == ActorSourcedField(value: FormID(0xA), source: FormID(0x100)))
        #expect(resolved.wornArmor.value == FormID(0xB))
        #expect(resolved.headParts.value == [FormID(0xC)])
        #expect(resolved.defaultOutfit.value == FormID(0xD))
    }

    @Test func useTraitsPullsTraitFieldsFromTemplateOnly() throws {
        let template = try npc(
            formID: 0x200,
            flags: 0x0000_0001,
            race: 0xA2,
            wornArmor: 0xB2,
            headParts: [0xC2],
            defaultOutfit: 0xD2
        )
        let base = try npc(
            formID: 0x100,
            templateFlags: 0x0001, // useTraits
            template: 0x200,
            race: 0xA1,
            wornArmor: 0xB1,
            headParts: [0xC1],
            defaultOutfit: 0xD1
        )
        let resolved = try resolver(npcs: [base, template]).resolve(base: FormID(0x100))
        // Traits (gender, race, skin, head parts) come from the template.
        #expect(resolved.isFemale == ActorSourcedField(value: true, source: FormID(0x200)))
        #expect(resolved.race == ActorSourcedField(value: FormID(0xA2), source: FormID(0x200)))
        #expect(resolved.wornArmor.source == FormID(0x200))
        #expect(resolved.headParts.value == [FormID(0xC2)])
        // Inventory (outfit) stays local: useInventory is clear.
        #expect(resolved.defaultOutfit
            == ActorSourcedField(value: FormID(0xD1), source: FormID(0x100)))
    }

    @Test func useInventoryPullsOutfitFromTemplateOnly() throws {
        let template = try npc(formID: 0x200, race: 0xA2, defaultOutfit: 0xD2)
        let base = try npc(
            formID: 0x100,
            templateFlags: 0x0100, // useInventory
            template: 0x200,
            race: 0xA1,
            defaultOutfit: 0xD1
        )
        let resolved = try resolver(npcs: [base, template]).resolve(base: FormID(0x100))
        #expect(resolved.defaultOutfit
            == ActorSourcedField(value: FormID(0xD2), source: FormID(0x200)))
        #expect(resolved.race == ActorSourcedField(value: FormID(0xA1), source: FormID(0x100)))
    }

    @Test func templateFlagWithoutTemplateIsInert() throws {
        let base = try npc(formID: 0x100, templateFlags: 0x0101, race: 0xA1, defaultOutfit: 0xD1)
        let resolved = try resolver(npcs: [base]).resolve(base: FormID(0x100))
        #expect(resolved.race.source == FormID(0x100))
        #expect(resolved.defaultOutfit.source == FormID(0x100))
    }

    @Test func multiHopChainDelegatesPerRecordFlags() throws {
        // base delegates traits -> middle; middle delegates traits -> top.
        // middle delegates inventory too, but base does not, so outfit stays
        // at base.
        let top = try npc(formID: 0x300, race: 0xA3, defaultOutfit: 0xD3)
        let middle = try npc(
            formID: 0x200,
            templateFlags: 0x0101, // useTraits + useInventory
            template: 0x300,
            race: 0xA2,
            defaultOutfit: 0xD2
        )
        let base = try npc(
            formID: 0x100,
            templateFlags: 0x0001, // useTraits
            template: 0x200,
            race: 0xA1,
            defaultOutfit: 0xD1
        )
        let resolved = try resolver(npcs: [base, middle, top]).resolve(base: FormID(0x100))
        #expect(resolved.chain
            == [.npc(FormID(0x100)), .npc(FormID(0x200)), .npc(FormID(0x300))])
        #expect(resolved.race == ActorSourcedField(value: FormID(0xA3), source: FormID(0x300)))
        #expect(resolved.defaultOutfit
            == ActorSourcedField(value: FormID(0xD1), source: FormID(0x100)))
    }

    @Test func resolvesThroughLeveledListDeterministically() throws {
        let chosen = try npc(formID: 0x400, race: 0xA4)
        let other = try npc(formID: 0x500, race: 0xA5)
        let list = try lvln(formID: 0x300, entries: [
            LeveledList.Entry(level: 1, reference: FormID(0x500), count: 1),
            LeveledList.Entry(level: 10, reference: FormID(0x400), count: 1)
        ])
        let base = try npc(
            formID: 0x100,
            templateFlags: 0x0001, // useTraits
            template: 0x300,
            race: 0xA1
        )
        let resolved = try resolver(npcs: [base, chosen, other], leveled: [list])
            .resolve(base: FormID(0x100))
        #expect(resolved.chain == [
            .npc(FormID(0x100)),
            .leveled(list: FormID(0x300), chosen: FormID(0x400)),
            .npc(FormID(0x400))
        ])
        #expect(resolved.race == ActorSourcedField(value: FormID(0xA4), source: FormID(0x400)))
    }

    @Test func detectsTemplateCycle() throws {
        let first = try npc(formID: 0x100, templateFlags: 0x0001, template: 0x200)
        let second = try npc(formID: 0x200, templateFlags: 0x0001, template: 0x100)
        #expect(throws: ActorResolveError.cycle(
            [FormID(0x100), FormID(0x200), FormID(0x100)]
        )) {
            _ = try resolver(npcs: [first, second]).resolve(base: FormID(0x100))
        }
    }

    @Test func detectsMissingTemplateTarget() throws {
        let base = try npc(formID: 0x100, templateFlags: 0x0001, template: 0xDEAD)
        #expect(throws: ActorResolveError.missingTarget(
            FormID(0xDEAD), referencedBy: FormID(0x100)
        )) {
            _ = try resolver(npcs: [base]).resolve(base: FormID(0x100))
        }
    }

    @Test func detectsMissingBase() throws {
        #expect(throws: ActorResolveError.missingTarget(FormID(0x100), referencedBy: nil)) {
            _ = try resolver(npcs: []).resolve(base: FormID(0x100))
        }
    }

    @Test func detectsEmptyLeveledList() throws {
        let list = try lvln(formID: 0x300, entries: [])
        let base = try npc(formID: 0x100, template: 0x300)
        #expect(throws: ActorResolveError.emptyLeveledList(
            FormID(0x300), referencedBy: FormID(0x100)
        )) {
            _ = try resolver(npcs: [base], leveled: [list]).resolve(base: FormID(0x100))
        }
    }
}

// MARK: - Fixture builders (file-scope: shared by both suites)

/// Parses one synthetic record through the container walk.
private func record(_ bytes: Data) throws -> ESMRecord {
    let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
    guard case let .record(record)? = children.first else {
        throw ESMError.malformed("fixture did not produce a record")
    }
    return record
}

private func achrFields(
    base: UInt32 = 0x1000,
    position: [Float] = [1, 2, 3],
    rotation: [Float] = [0, 0, 0],
    scale: Float? = nil
) -> Data {
    var name = Data()
    name.appendUInt32(base)
    var data = Data()
    for value in position + rotation {
        data.appendUInt32(value.bitPattern)
    }
    var fields = ESMFixture.field("NAME", name) + ESMFixture.field("DATA", data)
    if let scale {
        var xscl = Data()
        xscl.appendUInt32(scale.bitPattern)
        fields += ESMFixture.field("XSCL", xscl)
    }
    return fields
}

/// ACBS: uint32 flags, 7 uint16 stat words, uint16 template flags,
/// uint16 health offset, uint16 bleedout override (24 bytes).
private func acbs(flags: UInt32 = 0, templateFlags: UInt16 = 0) -> Data {
    var data = Data()
    data.appendUInt32(flags)
    for _ in 0 ..< 7 {
        data.appendUInt16(0)
    }
    data.appendUInt16(templateFlags)
    data.appendUInt16(0)
    data.appendUInt16(0)
    return data
}

private func formIDField(_ type: String, _ value: UInt32) -> Data {
    var data = Data()
    data.appendUInt32(value)
    return ESMFixture.field(type, data)
}

private func npc(
    formID: UInt32,
    editorID: String? = nil,
    flags: UInt32 = 0,
    templateFlags: UInt16 = 0,
    template: UInt32? = nil,
    race: UInt32? = nil,
    wornArmor: UInt32? = nil,
    headParts: [UInt32] = [],
    defaultOutfit: UInt32? = nil
) throws -> ActorBase {
    var fields = Data()
    if let editorID {
        fields += ESMFixture.field("EDID", ESMFixture.zstring(editorID))
    }
    fields += ESMFixture.field("ACBS", acbs(flags: flags, templateFlags: templateFlags))
    if let template {
        fields += formIDField("TPLT", template)
    }
    if let race {
        fields += formIDField("RNAM", race)
    }
    if let wornArmor {
        fields += formIDField("WNAM", wornArmor)
    }
    for part in headParts {
        fields += formIDField("PNAM", part)
    }
    if let defaultOutfit {
        fields += formIDField("DOFT", defaultOutfit)
    }
    return try ActorBase(
        record: record(ESMFixture.record("NPC_", formID: formID, data: fields)),
        localized: false
    )
}

private func lvln(
    formID: UInt32,
    chanceNone: UInt8 = 0,
    flags: UInt8 = 0,
    entries: [LeveledList.Entry]
) throws -> LeveledList {
    var fields = ESMFixture.field("EDID", ESMFixture.zstring("TestLeveled"))
        + ESMFixture.field("LVLD", Data([chanceNone]))
        + ESMFixture.field("LVLF", Data([flags]))
        + ESMFixture.field("LLCT", Data([UInt8(entries.count)]))
    for entry in entries {
        var data = Data()
        data.appendUInt16(entry.level)
        data.appendUInt16(0)
        data.appendUInt32(entry.reference.rawValue)
        data.appendUInt32(entry.count)
        fields += ESMFixture.field("LVLO", data)
    }
    return try LeveledList(
        record: record(ESMFixture.record("LVLN", formID: formID, data: fields))
    )
}

private func resolver(
    npcs: [ActorBase],
    leveled: [LeveledList] = []
) -> ActorTemplateResolver {
    ActorTemplateResolver(
        actors: Dictionary(uniqueKeysWithValues: npcs.map { ($0.formID.rawValue, $0) }),
        leveledActors: Dictionary(
            uniqueKeysWithValues: leveled.map { ($0.formID.rawValue, $0) }
        )
    )
}
