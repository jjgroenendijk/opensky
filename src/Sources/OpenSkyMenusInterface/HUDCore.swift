import simd

nonisolated public struct HUDSettings: Equatable, Sendable {
    public var layerEnabled = true
    public var crosshairEnabled = true
    public var metersEnabled = true
    public var compassEnabled = true
    public var markersEnabled = true
    public var promptEnabled = true
    public var placeholderTextEnabled = false
    public var scale: Float = 1

    public init() {}
}
