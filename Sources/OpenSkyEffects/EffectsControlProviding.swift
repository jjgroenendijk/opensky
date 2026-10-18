// Panel seams of World > Effects: the image-space pass and the visual effects.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

@MainActor
public protocol ImageSpaceControlProviding: AnyObject {
    var imageSpacePassEnabled: Bool { get set }
    /// HDR tone mapping: eye adaptation and the white point.
    var toneMappingEnabled: Bool { get set }
    /// The `IMGS` editor IDs, for the forced baseline picker.
    var imageSpaceNames: [String] { get }
    /// Nil follows the weather or the interior cell.
    var forcedImageSpaceName: String? { get set }
    var imageSpaceModifierNames: [String] { get }
    @discardableResult
    func startImageSpaceModifier(named name: String, strength: Float) -> Bool
    func stopImageSpaceModifiers()
    var imageSpaceState: ImageSpaceState { get }
    /// The exposure the renderer's eye has adapted to.
    var eyeAdaptation: EyeAdaptation { get }
}

@MainActor
public protocol VisualEffectControlProviding: AnyObject {
    var visualEffectNames: [String] { get }
    func visualEffectDetails(named name: String) -> [String]
    /// False when the record draws nothing or the target is not resident.
    @discardableResult
    func attachVisualEffect(named name: String, toSelectedActor: Bool) -> Bool
    func clearVisualEffects()
    var visualEffectSnapshot: VisualEffectSnapshot { get }
}

nonisolated public struct VisualEffectSnapshot: Equatable, Sendable {
    public let instances: [VisualEffectInstance]
    public let attachedTotal: Int
    public let failedModels: Int
    public let lastSpellHit: String

    public init(
        instances: [VisualEffectInstance], attachedTotal: Int, failedModels: Int,
        lastSpellHit: String
    ) {
        self.instances = instances
        self.attachedTotal = attachedTotal
        self.failedModels = failedModels
        self.lastSpellHit = lastSpellHit
    }
}

@MainActor
public protocol ImpactControlProviding: AnyObject {
    /// Impact models: dust under a step, sparks or blood spray on a hit.
    var impactModelsEnabled: Bool { get set }
    var decalsEnabled: Bool { get set }
    func clearDecals()
    /// Shows the last impact again at the player's feet. False before the first one.
    @discardableResult
    func repeatLastImpact() -> Bool
    var impactSnapshot: ImpactSnapshot { get }
}

nonisolated public struct ImpactSnapshot: Equatable, Sendable {
    public let impactCount: Int
    public let decalCount: Int
    public let decalLimit: Int
    /// Decals the last frame drew.
    public let decalsDrawn: Int
    /// The last impact's editor ID, or nil before the first.
    public let lastImpact: String?

    public init(
        impactCount: Int, decalCount: Int, decalLimit: Int, decalsDrawn: Int, lastImpact: String?
    ) {
        self.impactCount = impactCount
        self.decalCount = decalCount
        self.decalLimit = decalLimit
        self.decalsDrawn = decalsDrawn
        self.lastImpact = lastImpact
    }

    public var text: String {
        """
        Impacts: \(impactCount), last \(lastImpact ?? "none")
        Decals: \(decalCount) of \(decalLimit), \(decalsDrawn) drawn
        """
    }
}
