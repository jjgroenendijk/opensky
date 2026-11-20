// What a menu movie needs from the movie files, the HUD, and input.
// Each concrete type answers its seam in OpenSkyMenus; a session port refines it.

public import OpenSkyFormatsSWF
public import OpenSkyGameData
public import OpenSkyRendering

/// The decoded menu movies.
public protocol MenuMovieLoading: AnyObject {
    var isAvailable: Bool { get }
    func request(
        _ path: String,
        while isWanted: @escaping () -> Bool,
        then use: @escaping (Result<SWFMovieScene, AssetLoadFailure>) -> Void
    )
}

/// A menu movie that can take the layer back once a movie opened over it stops,
/// such as a message box over the skills menu.
public protocol MenuLayerHolder: AnyObject {
    func reclaimLayer()
}

/// The HUD, which gives the single SWF layer to a menu movie and takes it back.
public protocol MenuLayerOwner: AnyObject {
    func suspend()
    func start()
    /// `holder` takes the layer from whatever holds it now.
    func suspend(for holder: any MenuLayerHolder)
    /// `holder` lets go. The holder below it, or else the HUD, gets the layer back.
    func release(by holder: any MenuLayerHolder)
}

extension MenuLayerOwner {
    public func suspend(for _: any MenuLayerHolder) {
        suspend()
    }

    public func release(by _: any MenuLayerHolder) {
        start()
    }
}

/// Menu mode, which takes the keys while a menu is open.
public protocol MenuInputRouting: AnyObject {
    var isMenuMode: Bool { get }
    @discardableResult func routeMenuInput(_ event: MenuInputEvent) -> Bool
}

/// The player's held and pressed controls, as the input dispatcher sets them.
public protocol CameraInputReceiving: AnyObject {
    func press(_ key: CameraInputState.MoveKey)
    func release(_ key: CameraInputState.MoveKey)
    func setBoost(_ enabled: Bool)
    func setSprint(_ enabled: Bool)
    func toggleSneak()
    func toggleAutoMove()
    func toggleAlwaysRun()
    func requestJump()
    func requestAttack()
    func setAttackHeld(_ enabled: Bool)
    func setBlocking(_ enabled: Bool)
    func setShouting(_ enabled: Bool)
    func requestWeaponToggle()
    func requestActivation()
    func releaseActivation()
    func requestCameraModeCycle()
}
