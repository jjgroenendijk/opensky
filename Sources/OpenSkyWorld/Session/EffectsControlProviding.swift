// Answers the World > Effects seams from the coordinator and the renderer.

import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering

@MainActor
public protocol EffectsControlForwarding: ImageSpaceControlProviding, VisualEffectControlProviding,
    ImpactControlProviding
{
    var effects: EffectsCoordinator { get }
    /// Where the impact and decal switches are saved.
    var playerSettingsStore: PlayerSettingsStore { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    /// The actor the panels act on, nil when none is resident.
    var effectsSelectedActor: ReferenceKey? { get }
}

extension EffectsControlForwarding {
    public var imageSpacePassEnabled: Bool {
        get { gameSession?.imageSpace.passEnabled ?? true }
        set { gameSession?.imageSpace.passEnabled = newValue }
    }

    public var toneMappingEnabled: Bool {
        get { gameSession?.imageSpace.toneMapping.enabled ?? playerSettingsStore.bool(.toneMapping)
        }
        set {
            gameSession?.imageSpace.toneMapping.enabled = newValue
            playerSettingsStore.set(.toneMapping, to: newValue ? 1 : 0)
        }
    }

    public var imageSpaceNames: [String] {
        effects.records.imageSpaces.records.compactMap(\.record.editorID).sorted()
    }

    public var forcedImageSpaceName: String? {
        get { gameSession?.imageSpace.forcedBaseline?.record.editorID }
        set {
            let resolved = newValue.flatMap { effects.records.imageSpaces.record(editorID: $0) }
            gameSession?.imageSpace.forcedBaseline = resolved.map {
                ResolvedImageSpace(key: ReferenceKey(resolved: $0.id), record: $0.record)
            }
        }
    }

    public var imageSpaceModifierNames: [String] {
        effects.records.imageSpaceAdapters.records.compactMap(\.record.editorID).sorted()
    }

    public func startImageSpaceModifier(named name: String, strength: Float) -> Bool {
        guard
            let gameSession,
            let adapter = effects.records.imageSpaceAdapters.record(editorID: name)
        else { return false }
        return effects.startModifier(
            ReferenceKey(resolved: adapter.id), strength: strength, on: &gameSession.imageSpace
        )
    }

    public func stopImageSpaceModifiers() {
        gameSession?.imageSpace.modifiers.stopAll()
    }

    public var eyeAdaptation: EyeAdaptation {
        renderer?.eyeAdaptation ?? EyeAdaptation()
    }

    public var imageSpaceState: ImageSpaceState {
        gameSession?.imageSpace ?? ImageSpaceState()
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

    public var screenBloodEnabled: Bool {
        get { effects.screenBloodEnabled }
        set {
            effects.screenBloodEnabled = newValue
            playerSettingsStore.set(.screenBlood, to: newValue ? 1 : 0)
        }
    }

    public func splatterScreenBlood(damage: Float) -> Int {
        effects.splatterScreen(damage: damage)
    }

    public var bloodText: String {
        effects.bloodReadout
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
