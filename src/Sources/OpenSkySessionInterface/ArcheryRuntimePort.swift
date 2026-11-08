public import OpenSkyCombatInterface

/// What the world adapters use of `ArcheryRuntime`.
public protocol ArcheryRuntimePort: AnyObject {
    associatedtype ProjectileRuntime: ProjectileRuntimePort
    var projectiles: ProjectileRuntime { get }
    var settings: ArcherySettings { get }

    var zoom: BowZoom { get }

    var state: ArcheryState { get }
}
