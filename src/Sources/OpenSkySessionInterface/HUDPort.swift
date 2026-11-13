public import OpenSkyGameData
public import OpenSkyMenusInterface
public import OpenSkyWorldInterface

/// What the world adapters use of `HUDCoordinator`.
public protocol HUDPort: AnyObject, MenuLayerOwner {
    var effectivePrompt: String? { get }
    var interactionTarget: InteractionTarget? { get }
    var isActivateLocked: Bool { get }
    var isCartMode: Bool { get }
    var isLoaded: Bool { get }
    var playerSetMarker: SIMD3<Float>? { get }
    func publishMeters(_ meters: ActorValues, enemy: HUDEnemyHealth?)
    func setCartMode(_ enabled: Bool)
    func setCovered(_ covered: Bool)
    func setHelpMessage(_ text: String?)
    func showNotification(_ text: String)
    var shownBigNotices: [HUDBigNotice] { get }
    var shownModes: [HUDMode] { get }
    var shownNotifications: [String] { get }
    func shows(_ clip: HUDModeClip) -> Bool
    func update(_ change: (inout HUDSettings) -> Void)
    func updatePlayerSetMarker(_ position: SIMD3<Float>?)
    func updateCompassLocations(_ locations: [CompassLocation])
    func updateQuestTargets(_ positions: [SIMD3<Float>])
    func updateTarget(_ target: InteractionTarget?)
}
