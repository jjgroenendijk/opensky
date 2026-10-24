// Engine-owned interaction values. The world publishes one
// view-ray target and emits a typed event when the use key activates it.
// UI and future Papyrus consumers subscribe without owning targeting rules.

import Foundation
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
    /// XLOC of a DOOR or CONT reference. The plugin baseline; the runtime may have unlocked it.
    public let lock: LockData?
    /// FURN markers in world space, in marker order. Empty for every other base.
    public var seats: [FurnitureSeat] = []
    /// An automatic DOOR's area; walking into it activates the door. Nil for other bases.
    public var automaticArea: AutomaticDoorArea?
    /// The base authors its own verb (`ACTI` `RNAM`), which the game's verbs never replace.
    public var hasLabelOverride = false

    /// A FURN with a sleep marker. Using it opens the rest menu.
    public var isBed: Bool {
        seats.contains { $0.animationType == FurnitureSeat.sleepAnimation }
    }

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
        produce: HarvestProduce? = nil,
        lock: LockData? = nil
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
        self.lock = lock
    }
}

/// The space an automatic door covers: its base's `OBND` box at the reference's pose.
nonisolated public struct AutomaticDoorArea: Equatable, Sendable {
    public let worldToLocal: simd_float4x4
    public let minimum: SIMD3<Float>
    public let maximum: SIMD3<Float>

    public init(worldToLocal: simd_float4x4, minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        self.worldToLocal = worldToLocal
        self.minimum = minimum
        self.maximum = maximum
    }

    public func contains(_ point: SIMD3<Float>) -> Bool {
        let local = worldToLocal * SIMD4(point, 1)
        let position = SIMD3(local.x, local.y, local.z)
        return all(position .>= minimum) && all(position .<= maximum)
    }
}

/// One place an actor uses a piece of furniture.
nonisolated public struct FurnitureSeat: Equatable, Sendable {
    public let position: SIMD3<Float>
    /// Where the user's root goes: the marker at the furniture's own height. A chair's
    /// marker sits on the seat, and its clips put the root on the floor.
    public let root: SIMD3<Float>
    /// The world z rotation the user faces, in the record's clockwise radians.
    public let heading: Float
    /// 1 sit, 2 sleep, 4 lean.
    public let animationType: UInt16
    public static let sitAnimation: UInt16 = 1
    public static let sleepAnimation: UInt16 = 2
    /// FURN `FNMK`: only an actor with this keyword may use the seat.
    public let keyword: FormID?
    /// The marker's entry bits less the record's `NAM0` ones: 1 front, 2 behind, 4 right,
    /// 8 left, 16 up.
    public var entryPoints: UInt16 = 0
    /// False when the record's `MNAM` leaves this mesh marker off; no one uses it.
    public var isEnabled = true

    /// How far from the marker a standing actor's feet go. OpenSky plays no exit
    /// clip, whose root motion would carry the actor out, so this stands in for it.
    public static let standDistance: Float = 48

    public init(
        position: SIMD3<Float>, heading: Float, animationType: UInt16, keyword: FormID?,
        entryPoints: UInt16 = 0, isEnabled: Bool = true, root: SIMD3<Float>? = nil
    ) {
        self.position = position
        self.root = root ?? position
        self.heading = heading
        self.animationType = animationType
        self.keyword = keyword
        self.entryPoints = entryPoints
        self.isEnabled = isEnabled
    }

    /// The world z rotation the camera uses to look the way the seat faces: the
    /// counter-clockwise yaw from +x of the marker's clockwise heading from +y.
    public var facingYaw: Float {
        Float.pi / 2 - heading
    }

    /// The one entry bit an actor at `point` uses: the allowed side that faces it most.
    /// Up is used only when no side is allowed. The game's own choice is not documented.
    public func entry(from point: SIMD3<Float>) -> UInt16 {
        let offset = SIMD2(point.x - position.x, point.y - position.y)
        let allowed = sides.filter { entryPoints & $0.bit != 0 }
        guard
            let best = allowed.max(by: {
                simd_dot($0.direction, offset) < simd_dot($1.direction, offset)
            })
        else { return entryPoints & 16 }
        return best.bit
    }

    /// Where an actor that entered by `entry` stands up: `standDistance` out on that
    /// side, or on the root for up or no side.
    public func standPoint(entry: UInt16) -> SIMD3<Float> {
        guard let side = sides.first(where: { $0.bit == entry }) else { return root }
        let step = side.direction * Self.standDistance
        return root + SIMD3(step.x, step.y, 0)
    }

    private var sides: [(bit: UInt16, direction: SIMD2<Float>)] {
        let forward = SIMD2(sin(heading), cos(heading))
        let right = SIMD2(forward.y, -forward.x)
        return [(1, forward), (2, -forward), (4, right), (8, -right)]
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

/// Why a use-key activation did not go through.
nonisolated public enum ActivationRefusal: Equatable, Sendable {
    /// The target is locked and the player has no key. `level` is the XLOC byte.
    case locked(level: UInt8, key: FormID?)
    /// A Filter Activation perk of the player blocks it.
    case filteredByPerk
    /// The player rides, and a rider cannot use a door.
    case mounted
}

/// A use-key press the activation gate refused. No `InteractionEvent` follows it.
nonisolated public struct ActivationRefusalEvent: Equatable, Sendable {
    public let target: InteractionTarget
    public let refusal: ActivationRefusal

    public init(target: InteractionTarget, refusal: ActivationRefusal) {
        self.target = target
        self.refusal = refusal
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
