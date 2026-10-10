// CSTY combat style: the weights an actor's combat AI uses. Every block is a
// run of floats that may stop early, so each one keeps the floats present.
// Layout and sources: docs/formats/combat-style.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct CombatStyle: Equatable, Sendable {
    /// CSGD members, in file order.
    nonisolated public enum General: Int, CaseIterable, Sendable {
        case offensiveMultiplier, defensiveMultiplier, groupOffensiveMultiplier
        case meleeScoreMultiplier, magicScoreMultiplier, rangedScoreMultiplier
        case shoutScoreMultiplier, unarmedScoreMultiplier, staffScoreMultiplier
        case avoidThreatChance
    }

    /// CSME members, in file order.
    nonisolated public enum Melee: Int, CaseIterable, Sendable {
        case attackStaggeredMultiplier, powerAttackStaggeredMultiplier
        case powerAttackBlockingMultiplier, bashMultiplier, bashRecoilMultiplier
        case bashAttackMultiplier, bashPowerAttackMultiplier, specialAttackMultiplier
    }

    /// CSCR members, in file order.
    nonisolated public enum CloseRange: Int, CaseIterable, Sendable {
        case circleMultiplier, fallbackMultiplier, flankDistance, stalkTime
    }

    /// CSFL members, in file order.
    nonisolated public enum Flight: Int, CaseIterable, Sendable {
        case hoverChance, diveBombChance, groundAttackChance, hoverTime
        case groundAttackTime, perchAttackChance, perchAttackTime, flyingAttackChance
    }

    public let formID: FormID
    public let editorID: String?
    public let general: [Float]
    public let melee: [Float]
    public let closeRange: [Float]
    /// CSLR, the strafe multiplier.
    public let strafeMultiplier: Float?
    public let flight: [Float]
    /// DATA: 0x01 dueling, 0x02 flanking, 0x04 allow dual wielding.
    public let flags: UInt32?
    /// CSMD. xEdit leaves it unnamed.
    public let unknownCSMD: Data?
    /// Header flag 0x80000 (bit 19), the older dual-wield switch.
    public let allowsDualWieldingByHeader: Bool
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        var fields = try RecordFields(record: record, type: "CSTY")
        formID = fields.formID
        editorID = fields.editorID()
        general = fields.read("CSGD") { try Self.floats(&$0) } ?? []
        unknownCSMD = fields.bytes("CSMD")
        melee = fields.read("CSME") { try Self.floats(&$0) } ?? []
        closeRange = fields.read("CSCR") { try Self.floats(&$0) } ?? []
        strafeMultiplier = fields.float("CSLR")
        flight = fields.read("CSFL") { try Self.floats(&$0) } ?? []
        flags = fields.uint32("DATA")
        allowsDualWieldingByHeader = record.flags.rawValue & 0x80000 != 0
        skipped = fields.finish()
    }

    public func value(_ member: General) -> Float? {
        member.rawValue < general.count ? general[member.rawValue] : nil
    }

    public func value(_ member: Melee) -> Float? {
        member.rawValue < melee.count ? melee[member.rawValue] : nil
    }

    public func value(_ member: CloseRange) -> Float? {
        member.rawValue < closeRange.count ? closeRange[member.rawValue] : nil
    }

    public func value(_ member: Flight) -> Float? {
        member.rawValue < flight.count ? flight[member.rawValue] : nil
    }

    private static func floats(_ reader: inout BinaryReader) throws -> [Float] {
        var values: [Float] = []
        while reader.bytesRemaining >= 4 {
            try values.append(reader.readFloat32())
        }
        return values
    }
}
