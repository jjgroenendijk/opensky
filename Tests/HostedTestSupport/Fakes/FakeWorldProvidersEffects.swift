// The effects half of the world-provider fake: two image spaces, one modifier,
// one visual effect, and one explosion, debris, and hazard each.

@testable import OpenSkyCombat
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyRendering
@testable import OpenSkyWorld

struct FakeEffectsState {
    var imageSpace = ImageSpaceState()
    var forcedName: String?
    var modifierStarts: [(String, Float)] = []
    var attached: [(String, Bool)] = []
    var cleared = 0
    var detonated: [String] = []
    var spawned: [String] = []
    var thrown: [String] = []
    var precipitationTuning = PrecipitationTuning.fallback
    var weatherVolumetricLighting: String?
    var reverbWetOverride: Float?
    var reverbRecord: ReverbParameters?
    var lastAudioRouting: String?
    var impactModelsEnabled = true
    var decalsEnabled = true
    var decalsCleared = 0
    var impactRepeats = 0
}

extension FakeWorldProviders {
    var precipitationTuning: PrecipitationTuning {
        get { effectsState.precipitationTuning }
        set { effectsState.precipitationTuning = newValue }
    }

    var weatherVolumetricLighting: String? {
        get { effectsState.weatherVolumetricLighting }
        set { effectsState.weatherVolumetricLighting = newValue }
    }

    var reverbWetOverride: Float? {
        get { effectsState.reverbWetOverride }
        set { effectsState.reverbWetOverride = newValue }
    }

    var reverbRecord: ReverbParameters? {
        get { effectsState.reverbRecord }
        set { effectsState.reverbRecord = newValue }
    }

    var lastAudioRouting: String? {
        get { effectsState.lastAudioRouting }
        set { effectsState.lastAudioRouting = newValue }
    }

    var imageSpacePassEnabled: Bool {
        get { effectsState.imageSpace.passEnabled }
        set { effectsState.imageSpace.passEnabled = newValue }
    }

    var toneMappingEnabled: Bool {
        get { effectsState.imageSpace.toneMapping.enabled }
        set { effectsState.imageSpace.toneMapping.enabled = newValue }
    }

    var imageSpaceNames: [String] {
        ["CaveImageSpace", "SunnyImageSpace"]
    }

    var forcedImageSpaceName: String? {
        get { effectsState.forcedName }
        set { effectsState.forcedName = newValue }
    }

    var imageSpaceModifierNames: [String] {
        ["FlashModifier"]
    }

    func startImageSpaceModifier(named name: String, strength: Float) -> Bool {
        effectsState.modifierStarts.append((name, strength))
        return true
    }

    func stopImageSpaceModifiers() {
        effectsState.modifierStarts = []
    }

    var imageSpaceState: ImageSpaceState {
        effectsState.imageSpace
    }

    var visualEffectNames: [String] {
        ["GlowEffect"]
    }

    func visualEffectDetails(named name: String) -> [String] {
        name == "GlowEffect" ? ["Kind: Visual effect"] : []
    }

    func attachVisualEffect(named name: String, toSelectedActor: Bool) -> Bool {
        effectsState.attached.append((name, toSelectedActor))
        return true
    }

    func clearVisualEffects() {
        effectsState.cleared += 1
        effectsState.attached = []
    }

    var impactModelsEnabled: Bool {
        get { effectsState.impactModelsEnabled }
        set { effectsState.impactModelsEnabled = newValue }
    }

    var decalsEnabled: Bool {
        get { effectsState.decalsEnabled }
        set { effectsState.decalsEnabled = newValue }
    }

    func clearDecals() {
        effectsState.decalsCleared += 1
    }

    func repeatLastImpact() -> Bool {
        effectsState.impactRepeats += 1
        return true
    }

    var impactSnapshot: ImpactSnapshot {
        ImpactSnapshot(
            impactCount: effectsState.impactRepeats, decalCount: effectsState.impactRepeats,
            decalLimit: 100, decalsDrawn: 0, lastImpact: "FSTDirtWalkLImpact"
        )
    }

    var visualEffectSnapshot: VisualEffectSnapshot {
        var runtime = VisualEffectRuntime()
        let spec = VisualEffectSpec(name: "GlowEffect", artModel: "fx/glow.nif", membrane: nil)
        for (_, onActor) in effectsState.attached {
            runtime.attach(
                spec,
                to: onActor ? .point(.zero) : .actor(.player),
                cause: .debug,
                duration: nil
            )
        }
        return VisualEffectSnapshot(
            instances: runtime.instances, attachedTotal: effectsState.attached.count,
            failedModels: 0, lastSpellHit: "No spell hit yet."
        )
    }

    var explosionNames: [String] {
        ["FireballExplosion"]
    }

    var debrisNames: [String] {
        ["RockDebris"]
    }

    var hazardNames: [String] {
        ["FireHazard"]
    }

    func detonateExplosion(named name: String) -> Bool {
        effectsState.detonated.append(name)
        return true
    }

    func throwDebris(named name: String) -> Int {
        effectsState.thrown.append(name)
        return 6
    }

    func spawnHazard(named name: String) -> Bool {
        effectsState.spawned.append(name)
        return true
    }

    func clearExplosions() {
        effectsState.detonated = []
    }

    var explosionSnapshot: ExplosionControlSnapshot {
        ExplosionControlSnapshot(
            reports: [], detonationTotal: effectsState.detonated.count, debrisCount: 0,
            skippedPlacements: 0,
            hazards: effectsState.spawned.map {
                TrapHazardRow(name: $0, remainingLifetime: 5, lastHitTargets: 0, lastHitEffects: 0)
            }
        )
    }
}
