// The bridge port runs a perk fragment through the runner it holds.

import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct PerkFragmentPortTests {
    @Test func theBridgePortHandsAPerkFragmentToItsRunner() throws {
        let runner = FakePerkFragmentRunner()
        let bridge = FakePapyrusWorldStateBridgePort()
        bridge.perkFragmentsValue = runner
        let perk = try Perk(
            record: PerkFixture.record(fields: PerkFixture.fields(editorID: "FeedPerk")),
            localized: false
        )
        let port: any PapyrusWorldStateBridgePort = bridge
        let activation = PerkFragmentActivation(actor: .player, target: .playerReference)
        #expect(port.runPerkFragment(of: perk, key: .player, index: 15, activation: activation))
        #expect(runner.runs == [15])
    }
}

private final class FakePerkFragmentRunner: PapyrusPerkFragmentRunning {
    var runs: [UInt16] = []

    func runPerkFragment(
        of perk: Perk,
        key: ReferenceKey,
        index: UInt16,
        activation: PerkFragmentActivation
    ) -> Bool {
        runs.append(index)
        return true
    }
}
