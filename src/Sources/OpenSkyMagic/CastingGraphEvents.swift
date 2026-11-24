// The behaviour graph events a casting hand raises, as pure rules: the start event that
// picks the clips, the ready event, and the release event. The clips then raise the
// spell-fire event. See docs/engine/casting-graph.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyMagicInterface

/// What the start event of a spell depends on.
nonisolated struct CastGraphSpell: Equatable, Sendable {
    var castingType: MagicEffectCastingType
    var delivery: MagicEffectDelivery
    /// The main effect has the `MagicWard` keyword.
    var isWard = false
    /// The main effect has the `MagicTelekinesis` keyword.
    var isTelekinesis = false

    /// The start event after the hand's prefix, or nil when the spell has none.
    var startEvent: String? {
        let isSelf = delivery == .selfTarget
        let isAimed = delivery == .aimed || delivery == .targetActor
            || delivery == .targetLocation
        switch castingType {
        case .fireAndForget:
            if isSelf {
                return "SpellSelfStart"
            }
            return isAimed ? "SpellAimedStart" : nil
        case .concentration:
            if isSelf {
                if isTelekinesis {
                    return "SpellTelekinesisStart"
                }
                return isWard ? "WardStart" : "SpellSelfConcentrationStart"
            }
            return isAimed ? "SpellAimedConcentrationStart" : nil
        default:
            return nil
        }
    }
}

/// The graph variable and event names of a cast.
nonisolated public enum CastingGraphNames: Sendable {
    public static let wantCastLeft = "bWantCastLeft"
    public static let wantCastRight = "bWantCastRight"
    static let dualPrefix = "DualMagic_"
    static let ready = "SpellReady_Event"
    static let release = "SpellRelease_Event"

    static func prefix(of hand: SpellHand) -> String {
        hand == .left ? "MLh_" : "MRh_"
    }

    static func wantCast(_ hand: SpellHand) -> String {
        hand == .left ? wantCastLeft : wantCastRight
    }
}

/// One hand's cast as the graph event rule sees it on one frame.
nonisolated struct CastingGraphHand: Equatable, Sendable {
    var phase: SpellCastPhase = .idle
    var spell: ReferenceKey?
    /// The start event after the prefix, nil for a spell that has none.
    var start: String?
    var isConcentration = false
    /// The hand leads a dual cast. The partner raises nothing.
    var isDualLead = false
    var isDualPartner = false
    /// A fire-and-forget release waits for its spell-fire event.
    var isReleasing = false
}

nonisolated enum CastingGraphEventRule {
    /// The events `hand` raises going from `old` to `new`, without the start event,
    /// which `start(of:from:to:)` gives a step later. `cast` is true when a release
    /// cast the spell this frame without waiting for an event, as an NPC's does.
    static func events(
        _ hand: SpellHand, from old: CastingGraphHand, to new: CastingGraphHand, cast: Bool
    ) -> [String] {
        let sameCast = old.spell == new.spell || old.phase == .idle || new.phase == .idle
        guard !new.isDualPartner, !old.isDualPartner, sameCast else { return [] }
        let prefix = CastingGraphNames.prefix(of: new.isDualLead ? .left : hand)
        var events: [String] = []
        if old.phase == .charging, new.phase == .ready || new.phase == .concentrating {
            events.append(prefix + (new.isConcentration
                    ? CastingGraphNames.release : CastingGraphNames.ready))
        }
        let released = new.isReleasing && !old.isReleasing
            || cast && !old.isReleasing && !old.isConcentration
        if released {
            events.append(prefix + CastingGraphNames.release)
        }
        return events
    }

    /// Whether a start queued a step ago still goes out: the hand still casts, and a hand
    /// that joined a dual cast since then raises only the dual start.
    static func startStillHolds(_ event: String, phase: SpellCastPhase, dual: Bool) -> Bool {
        phase.isCasting && (!dual || event.hasPrefix(CastingGraphNames.dualPrefix))
    }

    /// The events right after a start event. A concentration hand with no charge time is
    /// ready, or for an NPC already concentrating, at once. Its release must follow the
    /// start that picks its clips.
    static func afterStart(_ hand: SpellHand, state: CastingGraphHand) -> [String] {
        guard
            state.isConcentration, state.phase == .ready || state.phase == .concentrating,
            !state.isDualPartner
        else { return [] }
        return [CastingGraphNames.prefix(of: state.isDualLead ? .left : hand)
            + CastingGraphNames.release]
    }

    /// The start event a hand that began a cast, or joined a dual cast as its lead,
    /// raises. Nil when nothing began.
    static func start(
        of hand: SpellHand, from old: CastingGraphHand, to new: CastingGraphHand
    ) -> String? {
        guard new.phase.isCasting, !new.isDualPartner, let start = new.start else { return nil }
        if new.isDualLead, !old.isDualLead {
            guard start != "SpellTelekinesisStart" else { return nil }
            return CastingGraphNames.dualPrefix + start
        }
        guard old.phase == .idle || old.spell != new.spell else { return nil }
        return CastingGraphNames.prefix(of: hand) + start
    }
}
