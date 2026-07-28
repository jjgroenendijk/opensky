// Engine-owned interaction values (M8.4.1). The world publishes one
// view-ray target and emits a typed event when the use key activates it.
// UI and future Papyrus consumers subscribe without owning targeting rules.

import simd

nonisolated enum InteractionAction: Equatable, Sendable {
    case activate
    case open
    case search
    case harvest
    case use

    var defaultLabel: String {
        switch self {
        case .activate: "Activate"
        case .open: "Open"
        case .search: "Search"
        case .harvest: "Harvest"
        case .use: "Activate"
        }
    }
}

/// Immutable record metadata retained beside a streamed cell.
nonisolated struct PlacedInteraction: Equatable, Sendable {
    let reference: FormID
    let base: FormID
    let position: SIMD3<Float>
    let name: String
    let action: InteractionAction
    let actionLabel: String
    /// Sound links resolved off the base record (DOOR/ACTI/CONT) at cell-build
    /// time. Nil when the base carries no decoded sound fields. The audio
    /// director consumes `activation` on use-key events and `close`/`loop` on
    /// interaction-animation boundaries. They ride together so the cell build
    /// remains the single resolution point.
    let sounds: ModelBase.Sounds?
}

/// Current crosshair target. Distance and hit position come from exact
/// collision geometry rather than the placed reference's origin.
nonisolated struct InteractionTarget: Equatable, Sendable {
    let interaction: PlacedInteraction
    let hitPosition: SIMD3<Float>
    let distance: Float
}

/// One use-key activation. M11 Papyrus OnActivate can subscribe to this
/// engine event without changing the raycast or door transition path.
nonisolated struct InteractionEvent: Equatable, Sendable {
    let target: InteractionTarget
}

/// Motion lifecycle for an activated interaction.
///
/// Door transitions publish these phases today. A future rendered door or
/// container animation can publish the same event at its authored animation
/// boundaries without changing the audio director.
nonisolated enum InteractionAnimationPhase: Equatable, Sendable {
    case motionStarted
    case closed
    case cancelled
}

/// One animation boundary for a placed interaction. The whole placement rides
/// along because a scene transition may evict the source cell before the close
/// boundary fires.
nonisolated struct InteractionAnimationEvent: Equatable, Sendable {
    let interaction: PlacedInteraction
    let phase: InteractionAnimationPhase
}

/// Finite normalized world-space ray. A nil ray means the current camera mode
/// does not participate in interaction targeting (fly mode today).
nonisolated struct InteractionRay: Equatable, Sendable {
    static let defaultMaximumDistance: Float = 192

    let origin: SIMD3<Float>
    let direction: SIMD3<Float>
    let maximumDistance: Float

    init?(
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

    var bounds: ModelBounds {
        let end = origin + direction * maximumDistance
        let padding = SIMD3<Float>(repeating: 0.01)
        return ModelBounds(
            min: simd_min(origin, end) - padding,
            max: simd_max(origin, end) + padding
        )
    }
}

nonisolated struct InteractionRayHit: Equatable {
    let reference: FormID
    let position: SIMD3<Float>
    let distance: Float
}
