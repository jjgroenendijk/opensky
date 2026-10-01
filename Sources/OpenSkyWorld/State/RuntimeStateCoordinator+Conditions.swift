// Condition lists: the music tracks with at least one CTDA condition. The
// random stream restarts from its default seed on every evaluation, so an
// unchanged world gives the same answer.

import OpenSkyAudio
import OpenSkyConditions
import OpenSkyFormatsESM

extension RuntimeStateCoordinator {
    public var runtimeStateConditionSources: [String] {
        conditionSources().keys.sorted()
    }

    public func evaluateConditions(source: String) -> RuntimeStateConditionReport {
        guard let musicStore = world?.musicStore else {
            return .unavailable(
                source: source,
                message: "No music records are loaded, so no condition list can be evaluated."
            )
        }
        guard
            let formID = conditionSources()[source],
            let track = musicStore.musicTrack(formID)
        else {
            return .unavailable(source: source, message: "No condition list named \(source).")
        }
        var tally = conditionTally
        let report = RuntimeStateConditionRunner.report(
            source: source,
            conditions: track.conditions,
            context: conditionContext(),
            tally: &tally
        )
        conditionTally = tally
        return report
    }

    /// The live context with the crosshair as subject and target. Dialogue and
    /// perks use it too, and override what they need.
    public func conditionContext() -> ConditionContext {
        let globals = globalResolution()
        guard let world else { return ConditionContext(globals: globals) }
        return world.conditionContext(crosshair: entry(for: .currentTarget), globals: globals)
    }

    private func conditionSources() -> [String: FormID] {
        if let cached = conditionSourceFormIDs {
            return cached
        }
        let sources = RuntimeStateCore.conditionSources(world?.musicStore)
        conditionSourceFormIDs = sources
        return sources
    }
}
