// Picks the loading screen for a destination: every LSCR whose conditions pass
// for the player standing in the destination, then one at random. The run-on
// rule and the census behind it: docs/formats/loading-screens.md#selection.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct LoadScreenSelector: Sendable {
    /// The failing condition's name, or nil when the screen may show.
    public typealias Check = @Sendable (ResolvedRecord<LoadScreen>) -> String?

    public let screens: [ResolvedRecord<LoadScreen>]
    private let check: Check

    public init(screens: [ResolvedRecord<LoadScreen>], check: @escaping Check) {
        self.screens = screens
        self.check = check
    }

    /// Screens in load order whose conditions pass.
    public func passing() -> [ResolvedRecord<LoadScreen>] {
        screens.filter { check($0) == nil }
    }

    /// One passing screen, picked with the seeded generator.
    public func pick(random: inout ConditionRandom) -> ResolvedRecord<LoadScreen>? {
        let candidates = passing()
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(random.next() % UInt64(candidates.count))]
    }

    /// The standard check: conditions run on the player, whose current
    /// location is `destination` while the screen is chosen.
    public static func conditionCheck(
        context base: ConditionContext,
        destination: ResolvedFormID?
    ) -> Check {
        var context = base
        context.subject = .player
        let prepared = context
        return { screen in
            var context = prepared
            context.data = prepared.data.with(
                sourcePlugin: screen.sourcePlugin, location: destination, of: .player
            )
            var evaluator = ConditionEvaluator(context: context)
            return evaluator.firstFailure(in: screen.record.conditions)
                .map(evaluator.functionName(of:))
        }
    }
}

nonisolated extension LoadScreenSelector {
    public init(store: PresentationRecordStore, check: @escaping Check) {
        self.init(screens: store.loadScreens.records, check: check)
    }
}
