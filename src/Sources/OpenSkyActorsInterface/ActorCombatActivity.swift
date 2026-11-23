// Combat values that actor state, conditions, and scripts read about any actor.

/// What one actor is doing about a fight, as `GetCombatState` spells it.
///
/// Three cases because the Creation Kit wiki documents three returns, and 16.7
/// is what makes the third reachable: an actor that lost its target and is
/// looking for it is neither out of combat nor fighting.
nonisolated public enum ActorCombatActivity: UInt8, Equatable, Sendable, CaseIterable {
    /// Not fighting. `GetCombatState` 0.
    ///
    /// Spelled `notFighting` rather than `none`, because `.none` on an
    /// `Optional` of this type would mean "no answer" and read identically at
    /// every call site that chains through one.
    case notFighting = 0
    /// Fighting. `GetCombatState` 1.
    case fighting = 1
    /// Searching for a target it lost. `GetCombatState` 2.
    case searching = 2
}

/// Where the weapon is. `drawing` and `sheathing` last until the clip reaches
/// `BeginWeaponDraw` or `BeginWeaponSheathe`. The weapon is on the hand node for
/// `drawn` and `sheathing`, and on the sheathed node otherwise.
nonisolated public enum WeaponDrawState: String, Equatable, Sendable, CaseIterable {
    case sheathed
    case drawing
    case drawn
    case sheathing

    /// Whether the attachment rides the hand node in this state.
    public var isWeaponInHand: Bool {
        self == .drawn || self == .sheathing
    }

    /// Whether a swing is allowed to start. Vanilla will not attack from a
    /// sheathed weapon; it draws first, which is the engine's job to sequence
    /// and not this type's.
    public var canAttack: Bool {
        self == .drawn
    }

    /// The state of an NPC nobody tracks a draw for: it holds its weapon while it fights
    /// or searches, and has it away otherwise.
    public static func ofNPC(_ activity: ActorCombatActivity) -> WeaponDrawState {
        activity == .notFighting ? .sheathed : .drawn
    }
}

/// An NPC's weapon over time. It draws when a fight or a search starts, and sheathes
/// when that ends. See docs/engine/condition-functions-world.md#combat-actions.
nonisolated public struct NPCWeaponDraw: Equatable, Sendable {
    /// How long a draw or a sheathe lasts. OpenSky's choice (docs/engine/unverified-values.md).
    public static let transitionSeconds: Float = 0.5
    /// The longest a graph that still plays its equip clip holds the draw past
    /// `transitionSeconds`, so a graph stuck in it cannot stop the fight. OpenSky's choice.
    public static let longestGraphHoldSeconds: Float = 2

    public private(set) var state = WeaponDrawState.sheathed
    private var left: Float = 0

    public init() {}

    /// One step. `wantsDrawn` is true while the actor fights or searches. A draw that is
    /// called off goes back to sheathed, and a sheathe that is called off to drawn.
    /// `graphEquipping` holds a draw until the actor's graph ends its equip clip.
    public mutating func advance(
        wantsDrawn: Bool,
        by seconds: Float,
        graphEquipping: Bool = false
    ) {
        switch state {
        case .sheathed:
            if wantsDrawn {
                begin(.drawing)
            }
        case .drawn:
            if !wantsDrawn {
                begin(.sheathing)
            }
        case .drawing:
            finish(
                wantsDrawn ? .drawn : nil, else: .sheathed, after: seconds,
                holding: graphEquipping
            )
        case .sheathing:
            finish(wantsDrawn ? nil : .sheathed, else: .drawn, after: seconds)
        }
    }

    private mutating func begin(_ next: WeaponDrawState) {
        state = next
        left = Self.transitionSeconds
    }

    private mutating func finish(
        _ end: WeaponDrawState?, else calledOff: WeaponDrawState, after seconds: Float,
        holding: Bool = false
    ) {
        guard let end else {
            state = calledOff
            return
        }
        left -= max(seconds, 0)
        if left <= 0, !holding || left <= -Self.longestGraphHoldSeconds {
            state = end
        }
    }
}
