// Picks the loading screen for a destination: the LSCRs whose conditions pass for
// the player standing in the destination, specific ones first, then one at random. The run-on
// rule and the census behind it: docs/formats/loading-screens.md#selection.

import Foundation
import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldConditions

nonisolated struct LoadScreenSelector: Sendable {
    /// The failing condition's name, or nil when the screen may show.
    typealias Check = @Sendable (ResolvedRecord<LoadScreen>) -> String?

    let screens: [ResolvedRecord<LoadScreen>]
    private let check: Check

    init(screens: [ResolvedRecord<LoadScreen>], check: @escaping Check) {
        self.screens = screens
        self.check = check
    }

    /// Screens in load order whose conditions pass.
    func passing() -> [ResolvedRecord<LoadScreen>] {
        screens.filter { check($0) == nil }
    }

    /// Whether a game is loaded when the screen is chosen.
    nonisolated enum GameState: Sendable {
        case noGame
        case gameLoaded
    }

    /// The screens the game picks from. Only a screen with a model counts. Before a
    /// game is loaded, the main menu screens count instead of the passing ones. A
    /// screen with conditions is specific: when one counts, only specific screens do.
    func candidates(_ state: GameState) -> [ResolvedRecord<LoadScreen>] {
        let shown = switch state {
        case .noGame: screens.filter(\.record.displaysInMainMenu)
        case .gameLoaded: passing()
        }
        let modelled = shown.filter { $0.record.model != nil }
        let specific = modelled.filter { !$0.record.conditions.isEmpty }
        return specific.isEmpty ? modelled : specific
    }

    /// One candidate, picked with the seeded generator.
    func pick(random: inout ConditionRandom) -> ResolvedRecord<LoadScreen>? {
        Self.pick(from: candidates(.gameLoaded), random: &random)
    }

    static func pick(
        from candidates: [ResolvedRecord<LoadScreen>], random: inout ConditionRandom
    ) -> ResolvedRecord<LoadScreen>? {
        guard !candidates.isEmpty else { return nil }
        return candidates[Int(random.next() % UInt64(candidates.count))]
    }

    /// The standard check: conditions run on the player, whose current
    /// location is `destination` while the screen is chosen.
    static func conditionCheck(
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
    init(store: PresentationRecordStore, check: @escaping Check) {
        self.init(screens: store.loadScreens.records, check: check)
    }
}
