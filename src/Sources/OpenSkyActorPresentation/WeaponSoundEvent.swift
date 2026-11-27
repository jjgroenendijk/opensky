// The animation events that make a held weapon sound: draw, sheathe, swing, and the end of
// an attack, which stops the attack loop. See docs/formats/item-records.md (WEAP).

public import OpenSkyFormatsESM

/// An animation event that plays or stops a sound of the source's held weapon.
nonisolated public enum WeaponSoundEvent: Equatable, Sendable {
    case draw
    case sheathe
    case swing(leftHand: Bool)
    case attackEnd

    /// The event `name` stands for, compared without case. Nil for any other name.
    public init?(_ name: String) {
        switch name.lowercased() {
        case "beginweapondraw": self = .draw
        case "beginweaponsheathe": self = .sheathe
        case "weaponswing": self = .swing(leftHand: false)
        case "weaponleftswing": self = .swing(leftHand: true)
        case "attackstop": self = .attackEnd
        default: return nil
        }
    }

    /// The hand whose weapon sounds.
    public var isLeftHand: Bool {
        self == .swing(leftHand: true)
    }

    /// The one-shot sound the event plays from `weapon`. A swing also starts the attack loop.
    public func sound(of weapon: WeaponDetails) -> FormID? {
        switch self {
        case .draw: weapon.drawSound
        case .sheathe: weapon.sheatheSound
        case .swing: weapon.swingSound
        case .attackEnd: nil
        }
    }
}
