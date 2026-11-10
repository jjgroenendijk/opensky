// What a casting hand shows and sounds as pure rules. CK wiki "Magic Effect": the
// casting art is "on the hands while preparing to cast", and each MGEF sound kind plays
// at one step of the cast. The release waits for the hand's spell-fire event, as a
// shout waits for its exhale. See docs/engine/spellcasting.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyMagicInterface

/// MGEF `SNDD` sound kinds (UESP "Skyrim Mod:Mod File Format/MGEF").
nonisolated enum MagicEffectSoundKind: UInt32, Equatable, Sendable, CaseIterable {
    case drawSheathe = 0
    case charge = 1
    case ready = 2
    case release = 3
    case castLoop = 4
    case onHit = 5

    var name: String {
        switch self {
        case .drawSheathe: "Draw/Sheathe"
        case .charge: "Charge"
        case .ready: "Ready"
        case .release: "Release"
        case .castLoop: "Cast Loop"
        case .onHit: "On Hit"
        }
    }
}

/// One hand as the cue rule sees it on one frame.
nonisolated struct CastingHandView: Equatable, Sendable {
    var phase: SpellCastPhase = .idle
    /// The spell the hand is casting, nil while idle.
    var spell: ReferenceKey?
    var isDualCast = false
    /// The wiki gives Charge and Ready to fire-and-forget spells only.
    var isConcentration = false

    init(
        phase: SpellCastPhase = .idle, spell: ReferenceKey? = nil, isDualCast: Bool = false,
        isConcentration: Bool = false
    ) {
        self.phase = phase
        self.spell = spell
        self.isDualCast = isDualCast
        self.isConcentration = isConcentration
    }
}

/// One thing a casting hand starts or stops.
nonisolated struct CastingCue: Equatable, Sendable {
    enum What: Equatable, Sendable {
        case sound(MagicEffectSoundKind)
        /// The MGEF casting art, or its dual-cast art.
        case art(dual: Bool)
    }

    let what: What
    let starts: Bool
    let spell: ReferenceKey

    init(_ what: What, starts: Bool, spell: ReferenceKey) {
        self.what = what
        self.starts = starts
        self.spell = spell
    }
}

nonisolated enum CastingCueRule {
    /// The cues of one hand going from `old` to `new`. `cast` is the spell a release
    /// cast this frame, which the wiki's Release sound needs: "successfully casts".
    static func cues(
        from old: CastingHandView, to new: CastingHandView, cast: ReferenceKey?
    ) -> [CastingCue] {
        var cues: [CastingCue] = []
        let changed = old.phase != new.phase || old.spell != new.spell
        if changed, let spell = old.spell {
            if let kind = loopKind(of: old) {
                cues.append(CastingCue(.sound(kind), starts: false, spell: spell))
            }
            if old.phase.isCasting, !new.phase.isCasting || old.spell != new.spell {
                cues.append(CastingCue(.art(dual: old.isDualCast), starts: false, spell: spell))
            }
        }
        if let cast {
            cues.append(CastingCue(.sound(.release), starts: true, spell: cast))
        }
        if changed, let spell = new.spell {
            if let kind = loopKind(of: new) {
                cues.append(CastingCue(.sound(kind), starts: true, spell: spell))
            }
            if new.phase.isCasting, !old.phase.isCasting || old.spell != new.spell {
                cues.append(CastingCue(.art(dual: new.isDualCast), starts: true, spell: spell))
            }
        }
        return cues
    }

    /// "The sound that plays when the player draws or sheathes their weapons with this
    /// spell in either hand."
    static func drawCues(
        drawn old: Bool?, now new: Bool?, readied: [ReferenceKey]
    ) -> [CastingCue] {
        guard let old, let new, old != new else { return [] }
        return Set(readied).sorted()
            .map { CastingCue(.sound(.drawSheathe), starts: true, spell: $0) }
    }

    /// The sound a hand's phase holds while it lasts.
    static func loopKind(of hand: CastingHandView) -> MagicEffectSoundKind? {
        switch hand.phase {
        case .idle: nil
        case .charging: hand.isConcentration ? nil : .charge
        case .ready: .ready
        case .concentrating: .castLoop
        }
    }
}

/// The graph events a spell release waits for (`0_master.hkx` clips' annotations).
nonisolated public enum SpellFireGraphNames: Sendable {
    public static let left = "MLh_SpellFire_Event"
    public static let right = "MRh_SpellFire_Event"

    /// The staff release clips' spelling, with no hand: it releases the hand a staff holds.
    public static let staff = "Spellfire"

    public static let observedEvents = [left, right, staff]

    static func event(of hand: SpellHand) -> String {
        hand == .left ? left : right
    }
}

/// Holds a released fire-and-forget hand until its spell-fire event, so the spell
/// leaves when the hand is thrown forward.
nonisolated public struct SpellReleaseLatch: Equatable, Sendable {
    /// An OpenSky value: how long a release waits for a graph that raises nothing.
    static let fireWithoutGraphAfter: Float = 0.4

    public private(set) var waited: [SpellHand: Float] = [:]

    public init() {}

    public func isWaiting(_ hand: SpellHand) -> Bool {
        waited[hand] != nil
    }

    /// The hold the caster runtime gets for `hand`: still held while the release waits.
    mutating func hold(
        _ hand: SpellHand, state: (pressed: Bool, phase: SpellCastPhase), fired: Bool, delta: Float
    ) -> Bool {
        let (pressed, phase) = state
        if let wait = waited[hand] {
            let total = wait + max(0, delta)
            guard phase == .ready, !fired, total < Self.fireWithoutGraphAfter else {
                waited[hand] = nil
                return pressed && phase != .ready
            }
            waited[hand] = total
            return true
        }
        guard !pressed, phase == .ready else { return pressed }
        waited[hand] = 0
        return true
    }
}

/// One cast a release completed.
nonisolated struct CompletedCast: Equatable, Sendable {
    let slot: CastSlot
    let spell: ReferenceKey
}
