// How hard the player's walk pushes a body, by its mass and collision layer, as the
// game scales its character's contact push. See docs/engine/dynamic-bodies.md.

import OpenSkyFormatsMesh

nonisolated public enum PlayerPushFactor {
    /// Kilograms. A body this heavy, or with no mass, is not pushed.
    public static let heaviest: Float = 95
    /// A push never sets a body moving faster than this, in Havok units per second.
    public static let fastest: Float = 1000

    static let projectileLayer: UInt8 = 6
    static let propsLayer: UInt8 = 10
    static let trapLayer: UInt8 = 14

    /// The factor the push is multiplied by. `impulse` is in kilogram units per second.
    public static func factor(mass: Float, layer: UInt8, impulse: Float) -> Float {
        guard mass > 0, mass < heaviest else { return 0 }
        var factor: Float = switch layer {
        case projectileLayer: 0
        case propsLayer: mass > heaviest / 2 ? 0.1 : 3
        case trapLayer: 0.1
        default: 2
        }
        let speed = abs(impulse) / mass / NIFCollisionModel.havokToEngineScale
        if speed > fastest {
            factor *= fastest / speed
        }
        return factor
    }
}
