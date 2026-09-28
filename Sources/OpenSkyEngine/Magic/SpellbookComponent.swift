// One actor's spell bookkeeping as a world-state component (issue #470,
// roadmap item 19.7): which spells it knows, which tomes it has read, which
// spell is readied in each hand, and which greater powers it has already spent
// today.
//
// ## Why the four travel in one slot
//
// `ActiveEffectState` is a slot of its own beside `actorValues` because the two
// have different lifetimes — a current-health float is rewritten sixty times a
// second while an effect list changes on an event. Everything here is on the
// event side of that line: learning a spell, reading a tome, readying a hand
// and spending a power are all things a player action does and nothing does per
// frame, so splitting them across slots would buy no write locality.
//
// The stronger reason is an invariant one component can enforce and two cannot:
// a readied hand must name a spell the actor knows. Forgetting a spell that is
// in a hand has to clear that hand in the same write, and a save whose load
// order no longer carries the readied spell has to drop the hand rather than
// leave it pointing at nothing. `init` is where both happen, which is also what
// makes this type the save decoder's entry point — the same role
// `ActiveEffectState.init` plays for `AEFF`.
//
// The component is dropped entirely once it empties, so an actor that knows no
// spells stops being dirty for this slot.
//
// Documented in docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Which hand a spell is readied in.
///
/// Two cases rather than a `HandSlots` because a hand slot is a set and a
/// readied spell goes into exactly one named hand; a spell that fills both
/// hands is one entry occupying both, which `SpellbookState` stores by writing
/// the same key into each hand.
///
/// The raw values are the save encoding and must not be renumbered.
nonisolated public enum SpellHand: UInt8, CaseIterable, Hashable, Sendable {
    case left = 0
    case right = 1

    /// The equipment-layer slot this hand is, so a spell and a weapon are
    /// arbitrated against the same occupancy value.
    public var slots: HandSlots {
        switch self {
        case .left: .leftHand
        case .right: .rightHand
        }
    }

    public var describedName: String {
        switch self {
        case .left: "left hand"
        case .right: "right hand"
        }
    }
}

/// One actor's known spells, read tomes, readied hands and spent powers.
nonisolated public struct SpellbookState: WorldStateComponent, Sendable {
    /// SPEL records the actor knows, in ascending key order. Ordered rather
    /// than a set so the save writes the same bytes twice for the same state.
    public private(set) var known: [ReferenceKey]
    /// BOOK records the actor has already opened, in ascending key order.
    ///
    /// This is the "already read" mark UESP records on the BOOK DATA flag byte:
    /// "0x08 - Read ([verification needed] not used in static game data, flag in
    /// save game data for already read books?)"
    /// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/BOOK>). The source
    /// carries its own hedge and so does this: the mark is per reader here,
    /// because it is what stops a second reading of the same tome teaching a
    /// spell twice, and per-reader is the only reading that survives an NPC
    /// picking the book up.
    public private(set) var readBooks: [ReferenceKey]
    public private(set) var leftHand: ReferenceKey?
    public private(set) var rightHand: ReferenceKey?
    /// Whole game days on which a greater power was last used, keyed by the
    /// power. UESP: "Each Greater Power can only be used once per game day"
    /// (<https://en.uesp.net/wiki/Skyrim:Powers>).
    public private(set) var powerDays: [ReferenceKey: Int32]

    public static var componentKind: WorldStateComponentKind {
        .spellbook
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point: a file written under a different load order degrades into a
    /// valid spellbook rather than failing the whole load.
    ///
    /// Duplicates collapse, order becomes the key order, and a hand naming a
    /// spell that is not known is cleared — including the case where the spell
    /// was never known and the case where it was forgotten in the same write.
    /// A spent-power day for a spell that is not known is dropped for the same
    /// reason: nothing can ever consult it again.
    public init(
        known: [ReferenceKey] = [],
        readBooks: [ReferenceKey] = [],
        leftHand: ReferenceKey? = nil,
        rightHand: ReferenceKey? = nil,
        powerDays: [ReferenceKey: Int32] = [:]
    ) {
        let knownSet = Set(known)
        self.known = knownSet.sorted()
        self.readBooks = Set(readBooks).sorted()
        self.leftHand = leftHand.flatMap { knownSet.contains($0) ? $0 : nil }
        self.rightHand = rightHand.flatMap { knownSet.contains($0) ? $0 : nil }
        self.powerDays = powerDays.filter { knownSet.contains($0.key) }
    }

    /// True when nothing is recorded at all, which is when the store drops the
    /// slot rather than keeping an empty component around.
    public var isEmpty: Bool {
        known.isEmpty && readBooks.isEmpty && powerDays.isEmpty
    }

    // MARK: - Queries

    public func knows(_ spell: ReferenceKey) -> Bool {
        known.contains(spell)
    }

    public func hasRead(_ book: ReferenceKey) -> Bool {
        readBooks.contains(book)
    }

    /// The spell readied in `hand`, or nil when that hand holds no spell.
    public func spell(in hand: SpellHand) -> ReferenceKey? {
        switch hand {
        case .left: leftHand
        case .right: rightHand
        }
    }

    /// The hands `spell` currently occupies — both when it is a two-handed
    /// spell readied in each, and `[]` when it is not readied at all.
    public func hands(of spell: ReferenceKey) -> HandSlots {
        var hands = HandSlots()
        if leftHand == spell {
            hands.insert(.leftHand)
        }
        if rightHand == spell {
            hands.insert(.rightHand)
        }
        return hands
    }

    /// Every hand currently holding a spell, whichever spell it is. What the
    /// item side asks before equipping something that takes a hand.
    public var occupiedHands: HandSlots {
        var hands = HandSlots()
        if leftHand != nil {
            hands.insert(.leftHand)
        }
        if rightHand != nil {
            hands.insert(.rightHand)
        }
        return hands
    }

    /// Whether `power` has already been spent on whole game day `day`.
    public func hasSpentPower(_ power: ReferenceKey, onDay day: Int32) -> Bool {
        powerDays[power] == day
    }

    // MARK: - Mutations

    public func learning(_ spell: ReferenceKey) -> SpellbookState {
        guard !knows(spell) else { return self }
        return copy(known: known + [spell])
    }

    /// This state without `spell`, and without it in either hand — the same
    /// write, because a hand pointing at a spell the actor no longer knows is
    /// the one state this type refuses to hold.
    public func forgetting(_ spell: ReferenceKey) -> SpellbookState {
        guard knows(spell) else { return self }
        return copy(known: known.filter { $0 != spell })
    }

    public func markingRead(_ book: ReferenceKey) -> SpellbookState {
        guard !hasRead(book) else { return self }
        return copy(readBooks: readBooks + [book])
    }

    /// This state with `spell` readied in `hands`, and every hand it takes
    /// cleared of whatever was there.
    ///
    /// Takes a `HandSlots` rather than a `SpellHand` because a two-handed spell
    /// fills both at once and doing that as two writes would leave a state
    /// where the same spell is in one hand and something else is in the other.
    public func equipping(_ spell: ReferenceKey, in hands: HandSlots) -> SpellbookState {
        guard knows(spell), !hands.isEmpty else { return self }
        return copy(
            leftHand: hands.contains(.leftHand) ? spell : leftHand,
            rightHand: hands.contains(.rightHand) ? spell : rightHand
        )
    }

    /// This state with `hands` emptied of whatever spell was readied in them.
    public func unequipping(_ hands: HandSlots) -> SpellbookState {
        copy(
            leftHand: hands.contains(.leftHand) ? nil : leftHand,
            rightHand: hands.contains(.rightHand) ? nil : rightHand
        )
    }

    /// This state with `power` marked spent on whole game day `day`.
    public func spendingPower(_ power: ReferenceKey, onDay day: Int32) -> SpellbookState {
        var days = powerDays
        days[power] = day
        return copy(powerDays: days)
    }

    /// Rebuilds with the given overrides. Every mutation routes through here so
    /// the normalizing `init` runs on every stored value, which is what keeps
    /// the readied-hand invariant true after a forget.
    ///
    /// `leftHand` and `rightHand` are double optionals so "leave it alone" and
    /// "clear it" stay distinguishable.
    private func copy(
        known: [ReferenceKey]? = nil,
        readBooks: [ReferenceKey]? = nil,
        leftHand: ReferenceKey?? = nil,
        rightHand: ReferenceKey?? = nil,
        powerDays: [ReferenceKey: Int32]? = nil
    ) -> SpellbookState {
        SpellbookState(
            known: known ?? self.known,
            readBooks: readBooks ?? self.readBooks,
            leftHand: leftHand ?? self.leftHand,
            rightHand: rightHand ?? self.rightHand,
            powerDays: powerDays ?? self.powerDays
        )
    }
}

nonisolated extension WorldStateComponentKind {
    /// One actor's known spells, read tomes, readied hands and spent greater
    /// powers. A slot of its own for the reason `activeEffects` is one: everything
    /// in it changes on a player action, never per frame. The four fields share the
    /// slot rather than splitting further because a readied hand must name a known
    /// spell, and only one component can enforce that in a single write.
    public static let spellbook = Self(rawValue: "spellbook", order: 13)
}

nonisolated extension WorldStateComponentValue {
    public static func spellbook(_ value: SpellbookState) -> Self {
        Self(value)
    }
}
