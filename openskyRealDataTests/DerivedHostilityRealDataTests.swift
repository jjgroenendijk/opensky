// Env-gated acceptance for derived hostility over the user's own read-only
// load order (issue #503, roadmap item 21.3).
//
// The question the milestone asks: with nobody touching the dev panel, does a
// vanilla bandit come out hostile to the player and a vanilla Whiterun guard
// come out calm, through the same `FactionRuntime` the session wires? Both
// answers run through the production derivation — the load order's FACT and
// RELA stores, the actor's own resolved `AIDT`, and the memberships the runtime
// seeds out of the NPC_ record.
//
// Counts, editor IDs and derived verdicts only — no game bytes leave the run
// (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
@testable import opensky
import Testing

struct DerivedHostilityRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Vanilla's generic bandits are all named this way, so one is found
    /// without pinning a FormID a patch could move.
    private static let banditEditorIDPrefix = "EncBandit"
    /// Every vanilla Whiterun guard's base record is named this way
    /// (`WhiterunGuardFixture`).
    private static let guardEditorIDPrefix = "GuardWhiterun"

    /// Everything one session needs to ask the derivation a question.
    /// The device the Whiterun cell is built with. Nil on a machine with no
    /// Metal 4 GPU, which skips the one case that needs geometry.
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    @MainActor
    private struct Harness {
        var runtime: FactionRuntime
        let templates: ActorTemplateResolver
        let plugin: String
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func aVanillaBanditIsHostileToThePlayerAndAWhiterunGuardIsNot() throws {
        let root = try #require(Self.dataRoot)
        var harness = try Self.harness(root: root)

        let bandit = try #require(
            Self.lowestBase(withPrefix: Self.banditEditorIDPrefix, in: harness.templates)
        )
        let banditDecision = harness.runtime.decide(
            Self.holder(for: bandit, plugin: harness.plugin), toward: .player
        )
        Self.report(bandit, decision: banditDecision, harness: harness)
        #expect(banditDecision.isHostile)
        // Nothing wrote an override and no RELA names the pair, so the answer
        // has to have come out of the records: a stranger is Neutral, and only
        // a Very Aggressive or Frenzied actor attacks a stranger.
        #expect(banditDecision.source == .defaultNeutral)
        #expect(banditDecision.reaction == .neutral)

        let guardBase = try #require(
            Self.lowestBase(withPrefix: Self.guardEditorIDPrefix, in: harness.templates)
        )
        let guardDecision = harness.runtime.decide(
            Self.holder(for: guardBase, plugin: harness.plugin), toward: .player
        )
        Self.report(guardBase, decision: guardDecision, harness: harness)
        #expect(!guardDecision.isHostile)
        #expect(guardDecision.reaction == .neutral)
    }

    /// The same question about the guard the perception and combat suites
    /// fight, located the production way: its own cell built through
    /// `CellSceneBuilder`, and the lowest ACHR in it whose base is a guard.
    ///
    /// A placed reference rather than a base record, because that is the
    /// identity the combat loop actually holds — and because a derived answer
    /// that only worked for base records would be useless to it.
    @Test(.enabled(if: Self.dataRoot != nil && Self.device != nil))
    @MainActor
    func theWhiterunGuardInItsOwnCellDerivesAsNeutral() throws {
        let root = try #require(Self.dataRoot)
        let device = try #require(Self.device)
        var harness = try Self.harness(root: root)
        let scene = try WhiterunGuardFixture.buildCell(root: root, device: device)
        let located = try #require(
            WhiterunGuardFixture.locate(in: scene, templates: harness.templates)
        )
        let holder = ActorValueHolder(
            key: located.key,
            subject: .actor(base: located.actor.base),
            cell: nil
        )
        let decision = harness.runtime.decide(holder, toward: .player)
        print(
            "[INFO] placed \(located.editorID) \(located.key) reaction "
                + "\(decision.reaction.displayName) via \(decision.source.displayName), "
                + "hostility \(decision.hostility.displayName), memberships "
                + "\(harness.runtime.resolvedFactions(of: located.key).count)"
        )
        #expect(!decision.isHostile)
        #expect(!harness.runtime.resolvedFactions(of: located.key).isEmpty)

        // The panel toggle still wins, which is scope point 2's "override of
        // last resort": the same guard, made hostile by hand, stays hostile
        // even though every record says it should not be.
        harness.runtime.store.set(ActorCombatState.hostile, for: located.key)
        let overridden = harness.runtime.decide(holder, toward: .player)
        #expect(overridden.isHostile)
        #expect(overridden.source == .runtimeOverride)
    }

    // MARK: - Harness

    @MainActor
    private static func harness(root: GameDataRoot) throws -> Harness {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try ESMFile(url: esmURL)
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let templates = ActorTemplateResolver.build(from: file, localized: localized)
        let factions = FactionStoreLoader.load(root: root, baseFile: file)
        let relationships = RelationshipStoreLoader.load(root: root, baseFile: file)
        let relations = FactionRelationIndex(store: factions)
        let authored = factions.factions.values.reduce(0) { $0 + $1.faction.relations.count }
        print(
            "[INFO] factions \(factions.factions.count), authored XNAM \(authored), "
                + "indexed relations \(relations.count), "
                + "unnamed reactions \(relations.unnamedReactionCount), "
                + "relationships \(relationships.relationships.count)"
        )
        return Harness(
            runtime: FactionRuntime(
                store: WorldStateStore(),
                factions: factions,
                derivation: HostilityDerivation(
                    relations: relations,
                    relationships: relationships
                ),
                baselines: ActorFactionBaselineResolver(templates: templates),
                pluginName: esmURL.lastPathComponent
            ),
            templates: templates,
            plugin: esmURL.lastPathComponent
        )
    }

    /// The lowest-numbered NPC_ base whose editor ID starts with `prefix`, so a
    /// rerun picks the same actor.
    private static func lowestBase(
        withPrefix prefix: String,
        in templates: ActorTemplateResolver
    ) -> ActorBase? {
        templates.actors.values
            .filter { $0.editorID?.hasPrefix(prefix) == true }
            .min { $0.formID.rawValue < $1.formID.rawValue }
    }

    /// A base record as the holder the runtime takes.
    ///
    /// The base's own identity stands in for a placed reference: this suite is
    /// asking what the *records* derive to, and a base has no ACHR of its own
    /// to borrow a key from. The placed-reference path is covered by
    /// `theWhiterunGuardInItsOwnCellDerivesAsNeutral()`.
    private static func holder(for base: ActorBase, plugin: String) -> ActorValueHolder {
        ActorValueHolder(
            key: .plugin(name: plugin.lowercased(), objectID: base.formID.objectID),
            subject: .actor(base: base.formID),
            cell: nil
        )
    }

    @MainActor
    private static func report(
        _ base: ActorBase,
        decision: HostilityDecision,
        harness: Harness
    ) {
        let holder = holder(for: base, plugin: harness.plugin)
        let memberships = harness.runtime.resolvedFactions(of: holder.key)
            .map { $0.editorID ?? $0.id.description }
            .sorted()
        // The resolved AI data rather than the base record's own, because
        // `useAIData` may put it on a template further up the chain.
        let resolved = try? harness.templates.resolveFactions(base: base.formID)
        let aggression = resolved?.aiData.value?.aggression.description ?? "no AIDT"
        print(
            "[INFO] \(base.editorID ?? "-") aggression \(aggression), reaction "
                + "\(decision.reaction.displayName) via \(decision.source.displayName), "
                + "hostility \(decision.hostility.displayName), memberships \(memberships)"
        )
    }
}
