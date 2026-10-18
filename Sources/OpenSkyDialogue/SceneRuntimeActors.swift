// Scene actors: an actor is in one scene at a time, and its behaviour flags pause
// or end the scene. Rules from <https://ck.uesp.net/wiki/Category:Scenes> ("Actors
// in Scenes") and the Scenes Tab page ("Actor Behavior"). See docs/engine/scenes.md.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyWorldState

/// What a scene actor does now. The host answers it each tick.
nonisolated public struct SceneActorStatus: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let dead = SceneActorStatus(rawValue: 0x01)
    /// In combat or searching after it, as `IsInCombat` reads it.
    public static let inCombat = SceneActorStatus(rawValue: 0x02)
    /// In the dialogue menu with the player.
    public static let inPlayerDialogue = SceneActorStatus(rawValue: 0x04)
    public static let observingCombat = SceneActorStatus(rawValue: 0x08)
}

@MainActor
extension SceneRuntime {
    /// The actors of `entry` whose alias is filled, with their record entry.
    func filledActors(of entry: CatalogScene) -> [(actor: SceneActor, reference: ReferenceKey)] {
        guard let quest = entry.quest else { return [] }
        return entry.scene.actors.compactMap { actor in
            guard
                actor.aliasID >= 0,
                let reference = dialogue.aliases.reference(
                    alias: UInt32(actor.aliasID), in: quest
                )
            else { return nil }
            return (actor, reference)
        }
    }

    /// Every actor a playing scene holds.
    public func actorsInPlayingScenes() -> Set<ReferenceKey> {
        Set(playingScenes().flatMap { entry in
            store.component(SceneRuntimeState.self, for: entry.key)?.holdsActors == true
                ? filledActors(of: entry).map(\.reference) : []
        })
    }

    /// The other playing scene that holds `reference`, if any.
    func holder(of reference: ReferenceKey, except scene: FormID? = nil) -> CatalogScene? {
        playingScenes().first { other in
            other.formID != scene
                && store.component(SceneRuntimeState.self, for: other.key)?.holdsActors == true
                && filledActors(of: other).contains { $0.reference == reference }
        }
    }

    /// The playing scene `reference` acts in, as `GetCurrentScene` reads it.
    public func scene(holding reference: ReferenceKey) -> FormID? {
        holder(of: reference)?.formID
    }

    /// Starts the scene after stopping every playing scene that shares an actor
    /// with it, as `ForceStart()` does.
    @discardableResult
    public func forceStart(_ id: FormID) throws -> [SceneEvent] {
        guard let entry = catalog.scene(id) else { throw SceneError.unknownScene(id) }
        guard !isPlaying(id) else { return [] }
        let mine = Set(filledActors(of: entry).map(\.reference))
        var events: [SceneEvent] = []
        for other in playingScenes() where other.formID != id {
            if filledActors(of: other).contains(where: { mine.contains($0.reference) }) {
                events += stop(other.formID, reason: .interrupted)
            }
        }
        return try events + start(id)
    }
}

@MainActor
extension SceneRuntime.Playback {
    /// False while a required actor is in another scene. An interruptible scene that
    /// holds one is stopped instead, so the new scene can go on.
    mutating func claimActors() -> Bool {
        var waits = false
        for (actor, reference) in runtime.filledActors(of: entry) where !actor.isOptional {
            guard let other = runtime.holder(of: reference, except: entry.formID) else { continue }
            if other.scene.flags.contains(.interruptible) {
                events += runtime.stop(other.formID, reason: .interrupted)
            } else {
                waits = true
            }
        }
        // Noted once, when the start call finds the actors busy, so ticks do not flood the trace.
        if waits, isNew {
            note(.waitingForActors)
        }
        return !waits
    }

    /// An optional actor that another scene holds is skipped, like a dead one.
    func isAvailable(_ reference: ReferenceKey, alias: Int32?) -> Bool {
        if runtime.host?.sceneActorStatus(reference).contains(.dead) == true {
            return false
        }
        let optional = scene.actors.first { $0.aliasID == alias }?.isOptional ?? false
        return !optional || runtime.holder(of: reference, except: entry.formID) == nil
    }

    /// False when the scene ended or is paused. Resuming moves the start time of
    /// each running action by the paused time, so a timer keeps what was left.
    mutating func applyActorBehavior() -> Bool {
        guard let host = runtime.host else { return true }
        var pauses = false
        for (actor, reference) in runtime.filledActors(of: entry) {
            let status = host.sceneActorStatus(reference)
            let flags = actor.behavior
            let ends = (status.contains(.dead) && flags.contains(.deathEnd))
                || (status.contains(.inCombat) && flags.contains(.combatEnd))
                || (status.contains(.inPlayerDialogue) && flags.contains(.dialogueEnd))
                || (status.contains(.observingCombat) && flags.contains(.observeCombatEnd))
            if ends {
                end(.actorBehavior)
                return false
            }
            pauses = pauses
                || (status.contains(.inCombat) && flags.contains(.combatPause))
                || (status.contains(.inPlayerDialogue) && flags.contains(.dialoguePause))
                || (status.contains(.observingCombat) && flags.contains(.observeCombatPause))
        }
        if pauses {
            if state.pausedAt == nil {
                state.pausedAt = runtime.now
                note(.paused)
            }
            return false
        }
        if let pausedAt = state.pausedAt {
            let shift = runtime.now - pausedAt
            state = SceneRuntimeState(
                phase: state.phase, phaseEntered: state.phaseEntered,
                running: state.running.map {
                    SceneActionProgress(
                        action: $0.action, startedAt: $0.startedAt + shift, duration: $0.duration
                    )
                },
                completed: state.completed
            )
            note(.resumed)
        }
        return true
    }
}
