// PACK members AI does not run yet: idle animations, the template procedure
// tree, the template's data inputs, and the begin, end, and change events.
// Layout from xEdit dev-4.1.6 `PACK`; docs/formats/packages.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct PackageDetails: Equatable, Sendable {
    /// IDLF/IDLC/IDLT/IDLA.
    public struct IdleAnimations: Equatable, Sendable {
        /// Bit 0 run in sequence, bit 2 do once, bit 4 ignored by sandbox.
        public internal(set) var flags: UInt8 = 0
        /// IDLC as written. Advisory; `animations` is what decoded.
        public internal(set) var declaredCount: UInt8?
        public internal(set) var timer: Float?
        public internal(set) var animations: [FormID] = []
    }

    /// PFO2: package flags a branch sets and clears while it runs.
    public struct FlagsOverride: Equatable, Sendable {
        public let setGeneralFlags: UInt32
        public let clearGeneralFlags: UInt32
        public let setInterruptFlags: UInt16
        public let clearInterruptFlags: UInt16
        public let preferredSpeed: UInt8
    }

    /// One procedure-tree branch, opened by its ANAM type.
    public struct Branch: Equatable, Sendable {
        public let type: String
        public internal(set) var conditionList = ConditionList()
        /// PRCB root data.
        public internal(set) var branchCount: UInt32?
        /// PRCB flags: bit 0 repeat when complete.
        public internal(set) var rootFlags: UInt32?
        public internal(set) var procedureType: String?
        /// FNAM.
        public internal(set) var successCompletesPackage = false
        /// PKC2 — indexes into the template's data inputs.
        public internal(set) var dataInputIndexes: [UInt8] = []
        public internal(set) var flagsOverrides: [FlagsOverride] = []
        /// PFOR payloads, which xEdit leaves unexplained, kept raw.
        public internal(set) var unknownPFOR: [Data] = []

        public var conditions: [Condition] {
            conditionList.conditions
        }
    }

    /// A data input a template package declares: UNAM, BNAM, PNAM.
    public struct TemplateInput: Equatable, Sendable {
        public let index: Int8
        public internal(set) var name: String?
        public internal(set) var isPublic = false
    }

    /// PDTO. Kind 0 names a DIAL; kind 1 holds a four-character topic subtype.
    public struct TopicData: Equatable, Sendable {
        public let kind: UInt32
        public let value: UInt32

        public var topic: FormID? {
            kind == 0 ? FormID(value).nonNull : nil
        }
    }

    /// POBA, POEA, or POCA with the fields after it.
    public struct Event: Equatable, Sendable {
        public internal(set) var idle: FormID?
        public internal(set) var topic: TopicData?
        /// SCHR, SCDA, SCTX, QNAM, and TNAM left by older Creation Kit
        /// versions; xEdit marks them unused. Raw bytes, in file order.
        public internal(set) var legacyFields: [Data] = []
    }

    public internal(set) var idleAnimations: IdleAnimations?
    /// CNAM in the header — combat style.
    public internal(set) var combatStyle: FormID?
    /// QNAM in the header — the quest that owns the package.
    public internal(set) var ownerQuest: FormID?
    public internal(set) var branches: [Branch] = []
    public internal(set) var templateInputs: [TemplateInput] = []
    public internal(set) var onBegin: Event?
    public internal(set) var onEnd: Event?
    public internal(set) var onChange: Event?

    public init() {}
}

/// The PACK field walk for the members above. Each function returns false for
/// a field it does not read.
nonisolated extension PackageDetails {
    mutating func decodeHeader(_ field: ESMField) throws -> Bool {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "IDLF":
            idleAnimations = try IdleAnimations(flags: reader.readUInt8())
        case "IDLC":
            try editIdle { $0.declaredCount = try reader.readUInt8() }
        case "IDLT":
            try editIdle { $0.timer = try reader.readFloat32() }
        case "IDLA":
            try editIdle { idle in
                while reader.bytesRemaining >= 4 {
                    try idle.animations.append(reader.readFormID())
                }
            }
        case "CNAM":
            combatStyle = try reader.readFormID().nonNull
        case "QNAM":
            ownerQuest = try reader.readFormID().nonNull
        default:
            return false
        }
        return true
    }

    /// Procedure-tree branches, then the template's data inputs.
    mutating func decodeProcedureTree(_ field: ESMField) throws -> Bool {
        if field.type == "ANAM" {
            var reader = BinaryReader(field.data)
            try branches.append(Branch(type: reader.readZString()))
            return true
        }
        if field.type == "UNAM" || !templateInputs.isEmpty {
            return try decodeTemplateInput(field)
        }
        guard !branches.isEmpty else { return false }
        return try branches[branches.count - 1].decode(field)
    }

    /// A field after an event marker; `event` is the one the marker opened.
    static func decodeEvent(_ field: ESMField, into event: inout Event?) throws -> Bool {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "INAM":
            event?.idle = try reader.readFormID().nonNull
        case "PDTO":
            event?.topic = try TopicData(kind: reader.readUInt32(), value: reader.readUInt32())
        case "SCHR", "SCDA", "SCTX", "QNAM", "TNAM":
            event?.legacyFields.append(field.data)
        default:
            return false
        }
        return event != nil
    }

    private mutating func editIdle(_ edit: (inout IdleAnimations) throws -> Void) throws {
        var idle = idleAnimations ?? IdleAnimations()
        try edit(&idle)
        idleAnimations = idle
    }

    private mutating func decodeTemplateInput(_ field: ESMField) throws -> Bool {
        var reader = BinaryReader(field.data)
        switch field.type {
        case "UNAM":
            try templateInputs.append(TemplateInput(index: Int8(bitPattern: reader.readUInt8())))
        case "BNAM" where !templateInputs.isEmpty:
            templateInputs[templateInputs.count - 1].name = try reader.readZString()
        case "PNAM" where !templateInputs.isEmpty:
            templateInputs[templateInputs.count - 1].isPublic = try reader.readUInt32() != 0
        default:
            return false
        }
        return true
    }
}

nonisolated extension PackageDetails.Branch {
    fileprivate mutating func decode(_ field: ESMField) throws -> Bool {
        if try conditionList.decode(field: field) {
            return true
        }
        var reader = BinaryReader(field.data)
        switch field.type {
        case "PRCB":
            branchCount = try reader.readUInt32()
            rootFlags = try reader.readUInt32()
        case "PNAM":
            procedureType = try reader.readZString()
        case "FNAM":
            successCompletesPackage = try reader.readUInt32() != 0
        case "PKC2":
            try dataInputIndexes.append(reader.readUInt8())
        case "PFO2":
            try flagsOverrides.append(PackageDetails.FlagsOverride(
                setGeneralFlags: reader.readUInt32(),
                clearGeneralFlags: reader.readUInt32(),
                setInterruptFlags: reader.readUInt16(),
                clearInterruptFlags: reader.readUInt16(),
                preferredSpeed: reader.readUInt8()
            ))
        case "PFOR":
            unknownPFOR.append(field.data)
        default:
            return false
        }
        return true
    }
}
