// Who raises an alarm: by default every witness, and with a crime-faction check only
// those that belong to one.

@testable import OpenSkyCrime
import OpenSkyFeaturesTesting
import Testing

@MainActor
struct CrimeAlarmWitnessTests {
    private static let witness = CrimeFixture.key(0x700)

    @Test func everyWitnessRaisesAnAlarmByDefault() {
        #expect(NoCrimeWitnesses().raisesAlarm(Self.witness))
        #expect(PerceptionCrimeWitnesses(perception: nil).raisesAlarm(Self.witness))
    }

    @Test func aWitnessWithoutACrimeFactionRaisesNone() {
        let witnesses = PerceptionCrimeWitnesses(perception: nil, hasCrimeFaction: { _ in false })
        #expect(!witnesses.raisesAlarm(Self.witness))
        #expect(witnesses.witnesses(of: Self.witness).isEmpty)
    }
}
