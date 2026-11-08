// The colours of the debug markers the world overlay draws.

nonisolated public enum WorldOverlayMarkerColour {
    /// Amber, on each locked door and container.
    public static let lock = SIMD4<Float>(1, 0.85, 0.2, 1)
    /// Red, on each trap.
    public static let trap = SIMD4<Float>(1, 0.3, 0.2, 1)
}
