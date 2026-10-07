// World > Asset Cache section: turn cache reads on and off for the running
// session, the hits and misses per kind, and the entries of one asset path.

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
        checkboxWithTitle: "Read from the cache",
        target: nil,
        action: nil
    )
    private let kindControls = AssetCacheKind.built.map { kind in
        NSButton(checkboxWithTitle: kind.title, target: nil, action: nil)
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "AssetCacheStatsLabel")
    private let fastLoadControl = NSButton(
        checkboxWithTitle: "Fast texture loading",
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
        "Asset Cache"
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
        statsLabel.toolTip = "Cache hits and misses per asset kind since the game started"
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
        fastLoadControl.toolTip = "Read cached textures straight into GPU memory during a cell load"
        fastLoadLabel.toolTip = "Textures read by fast loading, and the last cell's load time"
        PanelComponents.configureTextField(
            pathControl, identifier: "AssetCachePathControl", width: 200,
            placeholder: "meshes\\clutter\\bucket01.nif"
        )
        pathControl.toolTip = "A game file path, as in the Asset Browser"
        PanelComponents.configureButton(
            inspectControl, target: self, action: #selector(inspect),
            identifier: "AssetCacheInspectControl"
        )
        inspectControl.toolTip = "Show the cache entries of this path"
        let inspectRow = NSStackView(views: [pathControl, inspectControl])
        inspectRow.spacing = PanelMetrics.rowGap
        return [
            PanelComponents.group([enabledControl] + kindControls + [statsLabel]),
            PanelComponents.group([fastLoadControl, fastLoadLabel]),
            PanelComponents.group([inspectRow, entryLabel])
        ]
    }

    override func refreshReadout() {
        refreshFastLoad()
        guard let cache = provider?.assetCache else {
            enabledControl.isEnabled = false
            inspectControl.isEnabled = false
            kindControls.forEach { $0.isEnabled = false }
            statsLabel.stringValue = "Cache: off for this session"
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
            (["Preset: \(cache.preset.title)"] + (lines.isEmpty ? ["Reads: none"] : lines))
                .joined(separator: "\n")
        entryLabel.stringValue = inspectedPath.map {
            AssetCacheReadout.inspectionLines(cache.inspect(path: $0)).joined(separator: "\n")
        } ?? ""
    }

    private func refreshFastLoad() {
        guard let control = provider?.fastTextureLoad else {
            fastLoadControl.isEnabled = false
            fastLoadControl.state = .off
            fastLoadLabel.stringValue = "Fast load: off for this session"
            return
        }
        fastLoadControl.isEnabled = true
        fastLoadControl.state = control.isEnabled ? .on : .off
        fastLoadLabel.stringValue = AssetCacheReadout.fastLoadLines(control.snapshot)
            .joined(separator: "\n")
    }

    @objc private func toggleFastLoad() {
        provider?.fastTextureLoad?.isEnabled = fastLoadControl.state == .on
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
