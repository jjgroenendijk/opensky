// Main-app HUD inspection seam (M8.4.3). The provider keeps the panel
// independent of GameViewController while exposing engine-owned target state
// and reversible presentation overrides.

import simd

nonisolated struct HUDControlSnapshot: Equatable {
    let isLoaded: Bool
    let loadError: String?
    let targetReference: FormID?
    let targetBase: FormID?
    let targetName: String?
    let targetAction: String?
    let targetDistance: Float?
    let targetPosition: SIMD3<Float>?
    let hitPosition: SIMD3<Float>?
    let prompt: String?
    let markerHeadings: [Float]
    let cameraHeading: Float?
    let scale: Float
    let drawStats: SWFDrawStats
}

@MainActor
protocol HUDControlProviding: AnyObject {
    var hudLayerEnabled: Bool { get set }
    var hudCrosshairEnabled: Bool { get set }
    var hudMetersEnabled: Bool { get set }
    var hudCompassEnabled: Bool { get set }
    var hudMarkersEnabled: Bool { get set }
    var hudPromptEnabled: Bool { get set }
    var hudPlaceholderTextEnabled: Bool { get set }
    var hudScale: Float { get set }
    var hudControlSnapshot: HUDControlSnapshot { get }
    func refocusGameView()
}
