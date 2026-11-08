public import OpenSkyWorldInterface

/// What the world adapters use of `PlayerHealthCues`.
public protocol PlayerHealthCuesPort {
    var heartbeat: Heartbeat? { get }
    var lastPulseStrength: Float? { get }
    var pulseCount: Int { get }
    var pulseEnabled: Bool { get set }
    var pulsing: Bool { get }
}
