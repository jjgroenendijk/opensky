// Shared free-fly input state: the view records keys and pointer deltas, the renderer
// drains them once per frame into a `CameraInput`. Logical keys, not NSEvent, so the axis
// logic is unit-testable. Both sides run on the main thread.

public import OpenSkyRenderCore
import simd

public final class CameraInputState {
    public init() {}

    /// Logical movement keys, decoupled from physical key codes (the view maps
    /// WASDQE onto these).
    public enum MoveKey {
        case forward, back, left, right, up, down
    }

    private var pressed: Set<MoveKey> = []
    private var boost = false
    private var sprinting = false
    private var sneaking = false
    private var jumpRequested = false
    private var attackRequested = false
    private var attackHeld = false
    private var blocking = false
    private var shouting = false
    private var weaponToggleRequested = false
    private var pendingLookRight: Float = 0
    private var pendingLookUp: Float = 0
    private var activationRequested = false
    public private(set) var isActivationHeld = false
    private var cameraModeCycleRequested = false
    private var autoMove = false
    /// A gamepad's left stick, x right and y forward, added to the move keys.
    private var analogMove: SIMD2<Float> = .zero
    /// The install's `SkyrimPrefs.ini` sets always run on by default.
    public private(set) var alwaysRun = true

    /// Forward or back ends Auto-Move.
    public func press(_ key: MoveKey) {
        pressed.insert(key)
        if key == .forward || key == .back {
            autoMove = false
        }
    }

    /// Auto-Move walks forward until it is pressed again or a forward or back key is.
    public func toggleAutoMove() {
        autoMove.toggle()
    }

    /// The left stick this frame. A stick pushed forward or back ends Auto-Move too.
    public func setAnalogMove(_ move: SIMD2<Float>) {
        analogMove = move
        if move.y != 0 {
            autoMove = false
        }
    }

    /// Caps Lock flips whether the body runs without the Run key held.
    public func toggleAlwaysRun() {
        alwaysRun.toggle()
    }

    public func release(_ key: MoveKey) {
        pressed.remove(key)
    }

    public func setBoost(_ enabled: Bool) {
        boost = enabled
    }

    /// Sprint is held, like boost: the locomotion bridge reads the level each fixed
    /// step.
    public func setSprint(_ enabled: Bool) {
        sprinting = enabled
    }

    public var isSprinting: Bool {
        sprinting
    }

    /// Flips sneak. Vanilla sneak is a toggle, not a held key, so the state
    /// survives the key-up that follows it.
    public func toggleSneak() {
        sneaking.toggle()
    }

    public var isSneaking: Bool {
        sneaking
    }

    /// Latches one jump key-down until the next frame drains it, so a jump can
    /// never be lost between two rendered frames or applied twice from one
    /// press.
    public func requestJump() {
        jumpRequested = true
    }

    /// Latches one attack press until the next frame drains it, like jump, so a
    /// click between frames reaches exactly one fixed step.
    public func requestAttack() {
        attackRequested = true
    }

    /// Holds the attack button down. Same binding as `requestAttack()`, but melee
    /// acts on the press and archery on the hold, so only this one clears on
    /// mouse-up.
    public func setAttackHeld(_ enabled: Bool) {
        attackHeld = enabled
    }

    /// Block is held, like boost and sprint: the melee runtime reads the level
    /// each frame and raises `blockStart`/`blockStop` on its edges.
    public func setBlocking(_ enabled: Bool) {
        blocking = enabled
    }

    /// The shout key is held like block: the shout runtime times the hold.
    public func setShouting(_ enabled: Bool) {
        shouting = enabled
    }

    /// Latches one draw/sheath press. A toggle rather than two bindings,
    /// because vanilla binds one key to both and the graph already knows which
    /// way it is going.
    public func requestWeaponToggle() {
        weaponToggleRequested = true
    }

    /// The player's look speed; 1 is the camera's own speed.
    public var lookScale: Float = 1
    /// Invert Y: pointer up looks down.
    public var invertLook = false

    /// Accumulates pointer motion (points) until the next frame drains it.
    /// `right` = pointer moved right, `up` = pointer moved up.
    public func addLook(right: Float, up: Float) {
        pendingLookRight += right * lookScale
        pendingLookUp += (invertLook ? -up : up) * lookScale
    }

    /// Latches one interaction key-down until world controller consumes it.
    public func requestActivation() {
        activationRequested = true
        isActivationHeld = true
    }

    /// The use key went up, which tells a tap from a hold on a follower.
    public func releaseActivation() {
        isActivationHeld = false
    }

    public func consumeActivation() -> Bool {
        defer { activationRequested = false }
        return activationRequested
    }

    /// Latches one camera-mode step until the renderer drains the next input
    /// frame. One press advances fly -> walk -> third person -> fly.
    public func requestCameraModeCycle() {
        cameraModeCycleRequested = true
    }

    /// Clears all held state on capture or focus loss, so keys do not stick. Sneak
    /// and the drawn weapon survive, because they are modes the player set. The
    /// block guard drops.
    public func releaseAll() {
        pressed.removeAll()
        autoMove = false
        analogMove = .zero
        boost = false
        sprinting = false
        jumpRequested = false
        attackRequested = false
        attackHeld = false
        blocking = false
        shouting = false
        weaponToggleRequested = false
        pendingLookRight = 0
        pendingLookUp = 0
        activationRequested = false
        isActivationHeld = false
        cameraModeCycleRequested = false
    }

    /// Snapshots the frame's input and drains accumulated pointer deltas.
    /// Opposing keys cancel (forward+back -> 0). A frame with no time (paused,
    /// or between stepped frames) drains nothing, so a press waits for a step.
    public func makeInput(dt: Float) -> CameraInput {
        guard dt > 0 else {
            var input = CameraInput(
                boost: boost,
                sprint: sprinting,
                sneak: sneaking,
                attackHeld: attackHeld,
                block: blocking,
                shout: shouting,
                dt: dt
            )
            input.alwaysRun = alwaysRun
            return input
        }
        var input = CameraInput(
            moveForward: autoMove ? 1 : Self.clamped(axis(.forward, .back) + analogMove.y),
            moveRight: Self.clamped(axis(.right, .left) + analogMove.x),
            moveUp: axis(.up, .down),
            lookRight: pendingLookRight,
            lookUp: pendingLookUp,
            boost: boost,
            sprint: sprinting,
            sneak: sneaking,
            jump: jumpRequested,
            cycleCameraMode: cameraModeCycleRequested,
            attack: attackRequested,
            attackHeld: attackHeld,
            block: blocking,
            toggleWeaponDrawn: weaponToggleRequested,
            shout: shouting,
            dt: dt
        )
        input.alwaysRun = alwaysRun
        pendingLookRight = 0
        pendingLookUp = 0
        jumpRequested = false
        cameraModeCycleRequested = false
        attackRequested = false
        weaponToggleRequested = false
        return input
    }

    private static func clamped(_ value: Float) -> Float {
        min(1, max(-1, value))
    }

    private func axis(_ positive: MoveKey, _ negative: MoveKey) -> Float {
        (pressed.contains(positive) ? 1 : 0) - (pressed.contains(negative) ? 1 : 0)
    }
}
