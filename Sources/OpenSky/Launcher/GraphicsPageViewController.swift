// The launcher's Graphics page: the GPU feature switches, saved in the player settings
// file the game reads when it starts. `Developer > Rendering Performance` writes the same
// settings while the game runs.

import AppKit
import Metal
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld

final class GraphicsPageViewController: NSViewController {
    private(set) var store: PlayerSettingsStore
    private let reloadStore: @MainActor () -> PlayerSettingsStore
    let pipelineCacheControl = NSButton(
        checkboxWithTitle: "Cache GPU pipelines", target: nil, action: nil
    )
    let clearPipelineCacheControl = NSButton(
        title: "Clear Saved Pipelines", target: nil, action: nil
    )
    let gpuCullingControl = NSButton(checkboxWithTitle: "Cull on the GPU", target: nil, action: nil)
    let waterDepthControl = NSButton(
        checkboxWithTitle: "See into shallow water", target: nil, action: nil
    )
    let textureStreamingControl = NSButton(
        checkboxWithTitle: "Stream textures", target: nil, action: nil
    )
    let textureBudgetControl = NSPopUpButton()
    let rayTracedShadowsControl = NSButton(
        checkboxWithTitle: "Ray-traced sun shadows", target: nil, action: nil
    )
    let rayTracingLabel = NSTextField(labelWithString: "")
    let renderScaleControl = NSPopUpButton()
    let upscalerControl = NSPopUpButton()
    let frameInterpolationControl = NSButton(
        checkboxWithTitle: "Frame interpolation", target: nil, action: nil
    )
    let meshShaderGrassControl = NSButton(
        checkboxWithTitle: "Draw grass with mesh shaders", target: nil, action: nil
    )
    private let rayTracing: RayTracingAvailability
    private let interpolationUnsupportedReason: String?
    private let meshShaderUnsupportedReason: String?
    let statusLabel = NSTextField(labelWithString: "")

    /// `reloadStore` reads the file again each time the page shows, because the game
    /// window may have changed it.
    init(
        reloadStore: @escaping @MainActor () -> PlayerSettingsStore,
        rayTracing: RayTracingAvailability = .of(MTLCreateSystemDefaultDevice()),
        interpolationUnsupportedReason: String? = FrameInterpolationSupport
            .unsupportedReason(MTLCreateSystemDefaultDevice()),
        meshShaderUnsupportedReason: String? = MeshShaderSupport
            .unsupportedReason(MTLCreateSystemDefaultDevice())
    ) {
        self.reloadStore = reloadStore
        self.rayTracing = rayTracing
        self.interpolationUnsupportedReason = interpolationUnsupportedReason
        self.meshShaderUnsupportedReason = meshShaderUnsupportedReason
        store = reloadStore()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        configureControls()
        let title = NSTextField(labelWithAttributedString: Theme.headingAttributed(
            "Graphics", size: 24, color: Theme.gold
        ))
        let stack = NSStackView(views: [
            title,
            PanelComponents.group([
                PanelComponents.caption("Pipelines"), pipelineCacheControl,
                PanelComponents.buttonRow([clearPipelineCacheControl])
            ]),
            PanelComponents.group([PanelComponents.caption("Culling"), gpuCullingControl]),
            PanelComponents.group([PanelComponents.caption("Grass"), meshShaderGrassControl]),
            PanelComponents.group([PanelComponents.caption("Water"), waterDepthControl]),
            PanelComponents.group([
                PanelComponents.caption("Textures"), textureStreamingControl, textureBudgetControl
            ]),
            PanelComponents.group([
                PanelComponents.caption("Ray tracing"), rayTracedShadowsControl, rayTracingLabel
            ]),
            PanelComponents.group([
                PanelComponents.caption("Upscaling"), renderScaleControl, upscalerControl,
                frameInterpolationControl
            ]),
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        view = stack
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        store = reloadStore()
        refresh()
    }

    func refresh() {
        pipelineCacheControl.state = store.bool(.pipelineCacheEnabled) ? .on : .off
        gpuCullingControl.state = store.bool(.gpuCulling) ? .on : .off
        waterDepthControl.state = store.bool(.waterDepth) ? .on : .off
        textureStreamingControl.state = store.bool(.textureStreaming) ? .on : .off
        textureBudgetControl.selectItem(at: Int(store.value(.textureBudget)))
        rayTracedShadowsControl.isEnabled = rayTracing.isAvailable
        rayTracedShadowsControl.state = rayTracing.isAvailable && store.bool(.rayTracedShadows)
            ? .on : .off
        rayTracingLabel.stringValue = rayTracing.reason.map { "Unavailable: \($0)" } ?? ""
        renderScaleControl.selectItem(at: RenderScale(store: store).settingIndex)
        upscalerControl.selectItem(at: UpscalerKind(store: store).rawValue)
        meshShaderGrassControl.isEnabled = meshShaderUnsupportedReason == nil
        meshShaderGrassControl.state = meshShaderUnsupportedReason == nil
            && store.bool(.meshShaderGrass) ? .on : .off
        frameInterpolationControl.isEnabled = interpolationUnsupportedReason == nil
        frameInterpolationControl.state = interpolationUnsupportedReason == nil
            && store.bool(.frameInterpolation) ? .on : .off
    }

    private func configureControls() {
        PanelComponents.configureCheckbox(
            pipelineCacheControl, target: self, action: #selector(pipelineCacheChanged),
            identifier: "GraphicsPipelineCacheControl"
        )
        pipelineCacheControl.toolTip = "Load compiled GPU pipelines saved by an earlier launch"
        PanelComponents.configureButton(
            clearPipelineCacheControl, target: self, action: #selector(clearPipelineCache),
            identifier: "GraphicsPipelineCacheClearControl"
        )
        clearPipelineCacheControl.toolTip = "Delete the saved pipelines; the next launch compiles"
        PanelComponents.configureCheckbox(
            gpuCullingControl, target: self, action: #selector(gpuCullingChanged),
            identifier: "GraphicsGPUCullingControl"
        )
        gpuCullingControl.toolTip = "Cull the static scene in a compute pass, not on the CPU"
        PanelComponents.configureCheckbox(
            waterDepthControl, target: self, action: #selector(waterDepthChanged),
            identifier: "GraphicsWaterDepthControl"
        )
        waterDepthControl.toolTip = "Shallow water shows the ground below; costs one depth copy"
        configureTextureControls()
        configureUpscalingControls()
        configureGrassControls()
        statusLabel.font = PanelMetrics.monoFont
        statusLabel.textColor = Theme.parchmentDim
        statusLabel.setAccessibilityIdentifier("GraphicsStatsLabel")
        statusLabel.stringValue = "Applies when the game starts"
    }

    private func configureTextureControls() {
        PanelComponents.configureCheckbox(
            textureStreamingControl, target: self, action: #selector(textureStreamingChanged),
            identifier: "GraphicsTextureStreamingControl"
        )
        textureStreamingControl.toolTip = "Large textures keep only the mip levels the camera needs"
        textureBudgetControl.addItems(
            withTitles: PlayerSettingsCatalog.textureBudgetOptions.map { "Budget \($0) MiB" }
        )
        PanelComponents.configurePopUp(
            textureBudgetControl, target: self, action: #selector(textureBudgetChanged),
            identifier: "GraphicsTextureBudgetControl"
        )
        textureBudgetControl.toolTip = "Far textures drop detail when the levels pass this size"
        PanelComponents.configureCheckbox(
            rayTracedShadowsControl, target: self, action: #selector(rayTracedShadowsChanged),
            identifier: "GraphicsRayTracedShadowsControl"
        )
        rayTracedShadowsControl.toolTip = "Trace one ray to the sun per pixel; needs an M3 or later"
        rayTracingLabel.font = PanelMetrics.monoFont
        rayTracingLabel.textColor = Theme.parchmentDim
        rayTracingLabel.setAccessibilityIdentifier("GraphicsRayTracingLabel")
    }

    private func configureUpscalingControls() {
        renderScaleControl.addItems(
            withTitles: PlayerSettingsCatalog.renderScaleOptions.map { "Render scale \($0)" }
        )
        PanelComponents.configurePopUp(
            renderScaleControl, target: self, action: #selector(renderScaleChanged),
            identifier: "GraphicsRenderScaleControl"
        )
        renderScaleControl.toolTip = "Render the scene smaller and let MetalFX upscale it"
        upscalerControl.addItems(withTitles: PlayerSettingsCatalog.upscalerOptions)
        PanelComponents.configurePopUp(
            upscalerControl, target: self, action: #selector(upscalerChanged),
            identifier: "GraphicsUpscalerControl"
        )
        upscalerControl.toolTip = "Temporal also smooths edges; spatial costs less GPU time"
        PanelComponents.configureCheckbox(
            frameInterpolationControl, target: self, action: #selector(frameInterpolationChanged),
            identifier: "GraphicsFrameInterpolationControl"
        )
        frameInterpolationControl.toolTip = interpolationUnsupportedReason
            ?? "Show a MetalFX frame between real frames; needs the temporal upscaler"
    }

    private func configureGrassControls() {
        PanelComponents.configureCheckbox(
            meshShaderGrassControl, target: self, action: #selector(meshShaderGrassChanged),
            identifier: "GraphicsMeshShaderGrassControl"
        )
        meshShaderGrassControl.toolTip = meshShaderUnsupportedReason
            ?? "Cull grass meshlets on the GPU with object and mesh shaders"
    }

    @objc private func meshShaderGrassChanged() {
        store.set(.meshShaderGrass, to: meshShaderGrassControl.state == .on ? 1 : 0)
    }

    @objc private func frameInterpolationChanged() {
        store.set(.frameInterpolation, to: frameInterpolationControl.state == .on ? 1 : 0)
    }

    @objc private func renderScaleChanged() {
        store.set(.renderScale, to: Double(max(renderScaleControl.indexOfSelectedItem, 0)))
    }

    @objc private func upscalerChanged() {
        store.set(.upscaler, to: Double(max(upscalerControl.indexOfSelectedItem, 0)))
    }

    @objc private func rayTracedShadowsChanged() {
        store.set(.rayTracedShadows, to: rayTracedShadowsControl.state == .on ? 1 : 0)
    }

    @objc private func textureStreamingChanged() {
        store.set(.textureStreaming, to: textureStreamingControl.state == .on ? 1 : 0)
    }

    @objc private func textureBudgetChanged() {
        store.set(.textureBudget, to: Double(max(textureBudgetControl.indexOfSelectedItem, 0)))
    }

    @objc private func pipelineCacheChanged() {
        store.set(.pipelineCacheEnabled, to: pipelineCacheControl.state == .on ? 1 : 0)
    }

    @objc private func gpuCullingChanged() {
        store.set(.gpuCulling, to: gpuCullingControl.state == .on ? 1 : 0)
    }

    @objc private func waterDepthChanged() {
        store.set(.waterDepth, to: waterDepthControl.state == .on ? 1 : 0)
    }

    @objc private func clearPipelineCache() {
        let folder = PipelineCache.archiveFolder(store: store)
        let cleared = folder.flatMap { try? PipelineCacheFolder.clear(folder: $0) } ?? 0
        statusLabel.stringValue = "Cleared: \(cleared) files"
    }
}
