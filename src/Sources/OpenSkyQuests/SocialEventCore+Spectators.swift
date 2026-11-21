// Watching a fight: the threat list, the fight area, the comments, and the back-off.
// docs/engine/random-conversations.md#what-a-watcher-does.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import simd

/// The box around every known attacker and target, each widened by its threat distance.
nonisolated struct SocialFightArea: Equatable {
    let centre: SIMD3<Float>
    let radius: Float

    init?(_ threats: [SocialThreat], actors: [ReferenceKey: SocialActor]) {
        var members: [(feet: SIMD3<Float>, reach: Float)] = []
        for threat in threats {
            guard let attacker = actors[threat.attacker] else { continue }
            let reach = attacker.fightsRanged
                ? SocialLimits.rangedThreatDistance : SocialLimits.meleeThreatDistance
            members.append((attacker.feet, reach))
            if let target = threat.target.flatMap({ actors[$0] }) {
                let own = target.fightsRanged && target.isInCombat
                    ? SocialLimits.rangedThreatDistance : reach
                members.append((target.feet, own))
            }
        }
        guard let first = members.first else { return nil }
        var low = first.feet - SIMD3(repeating: first.reach)
        var high = first.feet + SIMD3(repeating: first.reach)
        for member in members.dropFirst() {
            low = simd_min(low, member.feet - SIMD3(repeating: member.reach))
            high = simd_max(high, member.feet + SIMD3(repeating: member.reach))
        }
        let centre = (low + high) / 2
        self.centre = centre
        radius = members.map { simd_distance($0.feet, centre) + $0.reach }.max() ?? 0
    }
}

nonisolated extension SocialEventCore {
    /// What every watch in one pass reads.
    struct WatchPass {
        let byKey: [ReferenceKey: SocialActor]
        let fighters: [SocialActor]
        let now: Double
        let elapsed: Double
        let reacts: Bool
        let settings: SocialSettings
    }

    /// The settings and the clock of one pass over the watches.
    struct WatchTiming {
        let settings: SocialSettings
        let elapsed: Double
        let reacts: Bool
    }

    /// Starts, keeps, and ends each watch, and rolls the comments.
    static func spectators(
        _ frame: SocialFrame, timing: WatchTiming,
        state: inout SocialState, canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialEventCommand] {
        let (settings, elapsed, reacts) = (timing.settings, timing.elapsed, timing.reacts)
        let actors = frame.actors
        let fighters = actors.filter { $0.key != .player && !$0.isDead && $0.isInCombat }
        guard !fighters.isEmpty || !state.spectators.isEmpty else { return [] }
        let pass = WatchPass(
            byKey: Dictionary(actors.map { ($0.key, $0) }) { first, _ in first },
            fighters: fighters, now: frame.now, elapsed: elapsed, reacts: reacts,
            settings: settings
        )
        var commands: [SocialEventCommand] = []
        for (key, watch) in state.spectators.sorted(by: { $0.key < $1.key }) {
            commands += keepWatching((key, watch), pass: pass, state: &state, canSee: canSee)
        }
        guard reacts else { return commands }
        for watcher in actors where state.spectators[watcher.key] == nil && canWatch(watcher)
            && state.finders[watcher.key] == nil
        {
            let threats = detected(by: watcher, pass: pass, canSee: canSee)
            guard
                let area = SocialFightArea(threats, actors: pass.byKey),
                simd_distance(watcher.feet, area.centre) < SocialLimits.watchDistance
            else { continue }
            state.spectators[watcher.key] = SocialSpectator(
                threats: threats, startedAt: frame.now, inScene: watcher.isInScene
            )
            guard !watcher.isInScene else { continue }
            commands += leaveConversation(watcher.key, settings: settings, state: &state)
            if watcher.posture != .standing {
                commands.append(.standUp(watcher.key))
            }
            commands += [.hold(watcher.key), .look(watcher.key, at: threats[0].attacker)]
        }
        return commands
    }

    /// Alive, not the player, not fighting or fled, and flag 0x04. A watcher in a scene
    /// keeps its scene and only reports that it watches.
    static func canWatch(_ actor: SocialActor) -> Bool {
        !actor.isDead && actor.key != .player && !actor.isInCombat && actor.combatTarget == nil
            && actor.observesCombat
    }

    /// The fighters the watcher detects now that do not fight the watcher.
    private static func detected(
        by watcher: SocialActor, pass: WatchPass, canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialThreat] {
        pass.fighters.filter { fighter in
            fighter.combatTarget != watcher.key
                && simd_distance(fighter.feet, watcher.feet) <= SocialLimits.watchDistance
                && canSee(watcher, fighter)
        }.map { SocialThreat(attacker: $0.key, target: $0.combatTarget, lastSeen: pass.now) }
    }

    private static func keepWatching(
        _ entry: (key: ReferenceKey, watch: SocialSpectator), pass: WatchPass,
        state: inout SocialState, canSee: (SocialActor, SocialActor) -> Bool
    ) -> [SocialEventCommand] {
        let key = entry.key
        var watch = entry.watch
        guard let watcher = pass.byKey[key], !watcher.isDead, !watcher.isInCombat else {
            return stopWatching(key, watch, state: &state)
        }
        refreshThreats(&watch, watcher: watcher, pass: pass, canSee: canSee)
        guard
            let area = SocialFightArea(watch.threats, actors: pass.byKey),
            simd_distance(watcher.feet, area.centre) < SocialLimits.watchDistance
        else { return stopWatching(key, watch, state: &state) }
        var commands: [SocialEventCommand] = []
        let attacker = watch.threats[0].attacker
        watch.commentTimer -= pass.elapsed
        if
            watch.commentTimer <= 0,
            Float(state.random.next() % UInt64(10000)) / Float(100)
            < pass.settings.observeCombatChance
        {
            watch.commentTimer = SocialLimits.commentSeconds
            commands.append(.say("OBCO", key, lookAt: attacker))
        }
        if !watch.inScene {
            commands += step(&watch, watcher: watcher, area: area, now: pass.now)
        }
        state.spectators[key] = watch
        return commands
    }

    /// A detected attacker is refreshed every 2 s, a new one joins on a reaction pass,
    /// and one not refreshed for `fAISpectatorRememberThreatTimer` is dropped.
    private static func refreshThreats(
        _ watch: inout SocialSpectator, watcher: SocialActor, pass: WatchPass,
        canSee: (SocialActor, SocialActor) -> Bool
    ) {
        for index in watch.threats.indices {
            let threat = watch.threats[index]
            guard
                pass.now - threat.lastSeen >= SocialLimits.threatRefreshSeconds,
                let fighter = pass.byKey[threat.attacker],
                !fighter.isDead, fighter.isInCombat, fighter.combatTarget != watcher.key,
                canSee(watcher, fighter)
            else { continue }
            watch.threats[index].lastSeen = pass.now
            watch.threats[index].target = fighter.combatTarget
        }
        if pass.reacts {
            let known = Set(watch.threats.map(\.attacker))
            watch.threats += detected(by: watcher, pass: pass, canSee: canSee)
                .filter { !known.contains($0.attacker) }
        }
        let remember = Double(pass.settings.spectatorRememberSeconds)
        watch.threats.removeAll { pass.now - $0.lastSeen > remember }
    }

    /// Every 1.5 s: look at the first attacker, and a still watcher inside the fight
    /// radius backs off to 128 units outside it, then faces the centre.
    private static func step(
        _ watch: inout SocialSpectator, watcher: SocialActor, area: SocialFightArea, now: Double
    ) -> [SocialEventCommand] {
        var commands: [SocialEventCommand] = []
        if watch.facesCentre {
            commands.append(.face(watcher.key, toward: area.centre))
        }
        guard now - watch.lastStep >= SocialLimits.watchStepSeconds else { return commands }
        let moved = watch.lastStepFeet.map {
            isMoving(from: $0, at: watch.lastStep, to: watcher.feet, now: now)
        } ?? false
        watch.lastStep = now
        watch.lastStepFeet = watcher.feet
        commands.append(.look(watcher.key, at: watch.threats[0].attacker))
        guard !moved else { return commands }
        if watch.backOffGoal != nil {
            watch.backOffGoal = nil
            watch.facesCentre = true
            commands += [.stopWalking(watcher.key), .hold(watcher.key)]
        }
        var away = watcher.feet - area.centre
        away.z = 0
        let distance = simd_length(away)
        guard distance < area.radius else { return commands }
        let direction = distance > 0 ? away / distance : SIMD3<Float>(1, 0, 0)
        var goal = area.centre + direction * (area.radius + SocialLimits.watchBackOff)
        goal.z = watcher.feet.z
        watch.backOffGoal = goal
        watch.facesCentre = false
        commands += [.sheathe(watcher.key), .walk(watcher.key, to: goal)]
        return commands
    }

    private static func stopWatching(
        _ key: ReferenceKey, _ watch: SocialSpectator, state: inout SocialState
    ) -> [SocialEventCommand] {
        state.spectators[key] = nil
        guard !watch.inScene else { return [] }
        let walk: [SocialEventCommand] = watch.backOffGoal == nil ? [] : [.stopWalking(key)]
        return walk + [.release(key), .look(key, at: nil)]
    }
}
