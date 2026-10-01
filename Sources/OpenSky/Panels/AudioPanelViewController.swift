// World > Audio: the sidebar surface for the world audio engine, composed of
// self-contained sections. Sidebar path and control ids: docs/engine/audio.md.
// The Voice section lives under `World > Dialogue & Voice`, beside the
// conversation that plays it.

import AppKit
import OpenSkyWorld

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
