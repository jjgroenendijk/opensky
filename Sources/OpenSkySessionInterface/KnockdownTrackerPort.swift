public import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `KnockdownTracker`.
public protocol KnockdownTrackerPort {
    func isKnockedDown(_ key: ReferenceKey) -> Bool
    var phases: [ReferenceKey: KnockdownPhase] { get }
}
