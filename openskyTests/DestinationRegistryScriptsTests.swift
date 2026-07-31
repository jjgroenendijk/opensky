// Satellite of DestinationRegistryTests (issue #278): the World > Scripts
// destination's slice of the registry contract. Split out because the parent
// file sits at the length limit, and because the conformance below has to live
// outside `FakeWorldProviders`'s own declaration for that file to stay there.

import AppKit
@testable import opensky
import Testing

/// Forwards the Papyrus seam to the panel tests' recorder rather than
/// duplicating it, so a registry-level reset and a panel-level checkbox click
/// are observed through the same fake. The conformance itself comes from
/// `WorldControlProviders`, which the class already declares; restating it here
/// would be redundant.
extension FakeWorldProviders {
    var scriptsSnapshot: ScriptsSnapshot {
        scripts.scriptsSnapshot
    }

    func setScriptsPaused(_ paused: Bool) {
        scripts.setScriptsPaused(paused)
    }

    func stepScripts(ticks: Int) {
        scripts.stepScripts(ticks: ticks)
    }
}

struct DestinationRegistryScriptsTests {
    /// A paused VM is what "overridden" means for this destination — running is
    /// the documented default — and the sidebar's reset resumes it. A fresh
    /// session is not paused, which the parent suite's all-destinations sweep
    /// also relies on.
    @Test @MainActor
    func scriptsOverrideTracksThePausedVMAndResetResumesIt() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(DestinationRegistry.destination(id: "scripts")?.overrides)
        #expect(!overrides.isOverridden(context))

        providers.setScriptsPaused(true)
        #expect(overrides.isOverridden(context))

        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        #expect(providers.scripts.setPausedCalls == [true, false])
    }

    /// Stepping is a momentary action, not a setting: it must never light the
    /// sidebar dot, and the destination reset must not undo it.
    @Test @MainActor
    func steppingIsNotAnOverride() throws {
        let providers = FakeWorldProviders()
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(DestinationRegistry.destination(id: "scripts")?.overrides)

        providers.stepScripts(ticks: 1)
        providers.stepScripts(ticks: ScriptSchedulerSection.burstTicks)
        #expect(!overrides.isOverridden(context))
        #expect(providers.scripts.stepCalls == [1, ScriptSchedulerSection.burstTicks])
    }

    /// The destination is placed under World, between Runtime State and the
    /// Developer group, and carries its own SF Symbol.
    @Test
    func descriptorPlacementIsPinned() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "scripts"))
        #expect(descriptor.title == "Scripts")
        #expect(descriptor.section == .world)
        #expect(descriptor.symbolName == "curlybraces")
        #expect(descriptor.showsGameView)
        #expect(descriptor.isWorldInspector)
    }
}
