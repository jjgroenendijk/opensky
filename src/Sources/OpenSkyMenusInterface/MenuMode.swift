/// A menu event forwarded while menu mode is active. Deliberately small and
/// toolkit-free: directional focus moves, accept/cancel, and raw pointer motion
/// cover Scaleform menu navigation without binding to AppKit or a widget tree.
nonisolated public enum MenuInputEvent: Equatable, Sendable {
    public enum Direction: Sendable { case up, down, left, right }
    /// `xButton` is the install's `XButton` user event: the Ready Weapon key while a
    /// menu is open (`Interface\Controls\PC\controlmap.txt`). `yButton` is the
    /// gamepad Y button, which Jump shares; the skills menu makes a skill legendary with it.
    public enum Button: Sendable { case accept, cancel, xButton, yButton }

    case move(Direction)
    case button(Button)
    case pointer(deltaX: Float, deltaY: Float)
    /// A direction key came up. Only a menu that reads held keys, such as
    /// lockpicking, acts on it.
    case release(Direction)
}

/// Where the visible cursor is, for a menu that picks rows by hit testing.
/// `location` and `viewSize` are view points with the origin at the top left.
nonisolated public struct MenuPointerEvent: Equatable, Sendable {
    public enum Phase: Sendable { case moved, pressed, released }

    public let phase: Phase
    public let location: SIMD2<Float>
    public let viewSize: SIMD2<Float>

    public init(_ phase: Phase, location: SIMD2<Float>, viewSize: SIMD2<Float>) {
        self.phase = phase
        self.location = location
        self.viewSize = viewSize
    }
}

/// What one open menu does to the world simulation. Dialogue leaves it
/// running, because its camera, voice clock, and face morphs advance on it.
/// A per-menu policy, because a pausing menu can open over dialogue.
nonisolated public enum MenuWorldPolicy: Equatable, Sendable {
    /// The world sim stops while this menu is open. Every menu before item
    /// 17.3, and the default, so a caller that does not think about it gets
    /// the behaviour it had.
    case pausesWorld
    /// Input is captured but the world keeps advancing.
    case leavesWorldRunning
}
