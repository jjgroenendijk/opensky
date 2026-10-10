// World > Asset Optimisation section: turn optimised reads on and off for the
// running session, the hits and misses per kind, and the entries of one asset path.

import AppKit
import OpenSkyAssetCache
import OpenSkyRendering
import OpenSkyWorld

final class AssetCacheSection: PanelSectionViewController {
    weak var provider: (any AssetCacheControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let enabledControl = NSButton(
        checkboxWithTitle: "Read the optimised files",
        target: nil,
        action: nil
    )
    private let kindControls = AssetCacheKind.built.map { kind in
        NSButton(checkboxWithTitle: kind.title, target: nil, action: nil)
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "AssetCacheStatsLabel")
    private let fastLoadControl = NSButton(
        checkboxWithTitle: "Direct GPU loading of textures",
        target: nil,
        action: nil
    )
    private let fastMeshLoadControl = NSButton(
        checkboxWithTitle: "Direct GPU loading of meshes",
        target: nil,
        action: nil
    )
    private let fastLoadLabel = PanelComponents.statsLabel(
        identifier: "AssetCacheFastLoadStatsLabel"
    )
    private let pathControl = NSTextField()
    private let inspectControl = NSButton(title: "Inspect", target: nil, action: nil)
    private let entryLabel = PanelComponents.statsLabel(identifier: "AssetCacheEntryStatsLabel")
    private var inspectedPath: String?

    override var sectionTitle: String {
        "Asset Optimisation"
    }

    override var sectionIdentifier: String {
        "assetCache"
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    var fastLoadReadout: String {
        fastLoadLabel.stringValue
    }

    var entryReadout: String {
        entryLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(toggleEnabled),
            identifier: "AssetCacheReadControl"
        )
        enabledControl.toolTip = "Off loads every new asset from the game archives, for comparison"
        statsLabel.toolTip = "Optimised file hits and misses per asset kind since the game started"
        for (kind, control) in zip(AssetCacheKind.built, kindControls) {
            PanelComponents.configureCheckbox(
                control, target: self, action: #selector(toggleKind(_:)),
                identifier: "AssetCacheReadKind\(kind.title)Control"
            )
            control.tag = Int(kind.rawValue)
            control.toolTip = AssetCacheReadout.kindGain(kind)
                + ". Off loads new \(kind.folderName) from the game archives"
        }
        PanelComponents.configureCheckbox(
            fastLoadControl, target: self, action: #selector(toggleFastLoad),
            identifier: "AssetCacheFastLoadControl"
        )
        fastLoadControl.toolTip = "Read optimised textures straight into GPU memory on a cell load"
        PanelComponents.configureCheckbox(
            fastMeshLoadControl, target: self, action: #selector(toggleFastMeshLoad),
            identifier: "AssetCacheFastMeshLoadControl"
        )
        fastMeshLoadControl.toolTip = "Read optimised meshes straight into GPU buffers"
        fastLoadLabel.toolTip = "Assets read by direct GPU loading, and the last cell's load time"
        PanelComponents.configureTextField(
            pathControl, identifier: "AssetCachePathControl", width: 200,
            placeholder: "meshes\\clutter\\bucket01.nif"
        )
        pathControl.toolTip = "A game file path, as in the Asset Browser"
        PanelComponents.configureButton(
            inspectControl, target: self, action: #selector(inspect),
            identifier: "AssetCacheInspectControl"
        )
        inspectControl.toolTip = "Show the optimised files of this path"
        let inspectRow = NSStackView(views: [pathControl, inspectControl])
        inspectRow.spacing = PanelMetrics.rowGap
        return [
            PanelComponents.group([enabledControl] + kindControls + [statsLabel]),
            PanelComponents.group([fastLoadControl, fastMeshLoadControl, fastLoadLabel]),
            PanelComponents.group([inspectRow, entryLabel])
        ]
    }

    override func refreshReadout() {
        refreshFastLoad()
        guard let cache = provider?.assetCache else {
            enabledControl.isEnabled = false
            inspectControl.isEnabled = false
            kindControls.forEach { $0.isEnabled = false }
            statsLabel.stringValue = "Optimised files: off for this session"
            entryLabel.stringValue = ""
            return
        }
        enabledControl.isEnabled = true
        inspectControl.isEnabled = true
        enabledControl.state = cache.isEnabled ? .on : .off
        let kinds = cache.kinds
        for (kind, control) in zip(AssetCacheKind.built, kindControls) {
            control.isEnabled = cache.isEnabled
            control.state = kinds.contains(kind) ? .on : .off
        }
        let lines = AssetCacheReadout.countLines(cache.allCounts)
        statsLabel
            .stringValue =
            (["Texture quality: \(cache.textureOutput.quality.title)"] +
                (lines.isEmpty ? ["Reads: none"] : lines))
            .joined(separator: "\n")
        entryLabel.stringValue = inspectedPath.map {
            AssetCacheReadout.inspectionLines(cache.inspect(path: $0)).joined(separator: "\n")
        } ?? ""
    }

    private func refreshFastLoad() {
        guard let control = provider?.fastTextureLoad else {
            for control in [fastLoadControl, fastMeshLoadControl] {
                control.isEnabled = false
                control.state = .off
            }
            fastLoadLabel.stringValue = "Direct GPU loading: off for this session"
            return
        }
        fastLoadControl.isEnabled = true
        fastLoadControl.state = control.isEnabled ? .on : .off
        fastMeshLoadControl.isEnabled = true
        fastMeshLoadControl.state = control.loadsMeshes ? .on : .off
        fastLoadLabel.stringValue = AssetCacheReadout.directLoadLines(control.snapshot)
            .joined(separator: "\n")
    }

    @objc private func toggleFastLoad() {
        provider?.fastTextureLoad?.isEnabled = fastLoadControl.state == .on
        refreshReadout()
    }

    @objc private func toggleFastMeshLoad() {
        provider?.fastTextureLoad?.loadsMeshes = fastMeshLoadControl.state == .on
        refreshReadout()
    }

    @objc private func toggleEnabled() {
        provider?.assetCache?.isEnabled = enabledControl.state == .on
        refreshReadout()
    }

    @objc private func toggleKind(_ sender: NSButton) {
        guard
            let cache = provider?.assetCache,
            let kind = AssetCacheKind(rawValue: UInt8(clamping: sender.tag))
        else { return }
        if sender.state == .on {
            cache.kinds.insert(kind)
        } else {
            cache.kinds.remove(kind)
        }
        refreshReadout()
    }

    @objc private func inspect() {
        let path = pathControl.stringValue.trimmingCharacters(in: .whitespaces)
        inspectedPath = path.isEmpty ? nil : path
        refreshReadout()
    }
}
