// World > Scripts: the native timing checkbox, its readout line, and reset.

import AppKit
@testable import OpenSky
import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

struct ScriptsPanelTimingTests {
    /// Run-to-end timing is a deviation from the game, so it marks the destination
    /// overridden, and reset puts game timing back.
    @Test @MainActor
    func gameTimingCheckboxSwitchesNativeTiming() {
        let panel = ScriptsPanelViewController()
        panel.loadViewIfNeeded()
        let fake = FakeScriptProvider()
        var snapshot = makeScriptsSnapshot()
        snapshot.lastStepDelayedCalls = 7
        fake.scriptsSnapshot = snapshot
        panel.provider = fake
        #expect(panel.scriptGameTimingControl.state == .on)
        #expect(!panel.isOverridden)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        #expect(panel.schedulerSection.readout.contains("Native timing: game"))
        #expect(panel.schedulerSection.readout.contains("Delayed calls last step: 7"))

        panel.scriptGameTimingControl.state = .off
        sendScriptsControl(panel.scriptGameTimingControl)
        #expect(fake.gameTimingCalls == [false])
        #expect(panel.isOverridden)

        panel.schedulerSection.performResetToDefaults()
        #expect(fake.gameTimingCalls == [false, true])
        #expect(panel.scriptGameTimingControl.state == .on)
        #expect(!panel.isOverridden)
    }
}
