// The clock plan the M10 acceptance suites run on (issue #166): one game hour per
// real second, driven half a real second at a time. Both test targets compile this
// folder, so the synthetic weather suite in openskyTests and the real-install suite
// in openskyRealDataTests are held to the same numbers instead of keeping two
// copies that could drift. See openskyTestSupport/AGENTS.md.

enum M10AcceptanceClock {
    static let fastTimescale: Float = 3600
    static let wallStep: Float = 0.5
    static let gameHoursPerStep: Float = 0.5
    static let steps = 90
    static let totalGameHours: Float = 45
    static let startHour: Float = 8
    /// Forty-five hours past 08:00 on the vanilla start date is 05:00, two days
    /// later — 19 Last Seed rather than 17.
    static let endHour: Float = 5
}
