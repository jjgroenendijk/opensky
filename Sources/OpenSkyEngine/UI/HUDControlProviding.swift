// Main-app HUD inspection seam (M8.4.3). The provider keeps the panel
// independent of GameViewController while exposing engine-owned target state
// and reversible presentation overrides.

import OpenSkyFormatsESM
import OpenSkyRendering
import simd

nonisolated public struct HUDControlSnapshot: Equatable, Sendable {
    public let isLoaded: Bool
    public let loadError: String?
    public let targetReference: FormID?
    public let targetBase: FormID?
    public let targetName: String?
    public let targetAction: String?
    public let targetDistance: Float?
    public let targetPosition: SIMD3<Float>?
    public let hitPosition: SIMD3<Float>?
    public let prompt: String?
    public let markerHeadings: [Float]
    public let cameraHeading: Float?
    public let scale: Float
    public let drawStats: SWFDrawStats

    public init(
        isLoaded: Bool,
        loadError: String?,
        targetReference: FormID?,
        targetBase: FormID?,
        targetName: String?,
        targetAction: String?,
        targetDistance: Float?,
        targetPosition: SIMD3<Float>?,
        hitPosition: SIMD3<Float>?,
        prompt: String?,
        markerHeadings: [Float],
        cameraHeading: Float?,
        scale: Float,
        drawStats: SWFDrawStats
    ) {
        self.isLoaded = isLoaded
        self.loadError = loadError
        self.targetReference = targetReference
        self.targetBase = targetBase
        self.targetName = targetName
        self.targetAction = targetAction
        self.targetDistance = targetDistance
        self.targetPosition = targetPosition
        self.hitPosition = hitPosition
        self.prompt = prompt
        self.markerHeadings = markerHeadings
        self.cameraHeading = cameraHeading
        self.scale = scale
        self.drawStats = drawStats
    }
}

@MainActor
public protocol HUDControlProviding: AnyObject {
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
