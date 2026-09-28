// Synthetic EQUP coverage (issue #467): the decoder, the parent walk that
// turns an EQUP graph into `HandSlots`, and the load-order store. Every byte
// is assembled in code from the published record layout — never extracted game
// files (AGENTS.md "Legal & IP boundary").
//
// The graph mirrors the vanilla master's shape: two leaves named by editor ID,
// a choose-one composite, an all-of composite, and a one-parent composite that
// is how a shield ends up in the left hand.

import Foundation
@testable import opensky
import Testing

struct EquipSlotTests {
    private enum Slot {
        static let rightHand: UInt32 = 0x0100
        static let leftHand: UInt32 = 0x0110
        static let eitherHand: UInt32 = 0x0120
        static let bothHands: UInt32 = 0x0130
        static let shield: UInt32 = 0x0140
        static let voice: UInt32 = 0x0150
    }

    // MARK: - Decoder

    @Test
    func decodesAParentSlotArrayAndTheUseAllParentsFlag() throws {
        let record = try ShoutFixture.record(
            type: "EQUP",
            fields: EquipSlotFixture.fields(
                editorID: "BothHands",
                parents: [Slot.leftHand, Slot.rightHand],
                usesAllParents: true
            )
        )

        let slot = try EquipSlot(record: record)

        #expect(slot.editorID == "BothHands")
        #expect(slot.parents == [FormID(Slot.leftHand), FormID(Slot.rightHand)])
        #expect(slot.usesAllParents)
        #expect(slot.skipped.total == 0)
    }

    @Test
    func aLeafSlotHasNoParentsAndDoesNotUseThem() throws {
        let record = try ShoutFixture.record(
            type: "EQUP",
            fields: EquipSlotFixture.fields(
                editorID: "RightHand",
                parents: [],
                usesAllParents: false
            )
        )

        let slot = try EquipSlot(record: record)

        #expect(slot.parents.isEmpty)
        #expect(!slot.usesAllParents)
    }

    /// A PNAM whose byte count is not a multiple of four is a mod quirk: the
    /// whole entries still decode and the trailing bytes are dropped.
    @Test
    func aTrailingPartialParentIsDroppedWithoutLosingTheWholeOnes() throws {
        var packed = Data()
        packed.appendUInt32(Slot.leftHand)
        packed.append(contentsOf: [0x01, 0x02])
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Ragged"))
            + ESMFixture.field("PNAM", packed)
        let record = try ShoutFixture.record(type: "EQUP", fields: fields)

        let slot = try EquipSlot(record: record)

        #expect(slot.parents == [FormID(Slot.leftHand)])
        #expect(slot.skipped.total == 0)
    }

    @Test
    func aTruncatedDataFieldIsTalliedWithoutLosingTheRecord() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("ShortData"))
            + ESMFixture.field("DATA", Data([1]))
        let record = try ShoutFixture.record(type: "EQUP", fields: fields)

        let slot = try EquipSlot(record: record)

        #expect(slot.editorID == "ShortData")
        #expect(!slot.usesAllParents)
        #expect(slot.skipped.counts[.malformedField("DATA")] == 1)
    }

    @Test
    func anEquipSlotDecoderRejectsAnotherRecordType() throws {
        let record = try ShoutFixture.record(type: "DUAL", fields: Data())

        #expect(throws: ESMError.self) {
            _ = try EquipSlot(record: record)
        }
    }

    // MARK: - Hand resolution

    @Test
    func theGraphResolvesEveryVanillaSlotShape() throws {
        let table = try graph()

        #expect(table.hands(of: FormID(Slot.rightHand)) == .rightHand)
        #expect(table.hands(of: FormID(Slot.leftHand)) == .leftHand)
        #expect(table.hands(of: FormID(Slot.bothHands)) == .bothHands)
        // A choose-one slot is deterministic: right hand when it is an option.
        #expect(table.hands(of: FormID(Slot.eitherHand)) == .rightHand)
        // A shield takes all of its single parent, so it fills the left hand.
        #expect(table.hands(of: FormID(Slot.shield)) == .leftHand)
        // A leaf the engine does not name as a hand takes no hand at all.
        #expect(table.hands(of: FormID(Slot.voice))?.isEmpty == true)
    }

    /// The distinction `hands(of:)` collapses, which is what readying a spell
    /// to a named hand needs (issue #470): `BothHands` takes everything it
    /// names, `EitherHand` lets the equipper pick.
    @Test
    func theHandChoiceKeepsAllOfAndOneOfApart() throws {
        let table = try graph()

        #expect(table.handChoice(of: FormID(Slot.bothHands)) == .fixed(.bothHands))
        #expect(table.handChoice(of: FormID(Slot.eitherHand)) == .choice(.bothHands))
        #expect(table.handChoice(of: FormID(Slot.rightHand)) == .fixed(.rightHand))
        #expect(table.handChoice(of: FormID(Slot.voice)) == .fixed([]))
    }

    /// A two-handed slot ignores the request and fills both; a choose-one slot
    /// answers with the hand asked for, and refuses one it does not offer.
    @Test
    func occupancyAnswersTheRequestedHandOrRefusesIt() throws {
        let table = try graph()

        let both = try #require(table.handChoice(of: FormID(Slot.bothHands)))
        #expect(both.occupancy(preferring: .rightHand) == .bothHands)
        #expect(both.occupancy(preferring: .leftHand) == .bothHands)

        let either = try #require(table.handChoice(of: FormID(Slot.eitherHand)))
        #expect(either.occupancy(preferring: .rightHand) == .rightHand)
        #expect(either.occupancy(preferring: .leftHand) == .leftHand)

        let shield = try #require(table.handChoice(of: FormID(Slot.shield)))
        #expect(shield.occupancy(preferring: .rightHand) == .leftHand)

        let voice = try #require(table.handChoice(of: FormID(Slot.voice)))
        #expect(voice.occupancy(preferring: .rightHand) == nil)
    }

    @Test
    func anUnresolvableOrNullLinkIsAMissRatherThanAnEmptyAnswer() throws {
        let table = try graph()

        #expect(table.hands(of: nil) == nil)
        #expect(table.hands(of: FormID(0)) == nil)
        #expect(table.hands(of: FormID(0xDEAD)) == nil)
    }

    /// A mod that makes the parent chain cyclic must terminate rather than
    /// recurse; the depth cap is what bounds it.
    @Test
    func aCyclicParentChainTerminates() throws {
        var contents = Data()
        contents += ESMFixture.record(
            "EQUP",
            formID: 0x0200,
            data: EquipSlotFixture.fields(
                editorID: "LoopA", parents: [0x0210], usesAllParents: true
            )
        )
        contents += ESMFixture.record(
            "EQUP",
            formID: 0x0210,
            data: EquipSlotFixture.fields(
                editorID: "LoopB", parents: [0x0200], usesAllParents: true
            )
        )
        let table = try EquipSlotTable(
            file: ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup("EQUP", contents: contents))
        )

        #expect(table.hands(of: FormID(0x0200))?.isEmpty == true)
    }

    // MARK: - Store

    @Test
    func theStoreResolvesSlotsAcrossTheLoadOrder() throws {
        let base = try ESMFile(data: pluginBytes())
        let store = EquipSlotStore(plugins: [(name: "Base.esm", file: base)])

        #expect(store.slots.count == 6)
        #expect(store.slot(editorID: "bothhands")?.slot.usesAllParents == true)
        #expect(
            store.hands(of: FormID(Slot.bothHands), fromPlugin: "Base.esm") == .bothHands
        )
        #expect(store.hands(of: FormID(Slot.shield), fromPlugin: "Base.esm") == .leftHand)
        #expect(store.hands(of: FormID(0xDEAD), fromPlugin: "Base.esm") == nil)
        #expect(
            store.displayString(for: FormID(Slot.voice), fromPlugin: "Base.esm") == "Voice"
        )
        #expect(
            store.displayString(for: FormID(0xDEAD), fromPlugin: "Base.esm")
                .hasPrefix("[UNRESOLVED]")
        )
    }

    private func graph() throws -> EquipSlotTable {
        try EquipSlotTable(file: ESMFile(data: pluginBytes()))
    }

    private func pluginBytes() -> Data {
        var contents = Data()
        contents += slot(Slot.rightHand, "RightHand", parents: [], all: false)
        contents += slot(Slot.leftHand, "LeftHand", parents: [], all: false)
        contents += slot(
            Slot.eitherHand,
            "EitherHand",
            parents: [Slot.leftHand, Slot.rightHand],
            all: false
        )
        contents += slot(
            Slot.bothHands,
            "BothHands",
            parents: [Slot.leftHand, Slot.rightHand],
            all: true
        )
        contents += slot(Slot.shield, "Shield", parents: [Slot.leftHand], all: true)
        contents += slot(Slot.voice, "Voice", parents: [], all: false)
        return ESMFixture.tes4() + ESMFixture.topGroup("EQUP", contents: contents)
    }

    private func slot(
        _ formID: UInt32,
        _ editorID: String,
        parents: [UInt32],
        all: Bool
    ) -> Data {
        ESMFixture.record(
            "EQUP",
            formID: formID,
            data: EquipSlotFixture.fields(
                editorID: editorID,
                parents: parents,
                usesAllParents: all
            )
        )
    }
}
