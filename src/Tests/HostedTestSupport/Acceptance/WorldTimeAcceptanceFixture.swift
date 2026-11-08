// The clock plan for the runtime-state acceptance suites: one game hour per
// real second, in half-second steps. Both test targets compile this, so the
// synthetic and real-data suites share the numbers.

enum WorldTimeAcceptanceClock {
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
