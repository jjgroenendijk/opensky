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

/// The HUD, which gives the single SWF layer to a menu movie and takes it back.
public protocol MenuLayerOwner: AnyObject {
    func suspend()
    func start()
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
