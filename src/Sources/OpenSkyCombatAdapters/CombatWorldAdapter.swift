// App side of `CombatCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and plays reaction clips. The rules live
// in the coordinator (docs/engine/coordinators.md).

public import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
public import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyScripting
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `CombatWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol CombatWorldHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var mapWorld: any MapWorldPort { get }
    var player: any PlayerPort { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var renderer: (any RendererPort)? { get }
    var animationClips: ActorClipLoader? { get }
    var worldData: WorldDataStores? { get }
}

/// Answers `CombatWorld` from the session systems `game` owns.
public final class CombatWorldAdapter {
    public unowned let game: any CombatWorldHost
    /// Rigs whose reaction clips were requested, because a room of actors shares one rig.
    private var warmedSkeletons: Set<String> = []

    public let spellCastsHost: any CombatSpellCastsHost
    public let impactEffectsHost: any CombatImpactEffectsHost
    public let reportsHost: any CombatReportsHost
    public let actorFactsHost: any CombatActorFactsHost
    public let gearHost: any CombatGearHost
    public let motionHost: any CombatMotionHost
    public let outcomesHost: any CombatOutcomesHost

    public var spellCasts: CombatSpellCastsAdapter {
        CombatSpellCastsAdapter(
            owner: self,
            game: spellCastsHost
        )
    }

    public var impactEffects: CombatImpactEffectsAdapter {
        CombatImpactEffectsAdapter(
            owner: self,
            game: impactEffectsHost
        )
    }

    public var reports: CombatReportsAdapter {
        CombatReportsAdapter(owner: self, game: reportsHost)
    }

    public var actorFacts: CombatActorFactsAdapter {
        CombatActorFactsAdapter(
            owner: self,
            game: actorFactsHost
        )
    }

    public var gear: CombatGearAdapter {
        CombatGearAdapter(owner: self, game: gearHost)
    }

    public var motion: CombatMotionAdapter {
        CombatMotionAdapter(owner: self, game: motionHost)
    }

    public var outcomes: CombatOutcomesAdapter {
        CombatOutcomesAdapter(owner: self, game: outcomesHost)
    }

    public init(game: some CombatWorldHost & CombatSpellCastsHost & CombatImpactEffectsHost &
        CombatReportsHost & CombatActorFactsHost & CombatGearHost & CombatMotionHost &
        CombatOutcomesHost)
    {
        spellCastsHost = game
        impactEffectsHost = game
        reportsHost = game
        actorFactsHost = game
        gearHost = game
        motionHost = game
        outcomesHost = game
        self.game = game
    }

    /// Nil without game data: the runtimes stay nil, and no fight starts with
    /// invented numbers.
    public func sessionData() -> CombatSessionData? {
        guard let provider = game.worldData else { return nil }
        let settings = provider.gameSettings
        let text: GameTextResolver = { [game] in game.mapWorld.text($0) }
        var data = CombatSessionData(
            combat: provider.combatSettings,
            archery: provider.archerySettings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        data.difficulty = provider.difficultySettings
        data.weaponDamage = WeaponDamageSettings.resolve(store: settings, text: text)
        data.stamina = StaminaSettings.resolve(store: settings)
        data.powerAttacks = PowerAttackSettings.resolve(store: settings)
        data.skillUses = MeleeSkillUseSettings.resolve(store: settings)
        data.staggers = StaggerSettings.resolve(store: settings)
        data.combatAI = CombatAISettings.resolve(store: settings)
        data.arrows = ArrowSettings.resolve(store: settings, text: text)
        data.falls = FallDamageSettings.resolve(store: settings)
        data.magicWorld = MagicWorldSettings.resolve(store: settings)
        return data
    }

    /// Only the player has a graph with a draw state, so an NPC draws while it fights.
    func updateNPCDrawStates() {
        guard let loop = game.combat.loop else { return }
        for actor in game.actorWorld.combatActors() {
            game.actorPlayback(for: actor.key)?.weaponsDrawn = loop
                .activity(of: actor.key) == .fighting
        }
    }

    private static func items(_ provider: WorldDataStores) -> ItemDefinitionStore? {
        provider.inventoryBaselines?.items
    }

    private static func impacts(_ provider: WorldDataStores) -> MeleeImpactResolver? {
        provider.footstepStore.map { MeleeImpactResolver(footsteps: $0) }
    }

    /// Plays one reaction clip on a resident actor. False when the actor has
    /// no playback or its rig has no such animation.
    public func playReaction(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        guard
            let renderer = game.renderer,
            let playback = game.actorPlayback(for: key),
            let loaded = reactionClip(clip, skeletonMeshPath: playback.clip.skeletonMeshPath)
        else { return false }
        playback.play(
            loaded,
            startingAt: renderer.animationTime,
            forSeconds: ActorAnimationClipLoader.holdSeconds(for: clip)
        )
        return true
    }

    /// The clip when it is loaded. The first ask for a skeleton warms every reaction
    /// of that rig off the main actor; a hit before it arrives plays no reaction.
    private func reactionClip(
        _ clip: CombatActorClip,
        skeletonMeshPath: String
    ) -> ActorAnimationClip? {
        guard let clips = game.animationClips else { return nil }
        if warmedSkeletons.insert(skeletonMeshPath).inserted {
            for other in CombatActorClip.allCases where other != clip {
                clips.prefetch(Self.reactionKey(other, skeletonMeshPath: skeletonMeshPath))
            }
        }
        return clips.value(for: Self.reactionKey(clip, skeletonMeshPath: skeletonMeshPath))
    }

    private static func reactionKey(
        _ clip: CombatActorClip,
        skeletonMeshPath: String
    ) -> ActorClipKey {
        ActorClipKey(
            skeletonMeshPath: skeletonMeshPath,
            animationPath: ActorAnimationClipLoader.animationPath(for: clip)
        )
    }
}

extension CombatWorldAdapter: CombatWorldPort {}
