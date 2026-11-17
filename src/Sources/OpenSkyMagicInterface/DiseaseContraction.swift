// Whether a hit passes on the attacker's disease. See docs/engine/diseases.md#contracting-it.

import OpenSkyFormatsESM

nonisolated public enum DiseaseContraction {
    /// The `Resist Disease` actor value, which the roll reads.
    public static let resistIndex = ActorValueIdentity.index(named: "Resist Disease")

    /// `resist` is the target's disease resistance, nil without an actor target. `roll` is a
    /// whole percent from 0 to 99. The chance is 100 minus the resistance cut to a whole
    /// number and capped at 100, and the disease passes when the chance is above the roll.
    public static func contracts(resist: Float?, roll: Int) -> Bool {
        let whole = resist.map { Int(min(max($0, -1000), 1000).rounded(.towardZero)) } ?? 100
        return 100 - min(whole, 100) > roll
    }
}
