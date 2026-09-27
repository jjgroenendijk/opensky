// Env-gated character-leveling checks over the user's read-only active load
// order (issue #499, roadmap item 20.6): the four GMSTs the curve and the
// level-up rewards read, and one real perk-point spend climbing a vanilla tree
// from its entry node. Numbers and editor IDs only — no game bytes leave the
// run.

import Foundation
@testable import opensky
import Testing

struct CharacterLevelingRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The first two ranks of the One-Handed damage chain, and the perk their
    /// tree box hangs off. Editor IDs rather than FormIDs, so this reads as the
    /// names the Creation Kit shows.
    private static let firstRank = "Armsman00"
    private static let secondRank = "Armsman20"
    private static let oneHandedInformation = "AVOneHanded"

    /// The four settings, as `Skyrim.esm` authors them — which is exactly what
    /// `CharacterLevelSettings.documentedDefaults` carries, so a load order
    /// that retunes any of them is visible here rather than silently absorbed.
    @Test(.enabled(if: Self.dataRoot != nil))
    func theLevelSettingsMatchTheDocumentedNumbers() throws {
        let root = try #require(Self.dataRoot)
        let store = GameSettingLoader.load(root: root)

        let settings = CharacterLevelSettings.resolve(store: store)

        #expect(settings.levelUpBase == 75)
        #expect(settings.levelUpMultiplier == 25)
        #expect(settings.attributeIncrement == 10)
        #expect(settings.carryWeightPerStaminaPick == 5)
        // The two worked examples UESP prints, against the install's own
        // numbers rather than against the fallbacks.
        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 1, settings: settings) == 100)
        #expect(CharacterLeveling.experienceForNextLevel(atLevel: 49, settings: settings) == 1300)
    }

    /// The AVIF perk trees this install carries, and the shape a spend depends
    /// on: every skill tree has an entry node granting no perk, and the box it
    /// reaches is buyable with nothing owned.
    @Test(.enabled(if: Self.dataRoot != nil))
    func everySkillTreeHasAnEntryNodeReachingABuyableBox() throws {
        let root = try #require(Self.dataRoot)
        let information = ActorValueInformationStoreLoader.load(root: root)
        let perks = PerkStoreLoader.load(root: root)
        let trees = PerkTreeIndex(information: information, perks: perks)

        #expect(trees.count > 100)
        var rootReachable = 0
        for record in information.perkTreeRecords {
            let boxes = record.information.perkTree.compactMap { node -> PerkTreePlacement? in
                guard
                    let link = node.perk,
                    let resolved = perks.resolve(link, fromPlugin: record.sourcePlugin)
                else { return nil }
                return trees.placement(of: ReferenceKey(resolved: resolved.id))
            }
            #expect(!boxes.isEmpty)
            rootReachable += boxes.count { $0.reachableFromRoot }
        }
        // At least one box per tree hangs off its entry node, or nothing in
        // that tree could ever be bought.
        #expect(rootReachable >= information.perkTreeRecords.count)
    }

    /// One real spend, climbing the real One-Handed tree: `Armsman00` is
    /// buyable off the entry node, `Armsman20` is refused until both its rank
    /// predecessor is owned and One-Handed reaches the 20 its own `CTDA` run
    /// asks for.
    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
    func aVanillaRankChainIsClimbedInOrder() throws {
        let root = try #require(Self.dataRoot)
        let perks = PerkStoreLoader.load(root: root)
        let trees = PerkTreeIndex(
            information: ActorValueInformationStoreLoader.load(root: root), perks: perks
        )
        let first = try #require(perks.perk(editorID: Self.firstRank))
        let second = try #require(perks.perk(editorID: Self.secondRank))
        let firstKey = ReferenceKey(resolved: first.id)
        var runtime = PerkRuntime(store: WorldStateStore(), perks: perks)
        let validator = PerkTreeSpendValidator(runtime: runtime, trees: trees)

        // The chain head hangs off the entry node, so nothing gates it.
        #expect(validator.refusal(
            for: firstKey, on: .player, conditions: Self.conditions(oneHanded: 15)
        ) == nil)
        // Rank two is in no box of its own and is found through the head.
        #expect(validator.refusal(
            for: ReferenceKey(resolved: second.id),
            on: .player,
            conditions: Self.conditions(oneHanded: 100)
        ) == .previousRankMissing(firstKey))

        runtime.add(firstKey, to: .player)
        let owning = PerkTreeSpendValidator(runtime: runtime, trees: trees)

        // With rank one owned, only the skill requirement is left, and it is
        // the record's own `GetBaseActorValue One-Handed >= 20`.
        #expect(owning.refusal(
            for: ReferenceKey(resolved: second.id),
            on: .player,
            conditions: Self.conditions(oneHanded: 19)
        ) == .unmetCondition)
        #expect(owning.refusal(
            for: ReferenceKey(resolved: second.id),
            on: .player,
            conditions: Self.conditions(oneHanded: 20)
        ) == nil)
    }

    /// The install's own One-Handed AVIF record still carries a perk tree whose
    /// entry node grants no perk, which is the assumption the spend rules rest
    /// on.
    @Test(.enabled(if: Self.dataRoot != nil))
    func theOneHandedTreeStillHasANullEntryNode() throws {
        let root = try #require(Self.dataRoot)
        let information = ActorValueInformationStoreLoader.load(root: root)

        let record = try #require(
            information.information(editorID: Self.oneHandedInformation)
        )
        let entry = try #require(record.information.perkTree.first { $0.isRoot })

        #expect(entry.perk == nil)
        #expect(!entry.connections.isEmpty)
        #expect(record.information.perkTree.count > 1)
    }

    /// One player whose One-Handed base is stated, which is what a perk's own
    /// condition run is judged against.
    private static func conditions(oneHanded: Float) -> ConditionContext {
        ConditionContext(
            actors: ActorStateResolution(states: [
                .player: ActorConditionState(
                    current: ActorValues(repeating: 100),
                    maximums: ActorValues(repeating: 100),
                    generalBaseline: [ActorValueIdentity.firstSkillIndex: oneHanded],
                    isPlayer: true
                )
            ]),
            subject: .player
        )
    }
}
