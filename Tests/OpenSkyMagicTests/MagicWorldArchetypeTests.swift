// Banish, Command Summoned, the race change, Werewolf Feed, Grab Actor, and Guide over
// synthetic MGEF records. Semantics: the Creation Kit wiki Magic Effect page, cited at
// `MagicArchetypeRule`.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import simd
import Testing

@MainActor
struct MagicWorldArchetypeTests {
    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x0900)
    private static let rival = ReferenceKey.plugin(name: "base.esm", objectID: 0x0901)
    private static let summon = ReferenceKey.generated(1)

    /// Raw archetypes are xEdit's `wbArchtypeEnum`.
    private enum Effect {
        static let banish: UInt32 = 0x70
        static let command: UInt32 = 0x71
        static let werewolf: UInt32 = 0x72
        static let feed: UInt32 = 0x73
        static let grab: UInt32 = 0x74
        static let guide: UInt32 = 0x75
        static let race: UInt32 = 0x7A
        static let hazard: UInt32 = 0x7B
    }

    private struct Spec {
        let formID: UInt32
        let editorID: String
        let archetype: UInt32
        var item: UInt32 = 0

        init(_ formID: UInt32, _ editorID: String, _ archetype: UInt32, item: UInt32 = 0) {
            self.formID = formID
            self.editorID = editorID
            self.archetype = archetype
            self.item = item
        }
    }

    private let world = FakeMagicWorld()

    private static var records: [Data] {
        let specs = [
            Spec(Effect.banish, "Banish", 42), Spec(Effect.command, "Command", 10),
            Spec(Effect.werewolf, "Werewolf", 36, item: Effect.race), Spec(Effect.feed, "Feed", 26),
            Spec(Effect.grab, "Grab", 45), Spec(Effect.guide, "Guide", 25, item: Effect.hazard)
        ]
        return specs.map { spec in
            ActiveEffectFixture.magicEffect(
                formID: spec.formID, editorID: spec.editorID, name: spec.editorID,
                data: ActiveEffectFixture.data(
                    associatedItem: spec.item, archetype: spec.archetype
                )
            )
        }
    }

    private func makeCoordinator() throws -> MagicCoordinator {
        let file = try ActiveEffectFixture.plugin(
            records: ActiveEffectFixture.effectRecords + ActiveEffectFixture.archetypeRecords
                + Self.records
        )
        for key in [Self.victim, Self.rival, Self.summon] {
            world.holders[key] = ActorValueHolder(
                key: key, subject: .actor(base: FormID(0x0F01)), cell: nil
            )
        }
        let coordinator = MagicCoordinator(world: world)
        coordinator.wireEffects(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        return coordinator
    }

    @discardableResult
    private static func cast(
        _ formID: UInt32, on target: ReferenceKey, by caster: ReferenceKey = .player,
        duration: UInt32 = 0, _ coordinator: MagicCoordinator
    ) -> [ActiveEffect] {
        guard let holder = coordinator.world.actorValueHolder(for: target) else { return [] }
        return coordinator.withEffects { runtime in
            runtime.apply(
                [MagicItemEffect(
                    effect: FormID(formID), magnitude: 10, area: 0, duration: duration,
                    conditions: ConditionList()
                )],
                fromPlugin: ActiveEffectFixture.pluginName,
                source: ActiveEffectSource(
                    kind: .spell, record: .plugin(name: "base.esm", objectID: 0x600)
                ),
                caster: caster,
                on: holder
            )
        } ?? []
    }

    // MARK: - Summons

    @Test func banishSendsASummonAway() throws {
        let coordinator = try makeCoordinator()
        Self.cast(ActiveEffectFixture.Archetype.summon, on: .player, duration: 60, coordinator)
        #expect(coordinator.commanded.map(\.actor) == [Self.summon])

        Self.cast(Effect.banish, on: Self.summon, by: Self.rival, coordinator)
        #expect(coordinator.commanded.isEmpty)
        #expect(world.releasedActors.map(\.actor) == [Self.summon])
    }

    /// Banish and Command Summoned work only on a summoned actor.
    @Test func banishRefusesAnActorNobodySummoned() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Effect.banish, on: Self.victim, coordinator)
        #expect(coordinator.effects?.tally.skips[.wrongTarget(.banish)] == 1)
        #expect(world.releasedActors.isEmpty)
    }

    @Test func commandSummonedHandsTheSummonToTheCaster() throws {
        let coordinator = try makeCoordinator()
        Self.cast(ActiveEffectFixture.Archetype.summon, on: .player, duration: 60, coordinator)
        Self.cast(Effect.command, on: Self.summon, by: Self.rival, coordinator)
        #expect(coordinator.commanded.map(\.caster) == [Self.rival])
        #expect(world.commandedBy.map(\.caster) == [Self.rival])
    }

    // MARK: - Race and feeding

    @Test func werewolfChangesTheRaceOnce() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Effect.werewolf, on: .player, duration: 10, coordinator)
        #expect(world.raceChanges.map(\.actor) == [.player])
        #expect(world.raceChanges.map(\.race.objectID) == [Effect.race])
    }

    @Test func aRaceChangeThatFailsIsRecorded() throws {
        let coordinator = try makeCoordinator()
        world.canChangeRace = false
        Self.cast(Effect.werewolf, on: .player, duration: 10, coordinator)
        #expect(world.raceChanges.isEmpty)
        #expect(coordinator.lastEffectAction == .raceChangeFailed(actor: world.actorName(.player)))
    }

    @Test func werewolfFeedNeedsACorpse() throws {
        let coordinator = try makeCoordinator()
        Self.cast(Effect.feed, on: Self.victim, coordinator)
        #expect(world.eaten.isEmpty)
        #expect(coordinator.effects?.tally.skips[.wrongTarget(.werewolfFeed)] == 1)

        world.dead = [Self.victim]
        Self.cast(Effect.feed, on: Self.victim, coordinator)
        #expect(world.eaten == [Self.victim])
    }

    // MARK: - Grab Actor

    /// The grabbed actor floats `fMagicGrabActorMinDistance` along the caster's aim and
    /// is let go once no landing renews the hold.
    @Test func grabActorHoldsThenLetsGo() throws {
        let coordinator = try makeCoordinator()
        world.aimRays[.player] = MagicAimRay(origin: .zero, direction: SIMD3(0, 1, 0))
        Self.cast(Effect.grab, on: Self.victim, coordinator)
        #expect(coordinator.isGrabbed(Self.victim))
        #expect(coordinator.influence(of: Self.victim).isParalysed)

        _ = coordinator.advanceEffects(delta: 0.1)
        #expect(world.actorHolds.last?.point == SIMD3(0, 120, 0))

        for _ in 0 ..< 20 {
            _ = coordinator.advanceEffects(delta: 0.1)
        }
        #expect(!coordinator.isGrabbed(Self.victim))
        #expect(world.actorHolds.last?.actor == Self.victim)
        #expect(world.actorHolds.last.map { $0.point == nil } == true)
    }

    // MARK: - Guide

    @Test func guideWithoutAQuestTargetSaysSo() throws {
        let coordinator = try makeCoordinator()
        world.guide = .noMarker
        Self.cast(Effect.guide, on: .player, coordinator)
        #expect(coordinator.takeCommands()
            .contains {
                if case .notice = $0 {
                    true
                } else {
                    false
                }
            })
        #expect(world.placedHazards.isEmpty)
    }

    /// One hazard every `fMagicGuideSpacing` units along the path.
    @Test func guideLaysHazardsAlongThePath() throws {
        let coordinator = try makeCoordinator()
        world.guide = .path([.zero, SIMD3(0, 100, 0)])
        Self.cast(Effect.guide, on: .player, coordinator)
        #expect(world.placedHazards == [SIMD3(0, 46, 0), SIMD3(0, 92, 0)])
    }
}
