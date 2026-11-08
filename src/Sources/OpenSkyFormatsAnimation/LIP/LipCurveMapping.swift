// What each slot of the 33-slot humanoid `.lip` grid drives. The file stores no
// names; the order and the evidence for it are in docs/formats/lip.md.

import Foundation

/// Head turn from a lip track, in radians. Positive yaw turns left, positive pitch
/// looks up. The sign of roll is not known.
nonisolated public struct LipHeadMotion: Equatable, Sendable {
    public static let zero = LipHeadMotion(pitch: 0, roll: 0, yaw: 0)

    public let pitch: Float
    public let roll: Float
    public let yaw: Float

    public init(pitch: Float, roll: Float, yaw: Float) {
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
    }

    public func scaled(by factor: Float) -> LipHeadMotion {
        LipHeadMotion(pitch: pitch * factor, roll: roll * factor, yaw: yaw * factor)
    }
}

nonisolated public struct LipMappedSample: Equatable, Sendable {
    /// Morph weights by the face's own TRI target spelling, clamped to 0...1.
    public let weights: [String: Float]
    public let head: LipHeadMotion
    /// Slots with a value but nothing on this face to drive.
    public let unmappedActiveSlots: [Int]
}

/// The slots one face can drive, resolved once per line.
nonisolated public struct LipTargetBinding: Equatable, Sendable {
    public let morphTargets: [Int: String]
    public let drivesHead: Bool
}

nonisolated public enum LipCurveMapping {
    /// Slots 0 to 15. The names are the head TRI's own.
    public static let speechTargets = [
        "Aah", "BigAah", "BMP", "ChJSh", "DST", "Eee", "Eh", "FV",
        "I", "K", "N", "Oh", "OohQ", "R", "Th", "W"
    ]
    /// Slots 16 to 29.
    public static let modifierTargets = [
        "BlinkLeft", "BlinkRight", "BrowDownLeft", "BrowDownRight",
        "BrowInLeft", "BrowInRight", "BrowUpLeft", "BrowUpRight",
        "LookDown", "LookLeft", "LookRight", "LookUp", "SquintLeft", "SquintRight"
    ]
    public static let headPitchSlot = 30
    public static let headRollSlot = 31
    public static let headYawSlot = 32

    /// The TRI target name for each slot, before a face is known.
    public static let slotTargets: [Int: String] = Dictionary(
        uniqueKeysWithValues: (speechTargets + modifierTargets).enumerated().map { ($0, $1) }
    )

    /// Matches names without case, because a few vanilla TRI files spell them
    /// differently (`BMp`, `w`). A track without the humanoid grid binds nothing.
    public static func binding(
        slotsPerFrame: Int, availableTargets: some Sequence<String>
    ) -> LipTargetBinding {
        guard slotsPerFrame == LIPFile.humanoidSlotsPerFrame else {
            return LipTargetBinding(morphTargets: [:], drivesHead: false)
        }
        var byLowercase: [String: String] = [:]
        for name in availableTargets {
            byLowercase[name.lowercased()] = byLowercase[name.lowercased()] ?? name
        }
        let morphs = slotTargets.compactMapValues { byLowercase[$0.lowercased()] }
        return LipTargetBinding(morphTargets: morphs, drivesHead: true)
    }

    public static func map(_ sample: LIPSample, binding: LipTargetBinding) -> LipMappedSample {
        var weights: [String: Float] = [:]
        for (slot, target) in binding.morphTargets {
            weights[target] = clamped(sample.value(at: slot))
        }
        let head = binding.drivesHead
            ? LipHeadMotion(
                pitch: sample.value(at: headPitchSlot),
                roll: sample.value(at: headRollSlot),
                yaw: sample.value(at: headYawSlot)
            )
            : .zero
        let unmapped = sample.values.indices.filter { slot in
            sample.values[slot] != 0 && binding.morphTargets[slot] == nil
                && !(binding.drivesHead && isHeadSlot(slot))
        }
        return LipMappedSample(weights: weights, head: head, unmappedActiveSlots: unmapped)
    }

    private static func isHeadSlot(_ slot: Int) -> Bool {
        [headPitchSlot, headRollSlot, headYawSlot].contains(slot)
    }

    private static func clamped(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
