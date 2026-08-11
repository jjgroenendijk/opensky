// World > Audio destination panel (M9.1.3): the sidebar verification surface
// for the world audio engine. Thin composition of two self-contained sections
// (output/graph, sources) on the shared panel framework, same shape as
// EnvironmentPanelViewController. Exact sidebar path and control ids:
// docs/engine/audio.md.

import AppKit

final class AudioPanelViewController: InspectorPanelViewController {
    let outputSection = AudioOutputSection()
    let sourcesSection = AudioSourcesSection()
    let voiceSection = AudioVoiceSection()
    let sfxSection = AudioSfxSection()
    let musicSection = AudioMusicSection()
    let footstepsSection = AudioFootstepsSection()

    /// Live audio bridge. Weak: the game controller owns this panel's parent
    /// and the engine, so the panel must not retain back.
    weak var provider: (any AudioControlProviding)? {
        didSet {
            outputSection.provider = provider
            sourcesSection.provider = provider
            voiceSection.provider = provider
            sfxSection.provider = provider
            musicSection.provider = provider
            footstepsSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [outputSection, sourcesSection, voiceSection, sfxSection, musicSection, footstepsSection]
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

    var audioVoiceFilterControl: NSTextField {
        voiceSection.filterControl
    }

    var audioVoiceFileControl: NSPopUpButton {
        voiceSection.fileControl
    }

    var audioVoicePlayControl: NSButton {
        voiceSection.playControl
    }

    var lipSyncEnabledControl: NSButton {
        voiceSection.lipSyncEnabledControl
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
