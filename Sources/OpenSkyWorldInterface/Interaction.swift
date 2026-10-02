// Engine-owned interaction values. The world publishes one
// view-ray target and emits a typed event when the use key activates it.
// UI and future Papyrus consumers subscribe without owning targeting rules.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd

nonisolated public enum InteractionAction: Equatable, Sendable {
    case activate
    case open
    case search
    case harvest
    case use
    /// A loose world item: activating it moves the reference's stack into the
    /// activator's inventory and removes the reference. The item's
    /// FULL name rides on `PlacedInteraction.name` as it does for every other
    /// action, so the HUD prompt reads "Take Iron Sword" from the same
    /// label-plus-name composition every action uses.
    case take
    /// A living actor the player can start a conversation with.
    /// Unlike every other action here the target is not a placed object with
    /// collision geometry; `TalkTargeting` picks it off the same view ray
    /// against actor capsules, and `CellStreamer` publishes it through the same
    /// `InteractionTarget` so the crosshair, the prompt and the compass marker
    /// need no second path.
    case talk

    public var defaultLabel: String {
        switch self {
        case .activate: "Activate"
        case .open: "Open"
        case .search: "Search"
        case .harvest: "Harvest"
        case .use: "Activate"
        case .take: "Take"
        // "Talk to <name>" rather than "Talk <name>", which is the one label
        // here whose wording is OpenSky's: the prompt is composed as label plus
        // name for every action, and nothing measured out of the install says
        // what the vanilla HUD writes for an actor.
        case .talk: "Talk to"
        }
    }
}

/// Immutable record metadata retained beside a streamed cell.
nonisolated public struct PlacedInteraction: Equatable, Sendable {
    public let reference: FormID
    public let base: FormID
    public let position: SIMD3<Float>
    public let name: String
    public let action: InteractionAction
    public let actionLabel: String
    /// Sound links resolved off the base record (DOOR/ACTI/CONT) at cell-build
    /// time. Nil when the base carries no decoded sound fields. The audio
    /// director consumes `activation` on use-key events and `close`/`loop` on
    /// interaction-animation boundaries. They ride together so the cell build
    /// remains the single resolution point.
    public let sounds: ModelBase.Sounds?
    /// TACT VNAM, carried to the talk event. Nil for every other base.
    public let voiceType: FormID?
    /// FURN workbench data. Nil for every other base and for a FURN without `WBDT`.
    public let station: CraftingStation?
    /// FLOR and TREE produce. Nil for every other base.
    public let produce: HarvestProduce?

    public init(
        reference: FormID,
        base: FormID,
        position: SIMD3<Float>,
        name: String,
        action: InteractionAction,
        actionLabel: String,
        sounds: ModelBase.Sounds?,
        voiceType: FormID? = nil,
        station: CraftingStation? = nil,
        produce: HarvestProduce? = nil
    ) {
        self.reference = reference
        self.base = base
        self.position = position
        self.name = name
        self.action = action
        self.actionLabel = actionLabel
        self.sounds = sounds
        self.voiceType = voiceType
        self.station = station
        self.produce = produce
    }
}

/// Current crosshair target. Distance and hit position come from exact
/// collision geometry rather than the placed reference's origin.
nonisolated public struct InteractionTarget: Equatable, Sendable {
    public let interaction: PlacedInteraction
    public let hitPosition: SIMD3<Float>
    public let distance: Float

    public init(interaction: PlacedInteraction, hitPosition: SIMD3<Float>, distance: Float) {
        self.interaction = interaction
        self.hitPosition = hitPosition
        self.distance = distance
    }
}

/// One use-key activation. Papyrus `OnActivate` subscribes to this event.
nonisolated public struct InteractionEvent: Equatable, Sendable {
    public let target: InteractionTarget

    public init(target: InteractionTarget) {
        self.target = target
    }
}

/// One use-key activation of an actor or a talking activator: the event the
/// dialogue menu opens on. It carries the speaker's session-stable
/// `ReferenceKey`, which dialogue and saves key off. The plain
/// `InteractionEvent` is still published beside it.
nonisolated public struct TalkActivationEvent: Equatable, Sendable {
    /// The actor or TACT reference being spoken to.
    public let speaker: ReferenceKey
    /// The TACT base's VNAM. Nil for an actor, whose voice comes from its NPC_.
    public let voiceType: FormID?

    public init(speaker: ReferenceKey, voiceType: FormID? = nil) {
        self.speaker = speaker
        self.voiceType = voiceType
    }

    /// The event a use-key press on `interaction` raises, or nil when it is not a talk.
    /// A picked actor names itself. A TACT is a placed object, so its key comes from
    /// the resident reference, and its voice type rides along.
    public init?(
        interaction: PlacedInteraction,
        pickedSpeaker: ReferenceKey?,
        placedKey: () -> ReferenceKey?
    ) {
        guard interaction.action == .talk else { return nil }
        if let pickedSpeaker {
            self.init(speaker: pickedSpeaker)
            return
        }
        guard let key = placedKey() else { return nil }
        self.init(speaker: key, voiceType: interaction.voiceType)
    }
}

/// Motion lifecycle for an activated interaction.
///
/// Door transitions publish these phases today. A future rendered door or
/// container animation can publish the same event at its authored animation
/// boundaries without changing the audio director.
nonisolated public enum InteractionAnimationPhase: Equatable, Sendable {
    case motionStarted
    case closed
    case cancelled
}

/// One animation boundary for a placed interaction. The whole placement rides
/// along because a scene transition may evict the source cell before the close
/// boundary fires.
nonisolated public struct InteractionAnimationEvent: Equatable, Sendable {
    public let interaction: PlacedInteraction
    public let phase: InteractionAnimationPhase

    public init(interaction: PlacedInteraction, phase: InteractionAnimationPhase) {
        self.interaction = interaction
        self.phase = phase
    }
}

/// Finite normalized world-space ray. A nil ray means the current camera mode
/// does not participate in interaction targeting (fly mode today).
nonisolated public struct InteractionRay: Equatable, Sendable {
    public static let defaultMaximumDistance: Float = 192

    public let origin: SIMD3<Float>
    public let direction: SIMD3<Float>
    public let maximumDistance: Float

    public init?(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        maximumDistance: Float = defaultMaximumDistance
    ) {
        let length = simd_length(direction)
        guard length.isFinite, length > 1e-6, maximumDistance.isFinite, maximumDistance > 0 else {
            return nil
        }
        self.origin = origin
        self.direction = direction / length
        self.maximumDistance = maximumDistance
    }

    public var bounds: ModelBounds {
        let end = origin + direction * maximumDistance
        let padding = SIMD3<Float>(repeating: 0.01)
        return ModelBounds(
            min: simd_min(origin, end) - padding,
            max: simd_max(origin, end) + padding
        )
    }
}

nonisolated public struct InteractionRayHit: Equatable, Sendable {
    public let reference: FormID
    public let position: SIMD3<Float>
    public let distance: Float

    public init(reference: FormID, position: SIMD3<Float>, distance: Float) {
        self.reference = reference
        self.position = position
        self.distance = distance
    }
}
