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

    public var displayName: String {
        switch self {
        case .notFighting: "not in combat"
        case .fighting: "in combat"
        case .searching: "searching"
        }
    }
}

/// Where the weapon is.
///
/// `drawing` and `sheathing` are the interim states between the engine raising
/// the event and the clip reaching the annotation that actually moves the
/// model. The attachment is on the hand node for `drawn` and `sheathing`, and
/// on the sheathed node for `sheathed` and `drawing`: the weapon stays where it
/// was until `BeginWeaponDraw` or `BeginWeaponSheathe` says the hand has
/// reached it.
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
}
