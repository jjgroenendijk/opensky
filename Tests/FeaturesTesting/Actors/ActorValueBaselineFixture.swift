// Baselines for suites that need actor values but not the record rules that
// derive them.

import OpenSkyGameData

public enum ActorValueBaselineFixture {
    /// Every subject starts at `maximum` of every value and regenerates nothing,
    /// so a number in a suite is only ever what the suite spent.
    public static func flat(maximum: Float = 100) -> ActorValueBaselineResolver {
        ActorValueBaselineResolver(
            fallback: ActorValueBaseline(
                maximums: ActorValues(repeating: maximum),
                regenPercentPerSecond: .zero
            )
        )
    }
}
