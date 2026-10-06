// World > Asset Cache: the session toggle, the read counts, and one entry.

import AppKit
import Foundation
@testable import OpenSky
import OpenSkyAssetCache
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld
import Testing

@MainActor
struct AssetCacheSectionTests {
    private final class FakeProvider: AssetCacheControlProviding {
        var assetCache: AssetCacheReader?
        var fastTextureLoad: FastTextureLoadControl?
    }

    private struct NoFiles: GameFileSource {
        func exists(_: String) -> Bool {
            false
        }

        func contents(forPath path: String) throws -> Data {
            throw VFSError
                .fileNotFound(path: path)
        }

        func archiveEntries() -> [VFSEntry] {
            []
        }

        func fileNames(inDirectory _: String) -> [String] {
            []
        }
    }

    private func reader() throws -> AssetCacheReader {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "AssetCacheSectionTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        return try AssetCacheReader(
            store: AssetCacheStore(root: root, limitBytes: 1 << 30), files: NoFiles(),
            preset: .balanced
        )
    }

    private func find(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        return view.subviews.lazy.compactMap { find(identifier, in: $0) }.first
    }

    @Test func theSectionIsUnderTheWorldDestination() {
        let panel = WorldPanelViewController()
        panel.assetCacheProvider = FakeWorldProviders()
        panel.loadViewIfNeeded()
        #expect(panel.sections.map(\.sectionIdentifier).contains("assetCache"))
        #expect(panel.assetCacheSection.statsReadout == "Cache: off for this session")
    }

    @Test func idsArePinned() {
        let section = AssetCacheSection()
        section.loadViewIfNeeded()
        for identifier in [
            "AssetCacheReadControl", "AssetCacheStatsLabel", "AssetCachePathControl",
            "AssetCacheInspectControl", "AssetCacheEntryStatsLabel",
            "AssetCacheFastLoadControl", "AssetCacheFastLoadStatsLabel"
        ] {
            #expect(find(identifier, in: section.view) != nil, "\(identifier)")
        }
    }

    @Test func theToggleTurnsCacheReadsOff() throws {
        let provider = FakeProvider()
        provider.assetCache = try reader()
        let section = AssetCacheSection()
        section.loadViewIfNeeded()
        section.provider = provider
        #expect(section.statsReadout == "Preset: Balanced\nReads: none")
        let toggle = try #require(find("AssetCacheReadControl", in: section.view) as? NSButton)
        #expect(toggle.state == .on)
        toggle.performClick(nil)
        #expect(provider.assetCache?.isEnabled == false)
    }

    @Test func theFastLoadToggleFlipsTheSessionControl() throws {
        let provider = FakeProvider()
        provider.assetCache = try reader()
        provider.fastTextureLoad = FastTextureLoadControl(isEnabled: true)
        let section = AssetCacheSection()
        section.loadViewIfNeeded()
        section.provider = provider
        #expect(section.fastLoadReadout == "Fast load: no cell loaded yet")
        let toggle = try #require(find("AssetCacheFastLoadControl", in: section.view) as? NSButton)
        #expect(toggle.state == .on)
        toggle.performClick(nil)
        #expect(provider.fastTextureLoad?.isEnabled == false)
    }

    @Test func inspectingAPathNoFileHasSaysSo() throws {
        let provider = FakeProvider()
        provider.assetCache = try reader()
        let section = AssetCacheSection()
        section.loadViewIfNeeded()
        section.provider = provider
        let field = try #require(find("AssetCachePathControl", in: section.view) as? NSTextField)
        field.stringValue = "meshes\\a.nif"
        try #require(find("AssetCacheInspectControl", in: section.view) as? NSButton)
            .performClick(nil)
        #expect(section.entryReadout == "Entry: no file has this path")
    }
}
