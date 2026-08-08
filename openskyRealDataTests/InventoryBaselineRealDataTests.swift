// Env-gated inventory-baseline sweep over the user's own Skyrim SE install
// (read-only external input, never committed — AGENTS.md Legal & IP).
// Skips automatically when OPENSKY_DATA_ROOT is unset or unresolvable.
// Summaries print and are written to gitignored logs/. Run with
// `make realtest T=InventoryBaselineRealDataTests/sweepsEveryContainerBaseline()`.
//
// A synthetic fixture cannot tell you whether the leveled expansion terminates
// on the real data, or whether the vanilla gold form is what this engine thinks
// it is. That is what this sweep is for.

import Foundation
@testable import opensky
import Testing

struct InventoryBaselineRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// Resolves a baseline for every CONT and every NPC_ in Skyrim.esm.
    ///
    /// The assertions are invariants rather than counts: expansion terminates,
    /// every produced stack is positive and unique, an actor's equipped set is
    /// a subset of what it carries, and the gold form this engine defaults to
    /// really is a weightless MISC record called `Gold001`.
    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryContainerBaseline() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let resolver = InventoryBaselineResolver.build(from: file)

        #expect(!resolver.items.definitions.isEmpty, "no item definitions indexed")
        #expect(!resolver.leveledItems.isEmpty, "no LVLI records indexed")
        #expect(!resolver.outfits.isEmpty, "no OTFT records indexed")

        let containers = sweep(
            ids: resolver.items.containers.keys.sorted(),
            resolver: resolver
        ) { .container(base: $0) }
        let actors = sweep(
            ids: resolver.actors.actors.keys.sorted(),
            resolver: resolver
        ) { .actor(base: $0) }

        #expect(containers.violations.isEmpty, "container baselines: \(containers.violations)")
        #expect(actors.violations.isEmpty, "actor baselines: \(actors.violations)")
        #expect(containers.nonEmpty > 0, "no container resolved to any contents")
        #expect(actors.nonEmpty > 0, "no actor resolved to an outfit")

        // The gold form `InventoryRuntime` defaults to, checked against the
        // install rather than trusted from memory.
        let gold = try #require(
            resolver.items.definition(InventoryRuntime.vanillaGoldFormID),
            "the default gold form is not an indexed item"
        )
        #expect(gold.editorID == "Gold001")
        #expect(gold.family == .miscellaneous)
        #expect(gold.weight == 0)

        let summary = """
        [INFO] Skyrim.esm inventory baselines: \(containers.resolved) CONT resolved \
        (\(containers.nonEmpty) non-empty, \(containers.stacks) stacks, \
        \(containers.items) items)
        [INFO] actors: \(actors.resolved) NPC_ resolved (\(actors.nonEmpty) with an outfit, \
        \(actors.stacks) stacks, \(actors.items) items)
        [INFO] indexes: \(resolver.items.definitions.count) items, \
        \(resolver.items.containers.count) containers, \
        \(resolver.leveledItems.count) LVLI, \(resolver.outfits.count) OTFT
        [INFO] gold: \(gold.editorID ?? "?") \(gold.formID) value \(gold.value) \
        weight \(gold.weight)
        """
        print(summary)
        try? summary.write(to: Self.logURL, atomically: true, encoding: .utf8)
    }

    private struct SweepResult {
        var resolved = 0
        var nonEmpty = 0
        var stacks = 0
        var items = 0
        var violations: [String] = []
    }

    /// Resolves one baseline per id and checks the component's invariants held
    /// all the way through expansion. Violations are collected rather than
    /// asserted per id, so a failure names the first few offenders instead of
    /// stopping at one.
    private func sweep(
        ids: [UInt32],
        resolver: InventoryBaselineResolver,
        owner: (FormID) -> InventoryOwner
    ) -> SweepResult {
        var result = SweepResult()
        for id in ids {
            let baseline = resolver.baseline(for: owner(FormID(id)))
            result.resolved += 1
            result.stacks += baseline.stacks.count
            result.items += baseline.totalCount
            if !baseline.isEmpty {
                result.nonEmpty += 1
            }
            guard result.violations.count < 5 else { continue }
            result.violations.append(contentsOf: Self.violations(of: baseline, id: FormID(id)))
        }
        return result
    }

    /// The invariants `ReferenceInventoryState` promises, restated as checks so
    /// the sweep proves them on data no fixture author chose.
    private static func violations(
        of baseline: ReferenceInventoryState,
        id: FormID
    ) -> [String] {
        var found: [String] = []
        let items = baseline.stacks.map(\.item.rawValue)
        if items != items.sorted() {
            found.append("\(id) stacks are not in FormID order")
        }
        if items.count != Set(items).count {
            found.append("\(id) has duplicate stacks")
        }
        if baseline.stacks.contains(where: { $0.count.signum() != 1 }) {
            found.append("\(id) has a non-positive stack")
        }
        let equipped = baseline.equipped.map(\.rawValue)
        if equipped != equipped.sorted() || equipped.count != Set(equipped).count {
            found.append("\(id) equipped set is unsorted or has duplicates")
        }
        if !Set(equipped).isSubset(of: Set(items)) {
            found.append("\(id) equips something it does not carry")
        }
        return found
    }

    private static var logURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
            .appending(path: "inventory-baseline-sweep.log")
    }
}
