// Runtime faction membership (issue #503, roadmap item 21.3): seeding from the
// authored SNAM run, joining and leaving, the refusals, and the derived
// hostility the runtime answers through the world-state store. No game-derived
// bytes.

import Foundation
@testable import opensky
import Testing

@MainActor
struct FactionRuntimeTests {
    private typealias Fixture = HostilityFixture

    @Test
    func seedsAnActorFromItsAuthoredRunOnceAndCountsWhatDidNotResolve() throws {
        let runtime = try makeRuntime()
        let holder = holder(Fixture.Actors.bandit)

        let report = runtime.seed(
            [
                ActorBase.FactionMembership(faction: FormID(Fixture.Factions.bandit), rank: 3),
                ActorBase.FactionMembership(faction: FormID(0x999), rank: 0)
            ],
            fromPlugin: Fixture.pluginName,
            to: holder
        )

        #expect(report.added == [Fixture.key(Fixture.Factions.bandit)])
        #expect(report.unresolved == 1)
        #expect(runtime.isMember(holder.key, of: Fixture.key(Fixture.Factions.bandit)))
        #expect(runtime.rank(of: holder.key, in: Fixture.key(Fixture.Factions.bandit)) == 3)
        #expect(runtime.resolvedFactions(of: holder.key).map(\.editorID) == ["BanditFaction"])
    }

    /// The lazy caller seeds on every query, so the guard has to hold.
    @Test
    func seedingThroughTheHolderHappensOncePerSession() throws {
        var runtime = try makeRuntime(withBaselines: true)
        let holder = holder(Fixture.Actors.bandit)

        let first = runtime.seed(holder)
        let second = runtime.seed(holder)

        #expect(first.added == [Fixture.key(Fixture.Factions.bandit)])
        #expect(!first.wasAlreadySeeded)
        #expect(second.wasAlreadySeeded)
        #expect(second.added.isEmpty)
        #expect(runtime.state(of: holder.key).count == 1)
    }

    /// A promotion that happened before anything asked must survive the seed
    /// that arrives afterwards.
    @Test
    func aRuntimeRankSurvivesALaterSeed() throws {
        var runtime = try makeRuntime(withBaselines: true)
        let holder = holder(Fixture.Actors.bandit)
        let bandits = Fixture.key(Fixture.Factions.bandit)

        #expect(runtime.join(holder.key, to: bandits, rank: 9))
        _ = runtime.seed(holder)

        #expect(runtime.rank(of: holder.key, in: bandits) == 9)
    }

    @Test
    func joiningAndLeavingWriteThroughTheStoreAndDropAnEmptyComponent() throws {
        let runtime = try makeRuntime()
        let holder = holder(Fixture.Actors.townsfolk)
        let town = Fixture.key(Fixture.Factions.town)

        #expect(runtime.join(holder.key, to: town, rank: 1))
        #expect(!runtime.join(holder.key, to: town, rank: 1))
        #expect(runtime.store.component(ActorFactionState.self, for: holder.key) != nil)

        // Joining again at another rank moves the rank rather than adding a row.
        #expect(runtime.join(holder.key, to: town, rank: 2))
        #expect(runtime.state(of: holder.key).count == 1)
        #expect(runtime.rank(of: holder.key, in: town) == 2)

        #expect(runtime.leave(holder.key, from: town))
        #expect(!runtime.leave(holder.key, from: town))
        #expect(runtime.store.component(ActorFactionState.self, for: holder.key) == nil)
    }

    /// A key nothing resolves would be a permanent unreadable entry in the
    /// save, so a join is refused; a *stored* key is kept, which is the other
    /// direction of the same rule.
    @Test
    func joiningAFactionTheLoadOrderDoesNotCarryIsRefused() throws {
        let runtime = try makeRuntime()
        let holder = holder(Fixture.Actors.townsfolk)
        let missing = Fixture.key(0x999)

        #expect(!runtime.join(holder.key, to: missing))
        #expect(runtime.state(of: holder.key).isEmpty)

        runtime.store.set(
            ActorFactionState(memberships: [
                ActorFactionMembership(faction: missing, rank: 0)
            ]),
            for: holder.key
        )
        #expect(runtime.isMember(holder.key, of: missing))
        #expect(runtime.resolvedFactions(of: holder.key).isEmpty)
        #expect(runtime.leave(holder.key, from: missing))
    }

    /// The whole path an actual session takes: seed from the record, derive,
    /// and let the override win.
    @Test
    func decidesHostilityFromTheSeededMembershipsAndYieldsToAnOverride() throws {
        var runtime = try makeRuntime(
            withBaselines: true,
            aggression: 2,
            relations: [
                Fixture.Relation(Fixture.Factions.bandit, Fixture.Factions.guards, .enemy)
            ]
        )
        let bandit = holder(Fixture.Actors.bandit)

        let toward = runtime.decide(bandit, toward: .player)
        #expect(toward.isHostile)
        #expect(runtime.state(of: bandit.key).count == 1)

        runtime.store.set(ActorCombatState.neutral, for: bandit.key)
        let calmed = runtime.decide(bandit, toward: .player)
        #expect(!calmed.isHostile)
        #expect(calmed.source == .runtimeOverride)
    }

    /// Without a baseline resolver — every synthetic scene — seeding is a
    /// no-op rather than a crash, and nothing is written.
    @Test
    func aRuntimeWithoutBaselinesSeedsNothing() throws {
        var runtime = try makeRuntime()
        let holder = holder(Fixture.Actors.bandit)

        let report = runtime.seed(holder)

        #expect(report == .none)
        #expect(runtime.state(of: holder.key).isEmpty)
    }

    // MARK: - Fixture

    private func holder(_ base: UInt32) -> ActorValueHolder {
        ActorValueHolder(key: Fixture.key(base), subject: .actor(base: FormID(base)), cell: nil)
    }

    private func makeRuntime(
        withBaselines: Bool = false,
        aggression: UInt8 = 2,
        relations: [Fixture.Relation] = []
    ) throws -> FactionRuntime {
        let file = try Fixture.file(relations: relations)
        let store = FactionStore(plugins: [(Fixture.pluginName, file)])
        return FactionRuntime(
            store: WorldStateStore(),
            factions: store,
            derivation: HostilityDerivation(
                relations: FactionRelationIndex(store: store),
                relationships: RelationshipStore(plugins: [(Fixture.pluginName, file)])
            ),
            baselines: withBaselines ? baselines(aggression: aggression) : nil,
            pluginName: withBaselines ? Fixture.pluginName : nil
        )
    }

    /// One bandit base whose record authors the bandit faction and an
    /// aggression, resolved the way the session resolves it.
    private func baselines(aggression: UInt8) -> ActorFactionBaselineResolver {
        let bandit = try? ActorBase(
            record: FactionFixture.decode(FactionFixture.actor(
                formID: Fixture.Actors.bandit,
                editorID: "Bandit",
                factions: [(Fixture.Factions.bandit, 0)],
                aiData: FactionFixture.aiData(aggression: aggression)
            )),
            localized: false
        )
        let actors = [bandit].compactMap(\.self)
        return ActorFactionBaselineResolver(templates: ActorTemplateResolver(
            actors: Dictionary(uniqueKeysWithValues: actors.map { ($0.formID.rawValue, $0) }),
            leveledActors: [:]
        ))
    }
}
