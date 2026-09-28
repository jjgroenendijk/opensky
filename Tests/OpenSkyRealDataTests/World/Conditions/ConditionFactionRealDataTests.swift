// Env-gated acceptance for the faction and relationship condition functions
// (issue #508, roadmap item 21.4), over the user's own read-only load order.
//
// Two questions, both asked with vanilla's own bytes:
//
// 1. Does a *real* authored `GetInFaction` condition — one lifted out of a real
//    `INFO` record, not one this suite composed — answer truthfully about a real
//    Whiterun guard? The guard is located the same production way
//    `WhiterunGuardFixture` locates it, its memberships are seeded from its own
//    `SNAM` run by the production `FactionRuntime`, and the condition is
//    evaluated by the production `ConditionEvaluator`.
// 2. What do the six new functions add to the registry's reach over the whole
//    load order? That is the coverage delta the issue asks to be recorded.
//
// Aggregate counts, editor IDs and derived verdicts only — no game bytes leave
// the run (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import OpenSky
import Testing

struct ConditionFactionRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// The six raw indices item 21.4 registers, from xEdit's TES5 condition
    /// table: `GetFactionRankDifference`, `GetInFaction`, `GetFactionRank`,
    /// `GetRelationshipRank`, `GetFactionRelation` and `IsHostileToActor`.
    private static let factionIndices: Set<UInt16> = [60, 71, 73, 403, 449, 719]

    /// The two crime-gold halves added after this delta was measured (issue
    /// #573): `GetCrimeGoldViolent` and `GetCrimeGoldNonviolent`. Subtracted
    /// out so the delta keeps pinning the faction step alone. `GetCrimeGold`
    /// (issue #504) landed first and is already inside the numbers below.
    private static let laterIndices: Set<UInt16> = [375, 376]

    private static let guardEditorIDPrefix = "GuardWhiterun"

    // MARK: - The authored condition

    /// One real guard, its seeded memberships, and the condition seam over them.
    @MainActor
    private struct Harness {
        let guardKey: ReferenceKey
        let editorID: String
        let memberships: [ResolvedFaction]
        let seam: FactionConditionResolution
        let plugin: String
        let factions: FactionStore
    }

    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func aVanillaGetInFactionConditionAnswersForTheWhiterunGuard() throws {
        let root = try #require(Self.dataRoot)
        let harness = try Self.harness(root: root)
        let memberKeys = Set(harness.memberships.map { ReferenceKey(resolved: $0.id) })
        #expect(!memberKeys.isEmpty, "the guard's SNAM run seeded nothing")
        print(
            "[INFO] \(harness.editorID) \(harness.guardKey) is in "
                + "\(harness.memberships.map { $0.editorID ?? $0.id.description }.sorted())"
        )

        let authored = try Self.authoredInFactionConditions(root: root, harness: harness)
        print(
            "[INFO] authored GetInFaction conditions comparing equal to 1: "
                + "\(authored.member.count) naming a faction this guard is in, "
                + "\(authored.other.count) naming one it is not"
        )

        // A condition vanilla wrote about a faction this guard really is in has
        // to come out true, with nothing tallied.
        let joined = try #require(authored.member.first, "no vanilla record asks this")
        let inFaction = Self.evaluate(joined, harness: harness)
        #expect(inFaction.outcome == .true)
        #expect(inFaction.tally.isClean)

        // And one about a faction it is not in has to come out *conclusively*
        // false — a real answer, not a reason-tagged one.
        let stranger = try #require(authored.other.first)
        let notInFaction = Self.evaluate(stranger, harness: harness)
        #expect(!notInFaction.outcome.isTrue)
        #expect(notInFaction.outcome.isConclusive)
        #expect(notInFaction.tally.unavailableFactions == 0)
    }

    /// The rank the same guard holds reads back through `GetFactionRank`, and a
    /// faction it is not in answers the documented -1 rather than a gap.
    @Test(.enabled(if: Self.dataRoot != nil))
    @MainActor
    func getFactionRankAnswersTheSeededRank() throws {
        let root = try #require(Self.dataRoot)
        let harness = try Self.harness(root: root)
        let membership = try #require(harness.memberships.first)
        let key = ReferenceKey(resolved: membership.id)
        let rank = try #require(harness.seam.rank(of: harness.guardKey, in: key))

        let result = try Self.evaluate(
            Self.condition(
                index: 73,
                parameter1: membership.id.objectID,
                comparison: 0,
                value: Float(rank)
            ),
            harness: harness
        )

        #expect(result.outcome == .true)
        #expect(result.tally.isClean)
    }

    // MARK: - The coverage delta

    @Test(.enabled(if: Self.dataRoot != nil))
    func recordsTheConditionCoverageDelta() throws {
        let root = try #require(Self.dataRoot)
        let coverage = Self.sweep(plugins: ActivePluginFiles.load(root: root))
        let registry = ConditionFunctionRegistry.standard
        let later = Self.laterIndices.reduce(0) { $0 + coverage.conditions(of: $1) }
        let after = coverage.implementedCount(in: registry) - later
        let added = Self.factionIndices.reduce(0) { $0 + coverage.conditions(of: $1) }
        let before = after - added

        // Measured 2026-09-08 against the active load order of the five masters
        // plus this install's Creation Club plugins. `GetInFaction` alone is
        // 9,028 of the 10,020, which is why the faction model was the largest
        // single block of unanswered dialogue conditions left.
        #expect(coverage.total == 118_494)
        #expect(before == 79630)
        #expect(added == 10020)
        #expect(after == 89650)
        // `GetFactionRankDifference` is registered and this load order never
        // asks it — the only one of the six with no vanilla caller. It stays
        // installed because its backing is the same membership lookup its two
        // siblings use, so leaving it out would be a gap with no saving.
        #expect(coverage.conditions(of: 60) == 0)
        for index in Self.factionIndices.subtracting([60]).sorted() {
            #expect(coverage.conditions(of: index) > 0)
        }
        for index in Self.factionIndices.sorted() {
            print(
                "[INFO] answered \(registry.name(for: index)): "
                    + "\(coverage.conditions(of: index))"
            )
        }
        print(
            "[INFO] faction condition coverage \(before)/\(coverage.total) -> "
                + "\(after)/\(coverage.total)"
        )
    }

    // MARK: - Harness

    @MainActor
    private static func harness(root: GameDataRoot) throws -> Harness {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let plugin = esmURL.lastPathComponent
        let file = try ESMFile(url: esmURL)
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let templates = ActorTemplateResolver.build(from: file, localized: localized)
        let factions = FactionStoreLoader.load(root: root, baseFile: file)
        let relationships = RelationshipStoreLoader.load(root: root, baseFile: file)
        let base = try #require(
            templates.actors.values
                .filter { $0.editorID?.hasPrefix(guardEditorIDPrefix) == true }
                .min { $0.formID.rawValue < $1.formID.rawValue },
            "no Whiterun guard base in this load order"
        )
        var runtime = FactionRuntime(
            store: WorldStateStore(),
            factions: factions,
            derivation: HostilityDerivation(
                relations: FactionRelationIndex(store: factions),
                relationships: relationships
            ),
            baselines: ActorFactionBaselineResolver(templates: templates),
            pluginName: plugin
        )
        let holder = ActorValueHolder(
            key: .plugin(name: plugin.lowercased(), objectID: base.formID.objectID),
            subject: .actor(base: base.formID),
            cell: nil
        )
        runtime.seed(holder)
        return Harness(
            guardKey: holder.key,
            editorID: base.editorID ?? base.formID.description,
            memberships: runtime.resolvedFactions(of: holder.key),
            seam: FactionConditionResolution(
                factions: factions,
                sourcePlugin: plugin,
                derivation: runtime.derivation,
                profiles: [holder.key: runtime.profile(of: holder)]
            ),
            plugin: plugin,
            factions: factions
        )
    }

    /// Real `GetInFaction` conditions lifted out of the load order, split by
    /// whether the faction they name is one this guard belongs to.
    ///
    /// Only the `== 1` form is taken, which is what makes the expected answer
    /// knowable without re-deriving it from the operator: the condition asks
    /// "is the subject in this faction", so it is true exactly when the guard is
    /// a member.
    @MainActor
    private static func authoredInFactionConditions(
        root: GameDataRoot,
        harness: Harness
    ) throws -> (member: [Condition], other: [Condition]) {
        let memberKeys = Set(harness.memberships.map { ReferenceKey(resolved: $0.id) })
        var member: [Condition] = []
        var other: [Condition] = []
        for plugin in ActivePluginFiles.load(root: root) {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                guard record.type == "INFO", let fields = try? record.fields() else {
                    return true
                }
                var list = ConditionList()
                for field in fields {
                    _ = try? list.decode(field: field)
                }
                for condition in list.conditions where isSimpleInFaction(condition) {
                    guard
                        let key = harness.seam.key(of: condition.parameter1.asFormID)
                    else { continue }
                    if memberKeys.contains(key) {
                        member.append(condition)
                    } else {
                        other.append(condition)
                    }
                }
                return true
            }
        }
        return (member, other)
    }

    /// `GetInFaction` compared equal to 1, on the Subject run-on, with no alias
    /// override and no subject/target swap — the plain form.
    private static func isSimpleInFaction(_ condition: Condition) -> Bool {
        guard
            condition.functionIndex == 71,
            condition.comparison == .equal,
            condition.runOn == .subject,
            condition.flags.isDisjoint(with: [.useAliases, .swapSubjectAndTarget]),
            case let .value(value) = condition.comparisonValue,
            value == 1
        else { return false }
        return true
    }

    @MainActor
    private static func evaluate(
        _ condition: Condition,
        harness: Harness
    ) -> (outcome: ConditionOutcome, tally: ConditionTally) {
        var evaluator = ConditionEvaluator(context: ConditionContext(
            factions: harness.seam,
            subject: harness.guardKey
        ))
        let outcome = evaluator.evaluate(condition)
        return (outcome, evaluator.tally)
    }

    /// One synthetic CTDA over a real faction FormID, for the cases no vanilla
    /// record happens to ask.
    private static func condition(
        index: UInt16,
        parameter1: UInt32,
        comparison: UInt8,
        value: Float
    ) throws -> Condition {
        var data = Data([comparison << 5, 0, 0, 0])
        data.appendUInt32(value.bitPattern)
        data.appendUInt16(index)
        data.appendUInt16(0)
        data.appendUInt32(parameter1)
        data.appendUInt32(0)
        data.appendUInt32(0)
        data.appendUInt32(0)
        data.appendUInt32(UInt32(bitPattern: Int32(-1)))
        guard
            let condition = try Condition(ctda: ESMField(type: "CTDA", data: data))
        else {
            throw ESMError.malformed("fixture CTDA did not decode")
        }
        return condition
    }

    private static func sweep(
        plugins: [(name: String, file: ESMFile)]
    ) -> ConditionCoverage {
        var coverage = ConditionCoverage()
        for plugin in plugins {
            ESMWalk.forEachRecord(in: plugin.file) { record in
                guard let fields = try? record.fields() else { return true }
                var list = ConditionList()
                for field in fields {
                    _ = try? list.decode(field: field)
                }
                for condition in list.conditions {
                    coverage.record(condition)
                }
                return true
            }
        }
        return coverage
    }
}
