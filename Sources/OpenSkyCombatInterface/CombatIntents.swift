/// One frame of archery intent. Filled beside `MeleeIntent` from the same
/// drained camera input, because it is the same button: with a bow equipped the
/// attack press draws instead of swinging.
nonisolated public struct ArcheryIntent: Equatable, Sendable {
    /// Attack button held. A level, not an edge — a bow is drawn for as long as
    /// it is held, which is what the draw-time damage curve measures.
    public var drawing = false
    /// Whether a bow is what is equipped. False routes the same button to
    /// melee and leaves this runtime idle.
    public var hasBowEquipped = false
    /// Seconds since the previous frame, for the hold clock.
    public var deltaTime: Float = 0

    public static let still = ArcheryIntent()

    public init(drawing: Bool = false, hasBowEquipped: Bool = false, deltaTime: Float = 0) {
        self.drawing = drawing
        self.hasBowEquipped = hasBowEquipped
        self.deltaTime = deltaTime
    }
}

/// One frame of melee intent, filled from the drained camera input beside
/// `LocomotionIntent` and held across the fixed steps that frame drives.
nonisolated public struct MeleeIntent: Equatable, Sendable {
    /// One attack press, consumed by the first step that can act on it.
    public var attack = false
    /// Block key held. A level, not an edge, exactly like sprint.
    public var block = false
    /// One draw/sheath press, consumed the same way as an attack.
    public var toggleWeaponDrawn = false

    public static let still = MeleeIntent()

    public init(attack: Bool = false, block: Bool = false, toggleWeaponDrawn: Bool = false) {
        self.attack = attack
        self.block = block
        self.toggleWeaponDrawn = toggleWeaponDrawn
    }
}
