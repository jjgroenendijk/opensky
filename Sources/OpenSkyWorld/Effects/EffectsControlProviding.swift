// Panel seams of World > Effects: the image-space pass and the visual effects.
// `EffectsControlForwarding` answers both from the coordinator and the renderer.

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

@MainActor
public protocol EffectsControlForwarding: ImageSpaceControlProviding, VisualEffectControlProviding,
    ImpactControlProviding
{
    var effects: EffectsCoordinator { get }
    /// Where the impact and decal switches are saved.
    var playerSettingsStore: PlayerSettingsStore { get }
    var renderer: Renderer? { get }
    /// The actor the panels act on, nil when none is resident.
    var effectsSelectedActor: ReferenceKey? { get }
}

extension EffectsControlForwarding {
    public var imageSpacePassEnabled: Bool {
        get { renderer?.imageSpace.passEnabled ?? true }
        set { renderer?.imageSpace.passEnabled = newValue }
    }

    public var toneMappingEnabled: Bool {
        get { renderer?.imageSpace.toneMapping.enabled ?? playerSettingsStore.bool(.toneMapping) }
        set {
            renderer?.imageSpace.toneMapping.enabled = newValue
            playerSettingsStore.set(.toneMapping, to: newValue ? 1 : 0)
        }
    }

    public var imageSpaceNames: [String] {
        effects.records.imageSpaces.records.compactMap(\.record.editorID).sorted()
    }

    public var forcedImageSpaceName: String? {
        get { renderer?.imageSpace.forcedBaseline?.record.editorID }
        set {
            let resolved = newValue.flatMap { effects.records.imageSpaces.record(editorID: $0) }
            renderer?.imageSpace.forcedBaseline = resolved.map {
                ResolvedImageSpace(key: ReferenceKey(resolved: $0.id), record: $0.record)
            }
        }
    }

    public var imageSpaceModifierNames: [String] {
        effects.records.imageSpaceAdapters.records.compactMap(\.record.editorID).sorted()
    }

    public func startImageSpaceModifier(named name: String, strength: Float) -> Bool {
        guard
            let renderer,
            let adapter = effects.records.imageSpaceAdapters.record(editorID: name)
        else { return false }
        return effects.startModifier(
            ReferenceKey(resolved: adapter.id), strength: strength, on: &renderer.imageSpace
        )
    }

    public func stopImageSpaceModifiers() {
        renderer?.imageSpace.modifiers.stopAll()
    }

    public var imageSpaceState: ImageSpaceState {
        renderer?.imageSpace ?? ImageSpaceState()
    }

    public var visualEffectNames: [String] {
        effects.catalog.entries.map(\.name)
    }

    public func visualEffectDetails(named name: String) -> [String] {
        effects.catalog.entry(named: name).map { effects.records.details(of: $0) } ?? []
    }

    public func attachVisualEffect(named name: String, toSelectedActor: Bool) -> Bool {
        guard
            let entry = effects.catalog.entry(named: name),
            let actor = toSelectedActor ? effectsSelectedActor : .player
        else { return false }
        return effects.attach(entry.key, to: .actor(actor), cause: .debug, duration: nil) != nil
    }

    public func clearVisualEffects() {
        effects.removeAll(cause: .debug)
    }

    public var impactModelsEnabled: Bool {
        get { effects.impactModelsEnabled }
        set {
            effects.impactModelsEnabled = newValue
            playerSettingsStore.set(.impactEffects, to: newValue ? 1 : 0)
        }
    }

    public var decalsEnabled: Bool {
        get { effects.decalsEnabled }
        set {
            effects.decalsEnabled = newValue
            playerSettingsStore.set(.decals, to: newValue ? 1 : 0)
        }
    }

    public func clearDecals() {
        effects.clearDecals()
    }

    public func repeatLastImpact() -> Bool {
        effects.repeatLastImpact()
    }

    public var impactSnapshot: ImpactSnapshot {
        ImpactSnapshot(
            impactCount: effects.impactCount,
            decalCount: effects.decals.decals.count,
            decalLimit: effects.decals.limit,
            decalsDrawn: renderer?.effects.lastDecalDraws ?? 0,
            lastImpact: effects.lastImpact
                .map { $0.impact.editorID ?? $0.impact.formID.description }
        )
    }

    public var visualEffectSnapshot: VisualEffectSnapshot {
        VisualEffectSnapshot(
            instances: effects.visualEffects.instances,
            attachedTotal: effects.visualEffects.attachedTotal,
            failedModels: effects.failedModels.count,
            lastSpellHit: effects.lastSpellHit
        )
    }
}
