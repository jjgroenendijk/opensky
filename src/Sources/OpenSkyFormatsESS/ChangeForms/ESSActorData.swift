// The part of an actor's change data after its animation part, for an actor with no AI
// process. It holds the life state, the killer, and the actor values.
// See docs/formats/ess-change-forms.md#actor-data-after-the-animation-part.

import Foundation

/// One actor value's three modifiers, as the save keeps them.
nonisolated public struct ESSActorValueModifiers: Equatable, Sendable {
    public let permanent: Float
    public let temporary: Float
    /// Zero or below; below zero is damage the actor still carries.
    public let damage: Float

    public init(permanent: Float, temporary: Float, damage: Float) {
        self.permanent = permanent
        self.temporary = temporary
        self.damage = damage
    }
}

nonisolated public struct ESSActorData: Equatable, Sendable {
    /// 1 dying, 2 dead, 3 unconscious, 5 recycle, 7 essential down.
    public let lifeState: UInt8
    public let killer: ESSRefID
    /// Health, magicka, stamina, and voice, in that order.
    public let primaryValues: [ESSActorValueModifiers]

    /// The life states that mean the actor is dead.
    public static let deadLifeStates: Set<UInt8> = [1, 2, 5]

    public var isDead: Bool {
        Self.deadLifeStates.contains(lifeState)
    }

    public var health: ESSActorValueModifiers? {
        primaryValues.first
    }

    public init(lifeState: UInt8, killer: ESSRefID, primaryValues: [ESSActorValueModifiers]) {
        self.lifeState = lifeState
        self.killer = killer
        self.primaryValues = primaryValues
    }

    /// Reads up to the movement data. Returns why reading stopped, or nil when every
    /// byte was read.
    static func read(_ reader: inout ESSReader) throws(ESSError) -> (Self, blockedBy: String?) {
        // Unknown byte, 4 timers, action (12), emotion (8), crime and combat (12), weight.
        try reader.skip(1 + 16 + 12 + 8 + 12 + 4, "actor timers and state")
        let killer = try reader.refID("actor killer")
        _ = try reader.uint16("actor state")
        try reader.skip(2, "actor sit and fly state")
        let lifeState = try reader.uint8("actor life state")
        try reader.skip(2 + 9, "actor knock, attack, and flag bytes")
        _ = try reader.refID("actor support")
        try skipSpellCasters(&reader)
        for _ in 0 ..< 5 {
            _ = try reader.refID("actor selected spell")
        }
        var values: [ESSActorValueModifiers] = []
        for _ in 0 ..< 4 {
            _ = try reader.uint32("actor value modifier count")
            try values.append(ESSActorValueModifiers(
                permanent: reader.float32("actor value permanent"),
                temporary: reader.float32("actor value temporary"),
                damage: reader.float32("actor value damage")
            ))
        }
        let data = Self(lifeState: lifeState, killer: killer, primaryValues: values)
        return try (data, readRest(&reader))
    }

    private static func skipSpellCasters(_ reader: inout ESSReader) throws(ESSError) {
        let mask = try reader.uint8("actor caster mask")
        for bit in 0 ..< 4 where mask & (1 << bit) != 0 {
            try reader.skip(4, "caster")
            _ = try reader.refID("caster spell")
            try reader.skip(8, "caster")
            _ = try reader.refID("caster target")
            try reader.skip(8, "caster")
            _ = try reader.refID("caster")
            try reader.skip(4, "caster")
            try reader.skip(reader.count("caster data"), "caster data")
        }
    }

    /// The other actor values, the added spells, and the parts after them up to the
    /// first part with no known layout.
    private static func readRest(_ reader: inout ESSReader) throws(ESSError) -> String? {
        try reader.skip(reader.count("actor base values", minimumElementSize: 8) * 8, "base values")
        try reader.skip(reader.count("actor modifiers", minimumElementSize: 16) * 16, "modifiers")
        try reader.skip(reader.count32("added spells", minimumElementSize: 3) * 3, "added spells")
        if try reader.uint8("actor movement flag") != 0 {
            return "actor movement data"
        }
        _ = try reader.uint32("actor more flags")
        if try reader.uint8("actor combat flag") != 0 {
            return "actor combat data"
        }
        try reader.skip(reader.count32("spell pairs", minimumElementSize: 7) * 7, "spell pairs")
        try reader.skip(4 + 4, "bribe day and underwater timer")
        _ = try reader.refID("dialogue branch")
        _ = try reader.uint8("actor last flag")
        return reader.isAtEnd ? nil : "\(reader.bytesRemaining) unread bytes"
    }
}
