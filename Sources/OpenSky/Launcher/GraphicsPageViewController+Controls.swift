// The Graphics page's controls: identifiers, tooltips, actions, and one row per
// base game option.

import AppKit
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld

extension GraphicsPageViewController {
    func configureControls() {
        presetControl.addItems(withTitles: GraphicsPreset.allCases.map(\.title) + ["Custom"])
        presetControl.item(at: GraphicsPreset.allCases.count)?.isEnabled = false
        presetControl.autoenablesItems = false
        PanelComponents.configurePopUp(
            presetControl, target: self, action: #selector(presetChanged),
            identifier: "GraphicsPresetControl"
        )
        presetControl.toolTip = "Set every option from the game's own preset file"
        configureCheckboxes()
        PanelComponents.configureButton(
            clearPipelineCacheControl, target: self, action: #selector(clearPipelineCache),
            identifier: "GraphicsPipelineCacheClearControl"
        )
        clearPipelineCacheControl.toolTip = "Delete saved pipelines; the next launch compiles them"
        configurePopUps()
        statusLabel.stringValue = "Applies when the game starts"
    }

    private func configureCheckboxes() {
        checkbox(
            frameInterpolationControl, "FrameInterpolation",
            interpolationUnsupportedReason ?? "Show a MetalFX frame between real frames"
        )
        checkbox(
            rayTracedShadowsControl,
            "RayTracedShadows",
            "Trace one ray to the sun per pixel; needs an M3 or later"
        )
        checkbox(
            meshShaderGrassControl, "MeshShaderGrass",
            meshShaderUnsupportedReason ?? "Cull grass on the GPU with mesh shaders"
        )
        checkbox(
            gpuCullingControl,
            "GPUCulling",
            "Cull the static scene in a compute pass, not on the CPU"
        )
        checkbox(
            roomCullingControl, "RoomCulling",
            "Inside, skip rooms the camera cannot see through a doorway"
        )
        checkbox(
            waterDepthControl,
            "WaterDepth",
            "Shallow water shows the ground below; costs one depth copy"
        )
        checkbox(
            terrainNormalMapsControl, "TerrainNormalMaps",
            "Light the ground with the land textures' normal maps"
        )
        checkbox(
            toneMappingControl, "ToneMapping",
            "The eye adapts to dark and bright scenes; follows the weather's image space"
        )
        configureCharacterCheckboxes()
        checkbox(
            impactEffectsControl, "ImpactEffects",
            "Dust under a step, sparks or blood spray where a hit lands"
        )
        checkbox(
            lightAnimationControl, "LightAnimation",
            "Torches and fires flicker; some lights pulse"
        )
        checkbox(
            particleSortingControl, "ParticleSorting",
            "Draw smoke and steam far to near, so near particles blend over far ones"
        )
        checkbox(
            pipelineCacheControl, "PipelineCache",
            "Load compiled GPU pipelines saved by an earlier launch; starts faster"
        )
        checkbox(
            textureStreamingControl, "TextureStreaming",
            "Large textures keep only the levels the camera needs; saves GPU memory"
        )
        checkbox(fullScreenControl, "FullScreen", "Play opens full screen")
    }

    private func configureCharacterCheckboxes() {
        checkbox(blinkingControl, "CharacterBlinking", "Actors blink on their own")
        checkbox(
            expressionsControl, "CharacterExpressions",
            "A speaker's face shows the emotion of the line it says"
        )
        checkbox(
            headTrackingControl, "CharacterHeadTracking",
            "Actors turn their heads toward what they look at"
        )
        checkbox(
            objectAnimationControl, "ObjectAnimation",
            "Traps, doors, and levers play their animations"
        )
    }

    /// `name` becomes the id `Graphics<name>Control`.
    private func checkbox(_ button: NSButton, _ name: String, _ toolTip: String) {
        PanelComponents.configureCheckbox(
            button, target: self, action: #selector(toggle(_:)),
            identifier: "Graphics\(name)Control"
        )
        button.toolTip = toolTip
    }

    private func configurePopUps() {
        let renderScales = PlayerSettingsCatalog.renderScaleOptions
        popUp(
            renderScaleControl,
            renderScales,
            "RenderScale",
            "Render the scene smaller and let MetalFX upscale it"
        )
        popUp(
            upscalerControl, PlayerSettingsCatalog.upscalerOptions, "Upscaler",
            "Temporal also smooths edges; spatial costs less GPU time"
        )
        popUp(
            textureBudgetControl, TextureBudget.choiceTitles, "TextureBudget",
            "GPU memory for close-up texture levels; Automatic follows this Mac"
        )
        let caps = PlayerSettingsCatalog.frameRateCapOptions
            .map(PlayerSettingsCatalog.frameRateCapTitle)
        popUp(frameRateCapControl, caps, "FrameRateCap", "The most frames a second Play draws")
    }

    /// `name` becomes the id `Graphics<name>Control`.
    private func popUp(
        _ button: NSPopUpButton,
        _ titles: [String],
        _ name: String,
        _ toolTip: String
    ) {
        button.addItems(withTitles: titles)
        PanelComponents.configurePopUp(
            button, target: self, action: #selector(choose(_:)),
            identifier: "Graphics\(name)Control"
        )
        button.toolTip = toolTip
    }

    private var checkboxSettings: [(NSButton, PlayerSettingID)] {
        [
            (frameInterpolationControl, .frameInterpolation), (
                rayTracedShadowsControl,
                .rayTracedShadows
            ),
            (meshShaderGrassControl, .meshShaderGrass), (gpuCullingControl, .gpuCulling),
            (roomCullingControl, .roomCulling),
            (waterDepthControl, .waterDepth), (terrainNormalMapsControl, .terrainNormalMaps),
            (impactEffectsControl, .impactEffects), (toneMappingControl, .toneMapping),
            (lightAnimationControl, .lightAnimation), (particleSortingControl, .particleSorting),
            (blinkingControl, .characterBlinking),
            (expressionsControl, .characterDialogueExpressions),
            (headTrackingControl, .characterHeadTracking),
            (objectAnimationControl, .objectAnimation),
            (pipelineCacheControl, .pipelineCacheEnabled),
            (textureStreamingControl, .textureStreaming), (fullScreenControl, .fullScreen)
        ]
    }

    private var popUpSettings: [(NSPopUpButton, PlayerSettingID)] {
        [
            (renderScaleControl, .renderScale), (upscalerControl, .upscaler),
            (textureBudgetControl, .textureBudget), (frameRateCapControl, .frameRateCap)
        ]
    }

    @objc private func toggle(_ sender: NSButton) {
        guard let id = checkboxSettings.first(where: { $0.0 === sender })?.1 else { return }
        set(id, to: sender.state == .on ? 1 : 0)
    }

    @objc private func choose(_ sender: NSPopUpButton) {
        guard let id = popUpSettings.first(where: { $0.0 === sender })?.1 else { return }
        set(id, to: Double(max(sender.indexOfSelectedItem, 0)))
    }

    @objc private func clearPipelineCache() {
        let folder = PipelineCache.archiveFolder(store: store)
        let cleared = folder.flatMap { try? PipelineCacheFolder.clear(folder: $0) } ?? 0
        statusLabel.stringValue = "Cleared: \(cleared) files"
    }
}

/// One base game option: a control, then its reason or its INI key.
@MainActor
final class GraphicsOptionRow: NSObject {
    let option: GraphicsOption
    let view: NSView
    private let toggle: NSButton?
    private let field: NSTextField?
    private weak var page: GraphicsPageViewController?

    init(option: GraphicsOption, layout: LauncherPageLayout, page: GraphicsPageViewController) {
        self.option = option
        self.page = page
        let identifier = "GraphicsOption\(option.key)Control"
        var views: [NSView] = []
        if option.isToggle {
            let button = NSButton(checkboxWithTitle: option.title, target: nil, action: nil)
            button.setAccessibilityIdentifier(identifier)
            toggle = button
            field = nil
            views.append(layout.toggle(button))
        } else {
            let input = NSTextField()
            PanelComponents.configureTextField(input, identifier: identifier, width: 100)
            toggle = nil
            field = input
            views.append(layout.row(option.title, input))
        }
        let note = layout
            .note(option.unavailableReason.map { "Unavailable: \($0)" } ?? option.iniName)
        note.setAccessibilityIdentifier("GraphicsOption\(option.key)StatsLabel")
        views.append(option.unavailableReason == nil ? layout.detail(note) : note)
        if option.unavailableReason != nil {
            views.append(layout.detail(layout.note(option.iniName)))
        }
        let stack = PanelComponents.group(views)
        stack.spacing = 2
        view = stack
        super.init()
        toggle?.target = self
        toggle?.action = #selector(changed)
        field?.target = self
        field?.action = #selector(changed)
        let enabled = option.unavailableReason == nil
        toggle?.isEnabled = enabled
        field?.isEnabled = enabled
        toggle?.toolTip = option.unavailableReason ?? option.iniName
        field?.toolTip = option.unavailableReason ?? option.iniName
    }

    func refresh(store: PlayerSettingsStore) {
        let value = store.value(option.id)
        toggle?.state = value >= 0.5 ? .on : .off
        field?.stringValue = value.formatted(.number.grouping(.never))
    }

    @objc private func changed() {
        if let toggle {
            page?.set(option.id, to: toggle.state == .on ? 1 : 0)
        } else if let field, let value = Double(field.stringValue), value.isFinite, value >= 0 {
            page?.set(option.id, to: value)
        } else {
            page?.refresh()
        }
    }
}
