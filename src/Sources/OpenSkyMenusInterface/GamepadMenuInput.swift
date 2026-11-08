import simd

/// The gamepad buttons a menu reads.
nonisolated public enum GamepadButton: Hashable, Sendable, CaseIterable {
    case a, b, x, y, dpadUp, dpadDown, dpadLeft, dpadRight
}
