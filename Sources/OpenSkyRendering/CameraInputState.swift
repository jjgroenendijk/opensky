// Shared free-fly input state (todo 2.8): the AppKit view layer records key
// presses and pointer deltas here; the renderer drains it once per frame into
// a `CameraInput`. Kept AppKit-free (logical keys, not NSEvent) so the
// press/release -> axis logic is unit-testable. Reference type: the view
// writes, the renderer reads, both on the main thread.

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

    /// Sprint is held, like boost (issue #188): the locomotion bridge reads the
    /// level each fixed step rather than an edge.
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

    /// Latches one attack press until the next frame drains it (issue #195),
    /// on the same terms as jump: a click between two rendered frames must
    /// still reach a fixed step, and must reach it exactly once.
    public func requestAttack() {
        attackRequested = true
    }

    /// Holds the attack button down (issue #196). The same binding as
    /// `requestAttack()` and deliberately not the same signal: melee acts on
    /// the press and archery on the hold, so the view sets both from one
    /// mouse-down and only this one is cleared by the mouse-up.
    public func setAttackHeld(_ enabled: Bool) {
        attackHeld = enabled
    }

    public var isAttackHeld: Bool {
        attackHeld
    }

    /// Block is held, like boost and sprint: the melee runtime reads the level
    /// each frame and raises `blockStart`/`blockStop` on its edges.
    public func setBlocking(_ enabled: Bool) {
        blocking = enabled
    }

    public var isBlocking: Bool {
        blocking
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

    /// Clears all held state — call on capture loss / focus loss so keys do not
    /// stick after the window stops receiving key-up events. Sneak is a mode
    /// rather than a held key, so it deliberately survives: releasing capture
    /// must not stand the player up. Whether the weapon is drawn survives for
    /// the same reason — it is world state the player set on purpose — but the
    /// guard drops, because a block held through a lost mouse-up would stay up
    /// forever.
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
    /// Opposing keys cancel (forward+back -> 0).
    public func makeInput(dt: Float) -> CameraInput {
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
