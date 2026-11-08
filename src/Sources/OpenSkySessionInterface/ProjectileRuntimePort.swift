public import OpenSkyCombatInterface
public import OpenSkyFormatsESM

/// What the world adapters use of `ProjectileRuntime`.
public protocol ProjectileRuntimePort: AnyObject {
    associatedtype MeleeImpactResolver: MeleeImpactResolverPort
    @discardableResult func fire(
        _ shot: ProjectileShot,
        from shooter: ProjectileShooter
    ) -> LiveProjectile?
    var impacts: MeleeImpactResolver? { get }
    var live: [LiveProjectile] { get }
    @discardableResult func removeArrows(stuckIn host: FormID) -> Int
}
