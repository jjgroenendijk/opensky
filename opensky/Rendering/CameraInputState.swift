// Shared free-fly input state (todo 2.8): the AppKit view layer records key
// presses and pointer deltas here; the renderer drains it once per frame into
// a `CameraInput`. Kept AppKit-free (logical keys, not NSEvent) so the
// press/release -> axis logic is unit-testable. Reference type: the view
// writes, the renderer reads, both on the main thread.

import simd

final class CameraInputState {
    /// Logical movement keys, decoupled from physical key codes (the view maps
    /// WASDQE onto these).
    enum MoveKey {
        case forward, back, left, right, up, down
    }

    private var pressed: Set<MoveKey> = []
    private var boost = false
    private var pendingLookRight: Float = 0
    private var pendingLookUp: Float = 0
    private var activationRequested = false
    private var walkToggleRequested = false

    func press(_ key: MoveKey) {
        pressed.insert(key)
    }

    func release(_ key: MoveKey) {
        pressed.remove(key)
    }

    func setBoost(_ enabled: Bool) {
        boost = enabled
    }

    /// Accumulates pointer motion (points) until the next frame drains it.
    /// `right` = pointer moved right, `up` = pointer moved up.
    func addLook(right: Float, up: Float) {
        pendingLookRight += right
        pendingLookUp += up
    }

    /// Latches one interaction key-down until world controller consumes it.
    func requestActivation() {
        activationRequested = true
    }

    func consumeActivation() -> Bool {
        defer { activationRequested = false }
        return activationRequested
    }

    /// Latches one fly/walk toggle until renderer drains the next input frame.
    func requestWalkToggle() {
        walkToggleRequested = true
    }

    /// Clears all held state — call on capture loss / focus loss so keys do not
    /// stick after the window stops receiving key-up events.
    func releaseAll() {
        pressed.removeAll()
        boost = false
        pendingLookRight = 0
        pendingLookUp = 0
        activationRequested = false
        walkToggleRequested = false
    }

    /// Snapshots the frame's input and drains accumulated pointer deltas.
    /// Opposing keys cancel (forward+back -> 0).
    func makeInput(dt: Float) -> CameraInput {
        let input = CameraInput(
            moveForward: axis(.forward, .back),
            moveRight: axis(.right, .left),
            moveUp: axis(.up, .down),
            lookRight: pendingLookRight,
            lookUp: pendingLookUp,
            boost: boost,
            toggleWalkMode: walkToggleRequested,
            dt: dt
        )
        pendingLookRight = 0
        pendingLookUp = 0
        walkToggleRequested = false
        return input
    }

    private func axis(_ positive: MoveKey, _ negative: MoveKey) -> Float {
        (pressed.contains(positive) ? 1 : 0) - (pressed.contains(negative) ? 1 : 0)
    }
}
