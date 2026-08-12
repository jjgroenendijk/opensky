// World > Audio destination panel (M9.1.3): the sidebar verification surface
// for the world audio engine. Thin composition of self-contained sections
// (output/graph, sources, sfx, music, footsteps) on the shared panel framework,
// same shape as EnvironmentPanelViewController. Exact sidebar path and control
// ids: docs/engine/audio.md.
//
// The Voice section moved to `World > Dialogue & Voice` with issue #209: a
// voice line is one step of a conversation, and the destination that owns the
// conversation is where a user looks for it. Everything routed through the
// voice submix still reports here, in the Sources section.

import AppKit

final class AudioPanelViewController: InspectorPanelViewController {
    let outputSection = AudioOutputSection()
    let sourcesSection = AudioSourcesSection()
    let sfxSection = AudioSfxSection()
    let musicSection = AudioMusicSection()
    let footstepsSection = AudioFootstepsSection()

    /// Live audio bridge. Weak: the game controller owns this panel's parent
    /// and the engine, so the panel must not retain back.
    weak var provider: (any AudioControlProviding)? {
        didSet {
            outputSection.provider = provider
            sourcesSection.provider = provider
            sfxSection.provider = provider
            musicSection.provider = provider
            footstepsSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [outputSection, sourcesSection, sfxSection, musicSection, footstepsSection]
    }

    /// Control forwards for the verification-surface tests, mirroring
    /// EnvironmentPanelViewController's convention.
    var audioEnabledControl: NSButton {
        outputSection.enabledControl
    }

    var audioMasterVolumeControl: NSSlider {
        outputSection.masterControl
    }

    var audioFileControl: NSPopUpButton {
        sourcesSection.fileControl
    }

    var audioPlaySelectedControl: NSButton {
        sourcesSection.playControl
    }

    var audioStopAllControl: NSButton {
        sourcesSection.stopAllControl
    }

    var audioMusicEnabledControl: NSButton {
        musicSection.musicEnabledControl
    }

    var audioMusicTypeControl: NSPopUpButton {
        musicSection.musicTypeControl
    }

    var audioStopMusicControl: NSButton {
        musicSection.stopMusicControl
    }

    var audioFootstepsEnabledControl: NSButton {
        footstepsSection.footstepsEnabledControl
    }

    var audioFootstepTagControl: NSPopUpButton {
        footstepsSection.footstepTagControl
    }

    var audioFootstepMaterialControl: NSPopUpButton {
        footstepsSection.footstepMaterialControl
    }

    var audioPlayFootstepControl: NSButton {
        footstepsSection.playFootstepControl
    }
}
