// `NPC_` change data, the actor base: base data, factions, spells, name, skills, class,
// race, face, and sex. The player's base is `00000007`.
// See docs/formats/ess-change-forms.md#actor-bases.

import Foundation

nonisolated public struct ESSFactionRank: Equatable, Sendable {
    public let faction: ESSRefID
    public let rank: Int8
}

nonisolated public struct ESSFace: Equatable, Sendable {
    public let hairColor: ESSRefID
    public let skinTone: SIMD4<UInt8>
    public let skin: ESSRefID
    public let headParts: [ESSRefID]
    /// Empty when the save stores no morph data.
    public let morphs: [Float]
    public let presets: [Int32]
}

nonisolated public struct ESSActorBaseChange: Equatable, Sendable {
    public let form: ESSRefID
    public private(set) var formFlags: UInt32?
    /// The 24-byte `ACBS` block, laid out as in the `NPC_` record.
    public private(set) var baseData: Data?
    public private(set) var factions: [ESSFactionRank]?
    public private(set) var spells: [ESSRefID]?
    public private(set) var leveledSpells: [ESSRefID]?
    public private(set) var shouts: [ESSRefID]?
    public private(set) var name: String?
    /// The 52-byte `DNAM` block: 18 skill values, then 18 offsets, then more.
    public private(set) var skills: Data?
    public private(set) var npcClass: ESSRefID?
    public private(set) var race: ESSRefID?
    public private(set) var face: ESSFace?
    public private(set) var isFemale: Bool?
    public private(set) var status = ESSDecodeStatus.complete

    /// The player's base `NPC_`, in `Skyrim.esm`.
    public static let playerBase = ESSRefID(kind: .default, value: 0x7)

    /// The level in `ACBS`, or nil without base data. A level-multiplier actor
    /// stores the multiplier times 1000 here.
    public var level: UInt16? {
        guard let baseData, baseData.count >= 10 else { return nil }
        let start = baseData.startIndex + 8
        return UInt16(baseData[start]) | UInt16(baseData[start + 1]) << 8
    }

    /// The 18 skill values in actor value order, from One-handed to Enchanting.
    public var skillValues: [UInt8]? {
        skills.map { Array($0.prefix(18)) }
    }

    private typealias Flag = ESSChangeFlag.ActorBase

    public init(_ change: ESSChangeForm) throws(ESSError) {
        guard change.type?.signature == "NPC_" else {
            throw .invalidValue(context: "change form \(change.form) is not an actor base")
        }
        form = change.form
        var reader = try ESSReader(change.data())
        try read(&reader, change: change)
        if status.isComplete, !reader.isAtEnd {
            status = .partial(blockedBy: "\(reader.bytesRemaining) unread bytes")
        }
    }

    private mutating func read(_ reader: inout ESSReader, change: ESSChangeForm) throws(ESSError) {
        if change.has(ESSChangeFlag.formFlags) {
            formFlags = try reader.uint32("form flags")
            _ = try reader.uint16("form flags")
        }
        if change.has(Flag.baseData) {
            baseData = try reader.bytes(24, "ACBS")
        }
        // Attribute data has no documented place, so every later field could be shifted.
        guard !change.has(Flag.attributes) else {
            status = .partial(blockedBy: "ACTOR_BASE_ATTRIBUTES")
            return
        }
        if change.has(Flag.factions) {
            factions = try Self.readFactions(&reader)
        }
        if change.has(Flag.spellList) {
            spells = try Self.readRefIDs(&reader, "spells")
            leveledSpells = try Self.readRefIDs(&reader, "leveled spells")
            shouts = try Self.readRefIDs(&reader, "shouts")
        }
        if change.has(Flag.aiData) {
            try reader.skip(20, "AIDT")
        }
        if change.has(Flag.fullName) {
            name = try reader.wstring("full name")
        }
        if change.has(Flag.skills) {
            skills = try reader.bytes(52, "DNAM")
        }
        try readAppearance(&reader, change: change)
    }

    private mutating func readAppearance(
        _ reader: inout ESSReader, change: ESSChangeForm
    ) throws(ESSError) {
        if change.has(Flag.npcClass) {
            npcClass = try reader.refID("class")
        }
        if change.has(Flag.race) {
            race = try reader.refID("race")
            _ = try reader.refID("previous race")
        }
        if change.has(Flag.face) {
            face = try Self.readFace(&reader)
        }
        if change.has(Flag.gender) {
            isFemale = try reader.uint8("gender") == 1
        }
        if change.has(Flag.defaultOutfit) {
            _ = try reader.refID("default outfit")
        }
        if change.has(Flag.sleepOutfit) {
            _ = try reader.refID("sleep outfit")
        }
    }

    private static func readFactions(_ reader: inout ESSReader) throws(ESSError)
        -> [ESSFactionRank]
    {
        let count = try reader.count("factions", minimumElementSize: 4)
        var factions: [ESSFactionRank] = []
        for _ in 0 ..< count {
            try factions.append(ESSFactionRank(
                faction: reader.refID("faction"), rank: reader.int8("faction rank")
            ))
        }
        return factions
    }

    static func readRefIDs(
        _ reader: inout ESSReader,
        _ context: String
    ) throws(ESSError) -> [ESSRefID] {
        let count = try reader.count(context, minimumElementSize: 3)
        var ids: [ESSRefID] = []
        for _ in 0 ..< count {
            try ids.append(reader.refID(context))
        }
        return ids
    }

    private static func readFace(_ reader: inout ESSReader) throws(ESSError) -> ESSFace? {
        guard try reader.uint8("face present") != 0 else { return nil }
        let hair = try reader.refID("hair color")
        let tone = try reader.bytes(4, "skin tone")
        let skin = try reader.refID("skin")
        let parts = try readRefIDs(&reader, "head parts")
        var morphs: [Float] = []
        var presets: [Int32] = []
        if try reader.uint8("face data present") != 0 {
            let morphCount = try reader.count32("face morphs", minimumElementSize: 4)
            for _ in 0 ..< morphCount {
                try morphs.append(reader.float32("face morph"))
            }
            let presetCount = try reader.count32("face presets", minimumElementSize: 4)
            for _ in 0 ..< presetCount {
                try presets.append(reader.int32("face preset"))
            }
        }
        let start = tone.startIndex
        return ESSFace(
            hairColor: hair,
            skinTone: SIMD4(tone[start], tone[start + 1], tone[start + 2], tone[start + 3]),
            skin: skin, headParts: parts, morphs: morphs, presets: presets
        )
    }
}
