// World > Effects and World > Audio > Reverb with the provider fake: pinned ids,
// visible frames, each control driving the fake, and the overrides.

import AppKit
@testable import OpenSky
import Testing

@MainActor
struct EffectsPanelTests {
    private func tap(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    private func panel(_ provider: FakeWorldProviders) -> EffectsPanelViewController {
        let panel = EffectsPanelViewController()
        panel.loadViewIfNeeded()
        panel.imageSpaceProvider = provider
        panel.visualEffectProvider = provider
        panel.impactProvider = provider
        panel.explosionProvider = provider
        return panel
    }

    @Test func accessibilityIdentifiersArePinned() {
        let panel = panel(FakeWorldProviders())
        let image = panel.imageSpaceSection
        let visual = panel.visualEffectSection
        let blast = panel.explosionSection
        #expect(image.sectionIdentifier == "imageSpace")
        #expect(visual.sectionIdentifier == "visualEffects")
        #expect(blast.sectionIdentifier == "explosions")
        let controls: [(NSView, String)] = [
            (image.passControl, "ImageSpacePassControl"),
            (image.toneMappingControl, "ImageSpaceToneMappingControl"),
            (image.forcedControl, "ImageSpaceForcedControl"),
            (image.modifierControl, "ImageSpaceModifierControl"),
            (image.strengthControl, "ImageSpaceStrengthControl"),
            (image.playControl, "ImageSpacePlayControl"),
            (image.stopControl, "ImageSpaceStopControl"),
            (visual.nameControl, "VisualEffectNameControl"),
            (visual.attachPlayerControl, "VisualEffectAttachPlayerControl"),
            (visual.attachActorControl, "VisualEffectAttachActorControl"),
            (visual.clearControl, "VisualEffectClearControl"),
            (panel.impactSection.modelsControl, "ImpactModelsControl"),
            (panel.impactSection.decalsControl, "DecalsControl"),
            (panel.impactSection.repeatControl, "ImpactRepeatControl"),
            (panel.impactSection.clearControl, "DecalClearControl"),
            (blast.explosionControl, "ExplosionSelectControl"),
            (blast.detonateControl, "ExplosionDetonateControl"),
            (blast.debrisControl, "DebrisSelectControl"),
            (blast.throwControl, "DebrisThrowControl"),
            (blast.hazardControl, "HazardSelectControl"),
            (blast.spawnControl, "HazardSpawnControl"),
            (blast.clearControl, "ExplosionClearControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    @Test func controlsHaveVisibleFrames() throws {
        let panel = panel(FakeWorldProviders())
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 2000)
        panel.view.layoutSubtreeIfNeeded()
        let controls: [NSView] = [
            panel.imageSpaceSection.passControl, panel.imageSpaceSection.playControl,
            panel.visualEffectSection.nameControl, panel.explosionSection.detonateControl,
            panel.explosionSection.spawnControl
        ]
        for control in controls {
            let name = control.accessibilityIdentifier()
            #expect(!control.isHidden, "\(name) hidden")
            #expect(control.frame.height > 0, "\(name) frame=\(control.frame)")
            let documentFrame = control.convert(control.bounds, to: scrollView.documentView)
            #expect(scrollView.documentView?.bounds.intersects(documentFrame) == true)
        }
    }

    @Test func imageSpaceControlsForceToggleAndPlay() {
        let provider = FakeWorldProviders()
        let section = panel(provider).imageSpaceSection
        section.refreshReadout()
        #expect(section.forcedControl.itemTitles == [
            ImageSpaceSection.followWeatherTitle, "CaveImageSpace", "SunnyImageSpace"
        ])
        section.forcedControl.selectItem(at: 1)
        tap(section.forcedControl)
        #expect(provider.forcedImageSpaceName == "CaveImageSpace")
        #expect(ImageSpaceSection.isOverridden(provider: provider))
        section.passControl.state = .off
        tap(section.passControl)
        #expect(!provider.imageSpacePassEnabled)
        section.toneMappingControl.state = .off
        tap(section.toneMappingControl)
        #expect(!provider.toneMappingEnabled)
        section.strengthControl.floatValue = 0.5
        tap(section.playControl)
        #expect(provider.effectsState.modifierStarts.first?.0 == "FlashModifier")
        #expect(provider.effectsState.modifierStarts.first?.1 == 0.5)
        ImageSpaceSection.resetToDefaults(provider: provider)
        #expect(provider.imageSpacePassEnabled)
        #expect(provider.forcedImageSpaceName == nil)
        section.refreshReadout()
        #expect(section.readout.hasPrefix("Baseline:"))
        #expect(section.readout.contains("Tone mapping: off"))
    }

    @Test func visualEffectControlsAttachAndClear() {
        let provider = FakeWorldProviders()
        let section = panel(provider).visualEffectSection
        section.refreshReadout()
        section.nameControl.stringValue = "GlowEffect"
        tap(section.attachActorControl)
        #expect(provider.effectsState.attached.first?.1 == true)
        #expect(VisualEffectSection.isOverridden(provider: provider))
        #expect(section.readout.contains("Effects: 1 live"))
        tap(section.clearControl)
        #expect(provider.effectsState.cleared == 1)
        #expect(!VisualEffectSection.isOverridden(provider: provider))
    }

    @Test func impactControlsToggleRepeatAndClear() {
        let provider = FakeWorldProviders()
        let section = panel(provider).impactSection
        #expect(section.sectionIdentifier == "impacts")
        #expect(!ImpactSection.isOverridden(provider: provider))
        section.decalsControl.state = .off
        tap(section.decalsControl)
        #expect(!provider.decalsEnabled)
        #expect(ImpactSection.isOverridden(provider: provider))
        tap(section.repeatControl)
        tap(section.clearControl)
        #expect(provider.effectsState.impactRepeats == 1)
        #expect(provider.effectsState.decalsCleared == 1)
        section.refreshReadout()
        #expect(section.readout.contains("last FSTDirtWalkLImpact"))
        ImpactSection.resetToDefaults(provider: provider)
        #expect(provider.decalsEnabled)
    }

    @Test func explosionControlsDetonateThrowAndSpawn() {
        let provider = FakeWorldProviders()
        let section = panel(provider).explosionSection
        section.refreshReadout()
        tap(section.detonateControl)
        tap(section.throwControl)
        tap(section.spawnControl)
        #expect(provider.effectsState.detonated == ["FireballExplosion"])
        #expect(provider.effectsState.thrown == ["RockDebris"])
        #expect(provider.effectsState.spawned == ["FireHazard"])
        #expect(section.readout.contains("Detonations: 1"))
        #expect(section.readout.contains("FireHazard at 0 0 0, 5.0 s left, 0 ticks"))
    }

    @Test func theReverbOverrideHoldsAndResets() {
        let provider = FakeWorldProviders()
        let panel = AudioPanelViewController()
        panel.loadViewIfNeeded()
        panel.provider = provider
        let section = panel.reverbSection
        #expect(section.overrideControl.accessibilityIdentifier() == "AudioReverbOverrideControl")
        #expect(section.wetLevelControl.accessibilityIdentifier() == "AudioReverbWetLevelControl")
        section.wetLevelControl.floatValue = 12
        section.overrideControl.state = .on
        tap(section.overrideControl)
        #expect(provider.reverbWetOverride == 12)
        #expect(AudioReverbSection.isOverridden(provider: provider))
        AudioReverbSection.resetToDefaults(provider: provider)
        #expect(provider.reverbWetOverride == nil)
        section.refreshReadout()
        #expect(section.readout.contains("Record: none"))
    }
}
