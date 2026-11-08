public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `RiddenDragonOrders`.
public protocol RiddenDragonOrdersPort {
    var breath: DragonBreathPhase { get set }
    var breathCooldown: Float { get }
    var isAttacking: Bool { get set }
    var landingRequested: Bool { get set }
    var lockedTarget: ReferenceKey? { get }
    var switchedTarget: ReferenceKey? { get }
}
