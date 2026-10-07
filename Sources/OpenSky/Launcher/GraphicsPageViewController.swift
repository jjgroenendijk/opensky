// The launcher's Graphics page: the GPU feature switches, saved in the player settings
// file the game reads when it starts. `Developer > Rendering Performance` writes the same
// settings while the game runs.

import AppKit
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
    let textureStreamingControl = NSButton(
        checkboxWithTitle: "Stream textures", target: nil, action: nil
    )
    let textureBudgetControl = NSPopUpButton()
    let statusLabel = NSTextField(labelWithString: "")

    /// `reloadStore` reads the file again each time the page shows, because the game
    /// window may have changed it.
    init(reloadStore: @escaping @MainActor () -> PlayerSettingsStore) {
        self.reloadStore = reloadStore
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
            PanelComponents.group([
                PanelComponents.caption("Textures"), textureStreamingControl, textureBudgetControl
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
        textureStreamingControl.state = store.bool(.textureStreaming) ? .on : .off
        textureBudgetControl.selectItem(at: Int(store.value(.textureBudget)))
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
        configureTextureControls()
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

    @objc private func clearPipelineCache() {
        let folder = PipelineCache.archiveFolder(store: store)
        let cleared = folder.flatMap { try? PipelineCacheFolder.clear(folder: $0) } ?? 0
        statusLabel.stringValue = "Cleared: \(cleared) files"
    }
}
