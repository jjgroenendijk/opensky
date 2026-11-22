import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPerception
public import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import simd

/// What `AIDetectionSenseAdapter` reads from the session.
@MainActor
public protocol AIDetectionSenseHost: AnyObject, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var effectsWorld: any EffectsWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var perception: any PerceptionPort { get }
    var perks: any PerkPort { get }
    var renderer: (any RendererPort)? { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIDetectionSenseAdapter {
    public let game: any AIDetectionSenseHost
}

extension AIDetectionSenseAdapter {
    /// `Sneak`, `Invisibility`, and `Movement Noise Mult` in the vanilla table.
    private static let sneakIndex: Int32 = 15
    private static let invisibilityIndex: Int32 = 54
    private static let blindnessIndex: Int32 = 84
    private static let movementNoiseMultIndex: Int32 = 92
    /// Point lights the sample sums; the nearest ones carry nearly all the light.
    private static let sampledPointLights = 8

    public func sneakSkill(of actor: ReferenceKey) -> Float {
        actorValue(Self.sneakIndex, of: actor) ?? DetectionTargetTraits.startingSkill
    }

    public func blindness(of actor: ReferenceKey) -> Float {
        actorValue(Self.blindnessIndex, of: actor) ?? 0
    }

    public func hasNightEye(_ actor: ReferenceKey) -> Bool {
        guard let index = ActorValueIdentity.index(named: "Night Eye") else { return false }
        return (actorValue(index, of: actor) ?? 0) > 0
    }

    /// The player rule on the Sneak skill, then the sneak skill perks.
    private func playerEffectiveSneak() -> Float? {
        guard let settings = game.perception.runtime?.settings else { return nil }
        return playerPerk(
            settings.playerSneakBase.value
                + settings.playerSneakMult.value * sneakSkill(of: .player),
            at: .modDetectionSneakSkill
        )
    }

    /// 100 times the largest channel of an interior's ambient colour. Infinite outdoors.
    private func interiorLightCap() -> Float {
        guard let ambient = game.renderer?.scene.lighting?.ambientColor else { return .infinity }
        return Self.lightLevelScale * max(ambient.x, ambient.y, ambient.z)
    }

    private static let lightLevelScale: Float = 100

    /// The player's detection perks apply once a frame, with no observer bound:
    /// no vanilla perk at these entry points tests the observer tab.
    public func playerDetectionTraits(
        at feet: SIMD3<Float>,
        eyeHeight: Float
    ) -> DetectionTargetTraits {
        var traits = DetectionTargetTraits(
            equippedWeight: game.inventory.armourWeights.playerWornArmourWeight,
            lightLevel: playerPerk(
                lightLevel(at: feet + SIMD3(0, 0, PlayerCapsule.torsoHeight(eyeHeight: eyeHeight))),
                at: .modDetectionLight
            ),
            muffle: actorValue(Self.movementNoiseMultIndex, of: .player) ?? 0,
            actionSound: sound.playerActionSound(),
            sneakSkill: sneakSkill(of: .player),
            isInvisible: (actorValue(Self.invisibilityIndex, of: .player) ?? 0) > 0,
            movementMultiplier: playerPerk(1, at: .modDetectionMovement)
        )
        traits.castingSound = sound.playerCastingSound()
        traits.effectiveSneakSkill = playerEffectiveSneak()
        traits.interiorLightCap = interiorLightCap()
        if let size = game.effectsWorld.race(of: .player)?.details.properties?.size {
            traits.sizeFactor = DetectionTargetTraits.sizeFactor(raceSize: Int(size))
        }
        return traits
    }

    private func playerPerk(_ value: Float, at entryPoint: PerkEntryPoint) -> Float {
        game.perks.modified(
            value,
            at: entryPoint,
            on: .player,
            subjects: { _ in PerkEvaluationSubjects(owner: .player) },
            seams: ConditionContext()
        )
    }

    private func actorValue(_ index: Int32, of actor: ReferenceKey) -> Float? {
        guard
            let runtime = game.actorValues.runtime,
            let holder = game.actorWorld.actorValueHolder(for: actor)
        else { return nil }
        return runtime.value(at: index, on: holder)
    }

    /// The same ambient, directional, and point light the scene pass shades with.
    public func lightLevel(at position: SIMD3<Float>) -> Float {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let settings = game.perception.runtime?.settings
        else {
            return 1
        }
        let scene = renderer.scene
        let interior = scene.lighting
        let weather = interior == nil ? gameSession.currentResolvedWeather : nil
        let sample = DetectionLightSample(
            ambient: weather?.ambientColor ?? interior?.ambientColor
                ?? renderer.camera.ambientColor,
            directional: weather?.sunlightColor ?? interior?.directionalColor
                ?? renderer.camera.sunColor,
            pointLights: scene.nearestPointLights(to: position, limit: Self.sampledPointLights)
                .map {
                    DetectionPointLight(
                        position: $0.position, radius: $0.radius, colour: $0.color,
                        falloffExponent: $0.falloffExponent
                    )
                }
        )
        return sample.level(at: position, fullLuminance: settings.fullLightLuminance.value)
    }
}
