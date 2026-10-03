// Shared free-fly input state: the view records keys and pointer deltas, the renderer
// drains them once per frame into a `CameraInput`. Logical keys, not NSEvent, so the axis
// logic is unit-testable. Both sides run on the main thread.

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
    private var weaponToggleRequested = false
    private var pendingLookRight: Float = 0
    private var pendingLookUp: Float = 0
    private var activationRequested = false
    private var cameraModeCycleRequested = false

    public func press(_ key: MoveKey) {
        pressed.insert(key)
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

    /// Latches one draw/sheath press. A toggle rather than two bindings,
    /// because vanilla binds one key to both and the graph already knows which
    /// way it is going.
    public func requestWeaponToggle() {
        weaponToggleRequested = true
    }

    /// Accumulates pointer motion (points) until the next frame drains it.
    /// `right` = pointer moved right, `up` = pointer moved up.
    public func addLook(right: Float, up: Float) {
        pendingLookRight += right
        pendingLookUp += up
    }

    /// Latches one interaction key-down until world controller consumes it.
    public func requestActivation() {
        activationRequested = true
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
        boost = false
        sprinting = false
        jumpRequested = false
        attackRequested = false
        attackHeld = false
        blocking = false
        weaponToggleRequested = false
        pendingLookRight = 0
        pendingLookUp = 0
        activationRequested = false
        cameraModeCycleRequested = false
    }

    /// Snapshots the frame's input and drains accumulated pointer deltas.
    /// Opposing keys cancel (forward+back -> 0). A frame with no time (paused,
    /// or between stepped frames) drains nothing, so a press waits for a step.
    public func makeInput(dt: Float) -> CameraInput {
        guard dt > 0 else {
            return CameraInput(
                boost: boost,
                sprint: sprinting,
                sneak: sneaking,
                attackHeld: attackHeld,
                block: blocking,
                dt: dt
            )
        }
        let input = CameraInput(
            moveForward: axis(.forward, .back),
            moveRight: axis(.right, .left),
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
            dt: dt
        )
        pendingLookRight = 0
        pendingLookUp = 0
        jumpRequested = false
        cameraModeCycleRequested = false
        attackRequested = false
        weaponToggleRequested = false
        return input
    }

    private func axis(_ positive: MoveKey, _ negative: MoveKey) -> Float {
        (pressed.contains(positive) ? 1 : 0) - (pressed.contains(negative) ? 1 : 0)
    }
}
