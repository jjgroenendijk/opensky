// HUD inspection seam: target state and reversible presentation overrides,
// without exposing `GameViewController`.

import simd

nonisolated struct HUDControlSnapshot: Equatable, Sendable {
    let prompt: String?
    let cameraHeading: Float?
    let scale: Float
}
