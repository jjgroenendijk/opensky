// NPC_ fields beyond the core `ActorBase` decode: inventory, attacks, combat
// style, overrides, sounds, destruction, and the face data (morphs, parts,
// tint layers). Layout and sources: docs/formats/actors.md.

import Foundation
import OpenSkyFormatsCore

/// One CSDT sound type with its CSDI and CSDC entries.
nonisolated public struct ActorSoundType: Equatable, Sendable {
    nonisolated public struct Entry: Equatable, Sendable {
        /// CSDI, a SOUN or SNDR.
        public var sound: FormID?
        /// CSDC, a percent.
        public var chance: UInt8?
    }

    /// 0 left foot to 21 play random or loop. See the page.
    public var type: UInt32
    public var entries: [Entry] = []
}

/// One TINI layer of a face tint.
nonisolated public struct ActorTintLayer: Equatable, Sendable {
    /// TINI, a tint mask index of the race.
    public var index: UInt16?
    /// TINC, RGBA.
    public var color: SIMD4<UInt8>?
    /// TINV, a percent.
    public var interpolation: UInt32?
    /// TIAS, a preset index.
    public var preset: Int16?
}

nonisolated public struct ActorBaseDetails: Equatable, Sendable {
    public var bounds: ObjectBounds?
    public var shortName: LString?
    public var keywords: [FormID] = []
    public var inventory: [Container.Entry] = []
    public var attacks: [RaceAttack] = []
    public var destructible: Destructible?
    /// INAM LVLI, ANAM ARMO, ATKR RACE, ZNAM CSTY, GNAM FLST, HCLF CLFM.
    public var deathItem: FormID?
    public var farAwayModel: FormID?
    public var attackRace: FormID?
    public var combatStyle: FormID?
    public var giftFilter: FormID?
    public var hairColor: FormID?
    /// SPOR, OCOR, GWOR, ECOR, DPLT: FLST package lists.
    public var spectatorOverride: FormID?
    public var observeDeadOverride: FormID?
    public var guardWarnOverride: FormID?
    public var combatOverride: FormID?
    public var defaultPackageList: FormID?
    /// SOFT, an OTFT.
    public var sleepingOutfit: FormID?
    /// CSCR, an NPC_ whose sounds this one uses.
    public var inheritsSoundsFrom: FormID?
    public var soundTypes: [ActorSoundType] = []
    /// NAM5, two bytes xEdit leaves unnamed.
    public var unknownNAM5: Data?
    public var height: Float?
    public var weight: Float?
    /// NAM8: 0 loud, 1 normal, 2 silent, 3 very loud, 4 quiet.
    public var soundLevel: UInt32?
    /// FTST, a TXST.
    public var headTexture: FormID?
    /// QNAM, RGB 0 to 1.
    public var textureLighting: SIMD3<Float>?
    /// NAM9: 19 morph sliders, nose long/short first and vampire morph last.
    public var faceMorphs: [Float] = []
    /// NAMA: nose, unknown, eyes, mouth.
    public var faceParts: [Int32] = []
    public var tintLayers: [ActorTintLayer] = []

    /// Decodes every field that `ActorBase` leaves alone.
    static func decode(record: ESMRecord, localized: Bool) throws -> (Self, FieldTally) {
        var fields = try RecordFields(record: record, type: "NPC_", localized: localized)
        for type in Self.decodedByActorBase {
            fields.markUsedAll(type)
        }
        var details = Self()
        details.bounds = fields.bounds()
        details.shortName = fields.lstring("SHRT")
        details.keywords = fields.formIDArray("KWDA")
        details.inventory = fields.inventory()
        details.attacks = fields.attacks()
        details.destructible = fields.destructible()
        details.readLinks(&fields)
        details.unknownNAM5 = fields.bytes("NAM5")
        details.height = fields.float("NAM6")
        details.weight = fields.float("NAM7")
        details.soundLevel = fields.uint32("NAM8")
        details.textureLighting = fields.read("QNAM") { try $0.readFloat3() }
        details.faceMorphs = fields
            .read("NAM9") { try Self.values(&$0) { try $0.readFloat32() } } ?? []
        details.faceParts = fields
            .read("NAMA") { try Self.values(&$0) { try $0.readInt32() } } ?? []
        details.readSoundTypes(&fields)
        details.readTintLayers(&fields)
        if fields.marker("DATA") == false {
            fields.note(.mismatch("NPC_ has no DATA marker"))
        }
        return (details, fields.finish())
    }

    private mutating func readLinks(_ fields: inout RecordFields) {
        deathItem = fields.formID("INAM")
        farAwayModel = fields.formID("ANAM")
        attackRace = fields.formID("ATKR")
        combatStyle = fields.formID("ZNAM")
        giftFilter = fields.formID("GNAM")
        hairColor = fields.formID("HCLF")
        spectatorOverride = fields.formID("SPOR")
        observeDeadOverride = fields.formID("OCOR")
        guardWarnOverride = fields.formID("GWOR")
        combatOverride = fields.formID("ECOR")
        defaultPackageList = fields.formID("DPLT")
        sleepingOutfit = fields.formID("SOFT")
        inheritsSoundsFrom = fields.formID("CSCR")
        headTexture = fields.formID("FTST")
    }

    private mutating func readSoundTypes(_ fields: inout RecordFields) {
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            switch fields.fields[index].type {
            case "CSDT":
                soundTypes
                    .append(ActorSoundType(type: fields
                            .read(at: index) { try $0.readUInt32() } ?? 0))
            case "CSDI" where !soundTypes.isEmpty:
                let sound = fields.read(at: index) { try $0.readFormID() }?.nonNull
                soundTypes[soundTypes.count - 1].entries.append(ActorSoundType.Entry(sound: sound))
            case "CSDC" where soundTypes.last?.entries.isEmpty == false:
                let last = soundTypes.count - 1
                let chance = fields.read(at: index) { try $0.readUInt8() }
                soundTypes[last].entries[soundTypes[last].entries.count - 1].chance = chance
            default:
                continue
            }
        }
    }

    private mutating func readTintLayers(_ fields: inout RecordFields) {
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            let type = fields.fields[index].type
            if type == "TINI" {
                tintLayers
                    .append(ActorTintLayer(index: fields.read(at: index) { try $0.readUInt16() }))
                continue
            }
            guard !tintLayers.isEmpty else { continue }
            let last = tintLayers.count - 1
            switch type {
            case "TINC":
                tintLayers[last].color = fields.read(at: index) { reader in
                    try SIMD4(
                        reader.readUInt8(),
                        reader.readUInt8(),
                        reader.readUInt8(),
                        reader.readUInt8()
                    )
                }
            case "TINV": tintLayers[last].interpolation = fields
                .read(at: index) { try $0.readUInt32() }
            case "TIAS": tintLayers[last].preset = fields.read(at: index) { try $0.readInt16() }
            default: continue
            }
        }
    }

    private static func values<Value>(
        _ reader: inout BinaryReader,
        _ decode: (inout BinaryReader) throws -> Value
    ) throws -> [Value] {
        var values: [Value] = []
        while reader.bytesRemaining >= 4 {
            try values.append(decode(&reader))
        }
        return values
    }

    /// Fields the core decode reads. KSIZ is implied by the KWDA length, PRKZ by the PRKR count.
    private static let decodedByActorBase: [FourCC] = [
        "EDID", "FULL", "VMAD", "ACBS", "CNAM", "DNAM", "AIDT", "TPLT", "RNAM", "VTCK", "WNAM",
        "PNAM", "DOFT", "PKID", "SPCT", "SPLO", "PRKR", "PRKZ", "SNAM", "CRIF", "KSIZ"
    ]
}

nonisolated extension RecordFields {
    /// Marks every field of `type` used, for fields another decoder of the record reads.
    mutating func markUsedAll(_ type: FourCC) {
        for index in fields.indices where fields[index].type == type {
            markUsed(at: index)
        }
    }
}
