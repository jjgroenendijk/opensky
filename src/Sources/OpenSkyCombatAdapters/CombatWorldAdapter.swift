// App side of `CombatCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and plays reaction clips. The rules live
// in the coordinator (docs/engine/coordinators.md).

public import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCamera
import OpenSkyCells
public import OpenSkyCombat
public import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `CombatWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol CombatWorldHost: AnyObject, SendableMetatype {
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var mapWorld: any MapWorldPort { get }
    var player: any PlayerPort { get }
    var renderer: (any RendererPort)? { get }
    var animationClips: ActorClipLoader? { get }
    var combatRecords: (any CombatRecordsPort)? { get }
}

/// Answers `CombatWorld` from the session systems `game` owns.
/// Every host a `CombatWorldAdapter` part reads, all one object.
public typealias CombatWorldHosts = CombatActorFactsHost & CombatGearHost &
    CombatImpactEffectsHost &
    CombatMotionHost & CombatOutcomesHost & CombatReportsHost & CombatSpellCastsHost &
    CombatWorldHost

public final class CombatWorldAdapter {
    public let game: any CombatWorldHost
    let frames: CombatFrameSteps
    let reactions: CombatReactionClips

    public var spellCasts: CombatSpellCastsAdapter {
        frames.spellCasts
    }

    public var impactEffects: CombatImpactEffectsAdapter {
        frames.impactEffects
    }

    var reports: CombatReportsAdapter {
        frames.reports
    }

    public var actorFacts: CombatActorFactsAdapter {
        frames.actorFacts
    }

    var gear: CombatGearAdapter {
        frames.gear
    }

    public var motion: CombatMotionAdapter {
        frames.motion
    }

    public var outcomes: CombatOutcomesAdapter {
        frames.outcomes
    }

    public var sessions: CombatSessionBuilder {
        CombatSessionBuilder(game: game)
    }

    public init(game: some CombatWorldHosts) {
        self.game = game
        frames = CombatFrameSteps(hosts: game)
        reactions = CombatReactionClips(game: game)
    }

    public func playReaction(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        reactions.playReaction(clip, on: key)
    }
}

extension CombatWorldAdapter: CombatWorldPort {}

/// Builds the combat session data from the game's records.
public struct CombatSessionBuilder {
    let game: any CombatWorldHost

    /// Nil without game data: the runtimes stay nil, and no fight starts with
    /// invented numbers.
    public func sessionData() -> CombatSessionData? {
        guard let provider = game.combatRecords else { return nil }
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
        data.friendlyFire = FriendlyFireSettings.resolve(store: settings)
        data.combatAI = CombatAISettings.resolve(store: settings)
        data.arrows = ArrowSettings.resolve(store: settings, text: text)
        data.falls = FallDamageSettings.resolve(store: settings)
        data.magicWorld = MagicWorldSettings.resolve(store: settings)
        return data
    }

    private static func items(_ provider: any CombatRecordsPort) -> ItemDefinitionStore? {
        provider.inventoryBaselines?.items
    }

    private static func impacts(_ provider: any CombatRecordsPort) -> MeleeImpactResolver? {
        provider.footstepStore.map { MeleeImpactResolver(footsteps: $0) }
    }
}

/// The parts of `CombatWorldAdapter`, and the frame steps that drive the fight.
final class CombatFrameSteps {
    let hosts: any CombatWorldHosts

    init(hosts: any CombatWorldHosts) {
        self.hosts = hosts
    }

    var spellCasts: CombatSpellCastsAdapter {
        CombatSpellCastsAdapter(game: hosts)
    }

    var impactEffects: CombatImpactEffectsAdapter {
        CombatImpactEffectsAdapter(game: hosts)
    }

    var reports: CombatReportsAdapter {
        CombatReportsAdapter(game: hosts, actorFacts: actorFacts)
    }

    var actorFacts: CombatActorFactsAdapter {
        CombatActorFactsAdapter(game: hosts)
    }

    var gear: CombatGearAdapter {
        CombatGearAdapter(game: hosts)
    }

    var motion: CombatMotionAdapter {
        CombatMotionAdapter(game: hosts, impactEffects: impactEffects)
    }

    var outcomes: CombatOutcomesAdapter {
        CombatOutcomesAdapter(
            game: hosts, motion: motion, impactEffects: impactEffects
        )
    }

    /// Only the player has a graph with a draw state, so an NPC draws while it fights.
    func updateNPCDrawStates() {
        guard let loop = hosts.combat.loop else { return }
        for actor in hosts.actorWorld.combatActors() {
            hosts.actorPlayback(for: actor.key)?.weaponsDrawn = loop
                .activity(of: actor.key) == .fighting
        }
    }
}

/// Plays the hit and stagger reactions, and warms each rig's clips once.
final class CombatReactionClips {
    let game: any CombatWorldHost
    /// Rigs whose reaction clips were requested, because a room of actors shares one rig.
    private var warmedSkeletons: Set<String> = []

    init(game: any CombatWorldHost) {
        self.game = game
    }

    /// Plays one reaction clip on a resident actor. False when the actor has
    /// no playback or its rig has no such animation.
    func playReaction(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
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
