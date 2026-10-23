// Papyrus `Game.SetPlayerReportCrime` over the fixture's hold faction.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
@testable import OpenSkyFeaturesTesting
import Testing

@MainActor
struct CrimeReportSwitchTests {
    /// Papyrus `SetPlayerReportCrime(false)` stops every report of the player's crimes.
    @Test
    func switchedOffReportsChargeThePlayerNothing() throws {
        var runtime = try CrimeFixture.runtime()
        runtime.reportsPlayerCrimes = false
        let outcome = runtime.report(CrimeFixture.event(.murder))
        #expect(outcome.gold == 0)
        #expect(outcome.refusal == .playerCrimesNotReported)
        runtime.reportsPlayerCrimes = true
        let reported = runtime.report(CrimeFixture.event(.murder))
        #expect(reported.gold == 1000)
    }
}
