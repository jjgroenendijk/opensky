import simd

/// The gamepad buttons the menus and the world read.
nonisolated public enum GamepadButton: Hashable, Sendable, CaseIterable {
    case a, b, x, y, dpadUp, dpadDown, dpadLeft, dpadRight
    case leftShoulder, rightShoulder, leftTrigger, rightTrigger
    case leftThumb, rightThumb, start, back

    /// The code the control map's gamepad column uses: an XInput button mask, or
    /// 0x0009 and 0x000a for the left and right triggers.
    public var controlMapCode: UInt32 {
        switch self {
        case .dpadUp: 0x0001
        case .dpadDown: 0x0002
        case .dpadLeft: 0x0004
        case .dpadRight: 0x0008
        case .start: 0x0010
        case .back: 0x0020
        case .leftThumb: 0x0040
        case .rightThumb: 0x0080
        case .leftShoulder: 0x0100
        case .rightShoulder: 0x0200
        case .a: 0x1000
        case .b: 0x2000
        case .x: 0x4000
        case .y: 0x8000
        case .leftTrigger: 0x0009
        case .rightTrigger: 0x000A
        }
    }

    /// The menus' Xbox button art symbol, such as `360_A`. The D-pad has none.
    public var artName: String? {
        switch self {
        case .a: "360_A"
        case .b: "360_B"
        case .x: "360_X"
        case .y: "360_Y"
        case .leftShoulder: "360_LB"
        case .rightShoulder: "360_RB"
        case .leftTrigger: "360_LT"
        case .rightTrigger: "360_RT"
        case .leftThumb: "360_L3"
        case .rightThumb: "360_R3"
        case .start: "360_Start"
        case .back: "360_Back"
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: nil
        }
    }

    public init?(controlMapCode code: UInt32) {
        guard let button = Self.allCases.first(where: { $0.controlMapCode == code }) else {
            return nil
        }
        self = button
    }
}
