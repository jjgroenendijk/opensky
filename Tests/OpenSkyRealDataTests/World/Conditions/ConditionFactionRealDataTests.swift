// Env-gated acceptance for the faction and relationship condition functions
// over the user's load order. It checks that a real authored `GetInFaction`
// condition answers truthfully about a real Whiterun guard, located and seeded
// the production way, and records what the six faction functions add to the
// registry's reach. Only counts, editor IDs and verdicts leave the run.

import FormatsCoreTesting
import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFactions
@testable import OpenSkyFactionsInterface
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

struct ConditionFactionRealDataTests {
    /// The six raw indices the faction step registers, from xEdit's TES5 condition
    /// table: `GetFactionRankDifference`, `GetInFaction`, `GetFactionRank`,
    /// `GetRelationshipRank`, `GetFactionRelation` and `IsHostileToActor`.
    private static let factionIndices: Set<UInt16> = [60, 71, 73, 403, 449, 719]

    /// `GetCrimeGoldViolent`, `GetCrimeGoldNonviolent`, `GetItemCount`, `GetEventData`, and
    /// the hand and child checks, subtracted so the delta measures the faction functions
    /// alone. `GetCrimeGold` is already inside the numbers below.
    private static let laterIndices: Set<UInt16> = [375, 376, 47, 65, 576, 102, 103, 365]

    private static let guardEditorIDPrefix = "GuardWhiterun"

    // MARK: - The authored condition

    /// One real guard, its seeded memberships, and the condition seam over them.
    @MainActor
    private struct Harness {
        let guardKey: ReferenceKey
        let editorID: String
        let memberships: [ResolvedFaction]
        let seam: FactionConditionResolution
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func aVanillaGetInFactionConditionAnswersForTheWhiterunGuard() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    @MainActor
    func getFactionRankAnswersTheSeededRank() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
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

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func recordsTheConditionCoverageDelta() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let coverage = ConditionCoverage.sweep(plugins: ActivePluginFiles.load(root: root))
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
        #expect(before == 79823)
        #expect(added == 10020)
        #expect(after == 89843)
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
            )
        )
    }

    /// Real `GetInFaction` conditions from the load order, split by whether the
    /// guard belongs to the named faction. Only the `== 1` form is taken, so the
    /// expected answer is membership itself.
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
}
