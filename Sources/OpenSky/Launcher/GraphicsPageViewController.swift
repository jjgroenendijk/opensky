// The launcher's Graphics page: a preset, the base game's options read from the
// install's INI files, then OpenSky's own groups. Every value lives in the player
// settings file the game reads when it starts.

import AppKit
import Metal
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld

final class GraphicsPageViewController: NSViewController {
    private(set) var store: PlayerSettingsStore
    private(set) var presets: GraphicsPresetFiles
    private let reloadStore: @MainActor () -> PlayerSettingsStore
    private let reloadPresets: @MainActor () -> GraphicsPresetFiles
    let layout = LauncherPageLayout(pageName: "Graphics")
    let presetControl = NSPopUpButton()
    lazy var presetLabel = layout.line("GraphicsPresetStatsLabel")
    var optionRows: [GraphicsOptionRow] = []
    let renderScaleControl = NSPopUpButton()
    let upscalerControl = NSPopUpButton()
    let frameInterpolationControl = NSButton(
        checkboxWithTitle: "Frame interpolation",
        target: nil,
        action: nil
    )
    let rayTracedShadowsControl = NSButton(
        checkboxWithTitle: "Ray-traced sun shadows",
        target: nil,
        action: nil
    )
    lazy var rayTracingLabel = layout.line("GraphicsRayTracingLabel")
    let meshShaderGrassControl = NSButton(
        checkboxWithTitle: "Draw grass with mesh shaders", target: nil, action: nil
    )
    let gpuCullingControl = NSButton(checkboxWithTitle: "Cull on the GPU", target: nil, action: nil)
    let waterDepthControl = NSButton(
        checkboxWithTitle: "See into shallow water",
        target: nil,
        action: nil
    )
    let terrainNormalMapsControl = NSButton(
        checkboxWithTitle: "Terrain normal maps", target: nil, action: nil
    )
    let impactEffectsControl = NSButton(
        checkboxWithTitle: "Impact effects", target: nil, action: nil
    )
    let lightAnimationControl = NSButton(
        checkboxWithTitle: "Flickering lights", target: nil, action: nil
    )
    let particleSortingControl = NSButton(
        checkboxWithTitle: "Sort particles far to near", target: nil, action: nil
    )
    let toneMappingControl = NSButton(
        checkboxWithTitle: "HDR tone mapping", target: nil, action: nil
    )
    let pipelineCacheControl = NSButton(
        checkboxWithTitle: "Keep compiled GPU pipelines", target: nil, action: nil
    )
    let clearPipelineCacheControl = LauncherButton(
        title: "Clear Saved Pipelines",
        target: nil,
        action: nil
    )
    let textureStreamingControl = NSButton(
        checkboxWithTitle: "Full detail only near the camera", target: nil, action: nil
    )
    let textureBudgetControl = NSPopUpButton()
    lazy var textureBudgetLabel = layout.line("GraphicsTextureBudgetStatsLabel")
    let fullScreenControl = NSButton(checkboxWithTitle: "Full screen", target: nil, action: nil)
    let frameRateCapControl = NSPopUpButton()
    lazy var statusLabel = layout.line("GraphicsStatsLabel", mono: true)
    let rayTracing: RayTracingAvailability
    let interpolationUnsupportedReason: String?
    let meshShaderUnsupportedReason: String?

    /// `reloadStore` reads the file again each time the page shows, because the game
    /// window may have changed it.
    init(
        reloadStore: @escaping @MainActor () -> PlayerSettingsStore,
        reloadPresets: @escaping @MainActor () -> GraphicsPresetFiles = GraphicsPageViewController
            .installPresets,
        rayTracing: RayTracingAvailability = .of(MTLCreateSystemDefaultDevice()),
        interpolationUnsupportedReason: String? = FrameInterpolationSupport
            .unsupportedReason(MTLCreateSystemDefaultDevice()),
        meshShaderUnsupportedReason: String? = MeshShaderSupport
            .unsupportedReason(MTLCreateSystemDefaultDevice())
    ) {
        self.reloadStore = reloadStore
        self.reloadPresets = reloadPresets
        self.rayTracing = rayTracing
        self.interpolationUnsupportedReason = interpolationUnsupportedReason
        self.meshShaderUnsupportedReason = meshShaderUnsupportedReason
        store = reloadStore()
        presets = reloadPresets()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// The settings file, with the install's INI values as the defaults of its options.
    static func installSettings() -> PlayerSettingsStore {
        let root = try? GameDataLocator.locate()
        let catalog = root.map {
            PlayerSettingsCatalog.vanilla.applyingINIDefaults(INISettings.load(
                candidates: TerrainLODSettings.iniCandidates(installURL: $0.installURL)
            ))
        } ?? .vanilla
        return PlayerSettingsStore(
            catalog: catalog,
            persistence: try? PlayerSettingsFile.defaultFile()
        )
    }

    static func installPresets() -> GraphicsPresetFiles {
        (try? GameDataLocator.locate()).map { GraphicsPresetFiles.load(installURL: $0.installURL) }
            ?? GraphicsPresetFiles(files: [:])
    }

    override func loadView() {
        configureControls()
        optionRows = GraphicsOptions.all.map { option in
            GraphicsOptionRow(option: option, layout: layout, page: self)
        }
        let baseGroups = GraphicsGroup.allCases.map { group in
            layout.group(group.title, optionRows.filter { $0.option.group == group }.map(\.view))
        }
        view = layout.makeView(title: "Graphics", groups: [
            layout.group("Preset", [layout.row("Preset", presetControl), presetLabel])
        ] + baseGroups + [
            layout.group("Upscaling", [
                layout.row("Render scale", renderScaleControl),
                layout.row("Upscaler", upscalerControl), layout.toggle(frameInterpolationControl)
            ]),
            layout.group("Rendering", [
                layout.toggle(rayTracedShadowsControl), rayTracingLabel,
                layout.toggle(meshShaderGrassControl), layout.toggle(gpuCullingControl),
                layout.toggle(waterDepthControl), layout.toggle(terrainNormalMapsControl),
                layout.toggle(impactEffectsControl), layout.toggle(toneMappingControl),
                layout.toggle(lightAnimationControl), layout.toggle(particleSortingControl),
                layout.toggle(pipelineCacheControl),
                layout.buttons([clearPipelineCacheControl])
            ]),
            layout.group("Texture memory", [
                layout.toggle(textureStreamingControl),
                layout.note("Far textures keep only small levels; costs a little pop-in up close"),
                layout.row("Memory for close-up detail", textureBudgetControl),
                textureBudgetLabel
            ]),
            layout.group("Window", [
                layout.toggle(fullScreenControl), layout.row("Frame rate cap", frameRateCapControl)
            ]),
            statusLabel
        ])
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        store = reloadStore()
        presets = reloadPresets()
        refresh()
    }

    func refresh() {
        refreshPreset()
        for row in optionRows {
            row.refresh(store: store)
        }
        rayTracedShadowsControl.isEnabled = rayTracing.isAvailable
        rayTracedShadowsControl.state = rayTracing.isAvailable && store
            .bool(.rayTracedShadows) ? .on : .off
        rayTracingLabel.stringValue = rayTracing.reason.map { "Unavailable: \($0)" } ?? ""
        rayTracingLabel.isHidden = rayTracing.reason == nil
        renderScaleControl.selectItem(at: RenderScale(store: store).settingIndex)
        upscalerControl.selectItem(at: UpscalerKind(store: store).rawValue)
        meshShaderGrassControl.isEnabled = meshShaderUnsupportedReason == nil
        meshShaderGrassControl.state = meshShaderUnsupportedReason == nil && store
            .bool(.meshShaderGrass) ? .on : .off
        frameInterpolationControl.isEnabled = interpolationUnsupportedReason == nil
        frameInterpolationControl.state = interpolationUnsupportedReason == nil
            && store.bool(.frameInterpolation) ? .on : .off
        gpuCullingControl.state = store.bool(.gpuCulling) ? .on : .off
        waterDepthControl.state = store.bool(.waterDepth) ? .on : .off
        terrainNormalMapsControl.state = store.bool(.terrainNormalMaps) ? .on : .off
        impactEffectsControl.state = store.bool(.impactEffects) ? .on : .off
        toneMappingControl.state = store.bool(.toneMapping) ? .on : .off
        lightAnimationControl.state = store.bool(.lightAnimation) ? .on : .off
        particleSortingControl.state = store.bool(.particleSorting) ? .on : .off
        pipelineCacheControl.state = store.bool(.pipelineCacheEnabled) ? .on : .off
        textureStreamingControl.state = store.bool(.textureStreaming) ? .on : .off
        textureBudgetControl.selectItem(at: Int(store.value(.textureBudget)))
        textureBudgetLabel.stringValue = Self.budgetLine(store: store)
        fullScreenControl.state = store.bool(.fullScreen) ? .on : .off
        frameRateCapControl.selectItem(at: Int(store.value(.frameRateCap)))
    }

    private func refreshPreset() {
        let available = !presets.files.isEmpty
        presetControl.isEnabled = available
        let current = presets.current(in: store)
        presetControl.selectItem(at: current?.rawValue ?? GraphicsPreset.allCases.count)
        let source = current?.fileName ?? "preset files"
        presetLabel.stringValue = available
            ? "Values from the game's \(source); a change makes it Custom"
            : "Unavailable: Low.ini to Ultra.ini are not in the game folder"
    }

    /// `Automatic: 1.2 GB on this Mac` or the fixed choice.
    static func budgetLine(store: PlayerSettingsStore) -> String {
        let bytes = Renderer.textureBudgetBytes(store: store)
        let text = bytes.formatted(.byteCount(style: .memory))
        let isAutomatic = store.value(.textureBudget) == 0
        return isAutomatic ? "Automatic: \(text) on this Mac" : "Fixed: \(text)"
    }

    func set(_ id: PlayerSettingID, to value: Double) {
        store.set(id, to: value)
        refresh()
    }

    @objc func presetChanged() {
        guard let preset = GraphicsPreset(rawValue: presetControl.indexOfSelectedItem) else {
            refresh()
            return
        }
        presets.apply(preset, to: store)
        refresh()
    }
}
