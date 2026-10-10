// Field groups that many record types share: destruction data, attacks, and
// inventory entries. Each group is read in file order, because a group member
// belongs to the opener before it. Layout and sources: docs/formats/records.md.

import Foundation
import OpenSkyFormatsCore

/// DEST header plus its stages.
nonisolated public struct Destructible: Equatable, Sendable {
    nonisolated public struct Stage: Equatable, Sendable {
        public var healthPercent: UInt8 = 0
        public var index: UInt8 = 0
        public var modelDamageStage: UInt8 = 0
        /// 0x01 cap damage, 0x02 disable, 0x04 destroy, 0x08 ignore external damage.
        public var flags: UInt8 = 0
        public var selfDamagePerSecond: Int32 = 0
        /// An EXPL and a DEBR.
        public var explosion: FormID?
        public var debris: FormID?
        public var debrisCount: Int32 = 0
        /// DMDL with DMDT and DMDS.
        public var model: ModelData?
        /// True when the DSTF end marker closed the stage.
        public var isClosed = false
    }

    public let health: Int32
    public let declaredStageCount: UInt8
    public let isVATSTargetable: Bool
    public let unknown: UInt16
    public var stages: [Stage] = []
}

nonisolated extension RecordFields {
    /// The DEST group, or nil when the record has none.
    public mutating func destructible() -> Destructible? {
        let start = fields.indices.first { fields[$0].type == "DEST" && !isUsed(at: $0) }
        guard let start, var group = read(at: start, { try Self.destructibleHeader(&$0) })
        else { return nil }
        scan: for index in (start + 1) ..< fields.count where !isUsed(at: index) {
            switch fields[index].type {
            case "DSTD":
                group.stages.append(read(at: index) { try Self.stage(&$0) } ?? Destructible.Stage())
            case "DMDL" where !group.stages.isEmpty:
                let model = model(at: index, hashes: "DMDT", alternates: "DMDS")
                group.stages[group.stages.count - 1].model = model
            case "DSTF" where !group.stages.isEmpty:
                markUsed(at: index)
                group.stages[group.stages.count - 1].isClosed = true
            default:
                break scan
            }
        }
        if Int(group.declaredStageCount) != group.stages.count {
            note(.mismatch("DEST stage count differs from the DSTD count"))
        }
        return group
    }

    /// Every ATKD with the ATKE that follows it.
    public mutating func attacks() -> [RaceAttack] {
        var attacks: [RaceAttack] = []
        for index in fields.indices where !isUsed(at: index) {
            switch fields[index].type {
            case "ATKD":
                attacks
                    .append(RaceAttack(properties: read(at: index) { try RaceAttack.Properties(&$0)
                    }))
            case "ATKE":
                if attacks.isEmpty || attacks[attacks.count - 1].event != nil {
                    attacks.append(RaceAttack())
                }
                attacks[attacks.count - 1].event = read(at: index) { try $0.readZString() }
            default:
                continue
            }
        }
        return attacks
    }

    /// Every CNTO with the COED that follows it. A COCT that differs is tallied.
    public mutating func inventory() -> [Container.Entry] {
        let declared = uint32("COCT")
        var entries: [Container.Entry] = []
        for index in fields.indices where !isUsed(at: index) {
            switch fields[index].type {
            case "CNTO":
                guard let entry = read(at: index, { try Self.inventoryEntry(&$0) })
                else { continue }
                entries.append(entry)
            case "COED" where !entries.isEmpty:
                let last = entries[entries.count - 1]
                guard let entry = read(at: index, { try Self.extraData(&$0, for: last) })
                else { continue }
                entries[entries.count - 1] = entry
            default:
                continue
            }
        }
        if let declared, Int(declared) != entries.count {
            note(.mismatch("COCT differs from the CNTO count"))
        }
        return entries
    }

    private static func destructibleHeader(_ reader: inout BinaryReader) throws -> Destructible {
        try Destructible(
            health: reader.readInt32(), declaredStageCount: reader.readUInt8(),
            isVATSTargetable: reader.readUInt8() != 0, unknown: reader.readUInt16()
        )
    }

    private static func stage(_ reader: inout BinaryReader) throws -> Destructible.Stage {
        var stage = Destructible.Stage()
        stage.healthPercent = try reader.readUInt8()
        stage.index = try reader.readUInt8()
        stage.modelDamageStage = try reader.readUInt8()
        stage.flags = try reader.readUInt8()
        stage.selfDamagePerSecond = try reader.readInt32()
        stage.explosion = try reader.readFormID().nonNull
        stage.debris = try reader.readFormID().nonNull
        stage.debrisCount = try reader.readInt32()
        return stage
    }

    private static func inventoryEntry(_ reader: inout BinaryReader) throws -> Container.Entry {
        try Container.Entry(
            item: reader.readFormID(), count: reader.readInt32(),
            owner: nil, ownerCondition: nil, condition: nil
        )
    }

    private static func extraData(
        _ reader: inout BinaryReader,
        for entry: Container.Entry
    ) throws -> Container.Entry {
        let owner = try reader.readFormID().nonNull
        let ownerCondition = try reader.readUInt32()
        return try Container.Entry(
            item: entry.item, count: entry.count,
            owner: owner, ownerCondition: owner == nil ? nil : ownerCondition,
            condition: reader.readFloat32()
        )
    }
}
