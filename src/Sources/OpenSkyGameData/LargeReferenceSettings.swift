// Which placed statics count as large references, kept loaded past the grid
// (docs/engine/distant-lod.md, "Large references").

public import OpenSkyFormatsESM
import simd

nonisolated public struct LargeReferenceSettings: Equatable, Sendable {
    /// `fLargeRefMinSize`, in game units.
    public var minimumSize: Float = 1024

    public static let vanilla = Self()

    public init(minimumSize: Float = 1024) {
        self.minimumSize = minimumSize
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fLargeRefMinSize", into: &settings, \.minimumSize)
        return settings
    }

    /// Half the bounds' diagonal, times the reference's scale. Observed in the game.
    public static func size(of bounds: ObjectBounds, scale: Float) -> Float {
        let extent = SIMD3<Float>(bounds.maximum) - SIMD3<Float>(bounds.minimum)
        return 0.5 * simd_length(extent) * scale
    }

    /// A reference larger than the minimum size counts as large.
    public func isLarge(_ bounds: ObjectBounds, scale: Float) -> Bool {
        Self.size(of: bounds, scale: scale) > minimumSize
    }
}
