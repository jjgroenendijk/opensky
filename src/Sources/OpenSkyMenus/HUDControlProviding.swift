// HUD inspection seam: target state and reversible presentation overrides,
// without exposing `GameViewController`.

import simd

nonisolated public struct HUDControlSnapshot: Equatable, Sendable {
    public let prompt: String?
    public let cameraHeading: Float?
    public let scale: Float

    public init(
        prompt: String?,
        cameraHeading: Float?,
        scale: Float
    ) {
        self.prompt = prompt
        self.cameraHeading = cameraHeading
        self.scale = scale
    }
}
