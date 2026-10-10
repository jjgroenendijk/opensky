// PIDN, MRKS, FOGM, SUMM, and THMB: the player's identity, the map markers, the
// local map fog, and the save list row come back as they were.

import Foundation
import OpenSkyActorsInterface
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct MenuStateSaveTests {
    private static let identity = PlayerIdentityState(
        race: FormID(0x13748), isFemale: true, name: "Ada",
        face: PlayerFace(
            morphs: [0.25, -0.5], parts: [2, -1], headParts: [FormID(0x1234)],
            hairColor: FormID(0x5678),
            tints: [PlayerTintLayer(maskIndex: 3, color: SIMD4(10, 20, 30, 255), strength: 0.5)],
            weight: 75, height: 1.03
        )
    )
    private static let marker = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_6E2A)

    @Test func identityMarkersAndFogSurviveAnEncodeAndDecode() throws {
        var fog = LocalMapFogState()
        fog.explore(OpenSkySaveFixture.riverwood, column: 3, row: 4)
        fog.explore(.interior(FormID(0x138C)), column: 0, row: 0)
        let markerState = MapMarkerState(isVisible: true, isDiscovered: false, canTravelTo: true)
        let original = OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: .player, cell: nil, components: [Self.identity.erased, fog.erased]
                ),
                OpenSkySaveFixture.entry(
                    key: Self.marker, cell: nil, components: [markerState.erased]
                )
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        for tag in ["PIDN", "MRKS", "FOGM"] {
            #expect(data.range(of: Data(tag.utf8)) != nil, "\(tag) written")
        }
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(PlayerIdentityState.self, for: .player) == Self.identity)
        #expect(store.component(LocalMapFogState.self, for: .player) == fog)
        #expect(store.component(MapMarkerState.self, for: Self.marker) == markerState)
    }

    @Test func summaryAndThumbnailAreReadWithoutTheWorld() throws {
        let summary = SaveSummary(
            characterName: "Ada", level: 3, raceName: "Redguard", locationName: "Riverwood",
            playSeconds: 125
        )
        let pixels = Data(repeating: 7, count: 8)
        let thumbnail = try #require(SaveThumbnail(width: 2, height: 1, rgba: pixels))
        let data = OpenSkySaveEncoder.encode(
            snapshot: OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            summary: summary,
            thumbnail: thumbnail
        )
        let read = try OpenSkySaveSummaryCodec.readSummary(data)
        #expect(read.summary == summary)
        #expect(read.thumbnail == thumbnail)
        #expect(read.metadata == OpenSkySaveFixture.metadata)
        _ = try OpenSkySaveDecoder.decode(data)
    }

    @Test func aThumbnailThatDoesNotFillItsSizeIsRefused() {
        #expect(SaveThumbnail(width: 2, height: 2, rgba: Data(count: 8)) == nil)
        #expect(SaveThumbnail(width: 0, height: 1, rgba: Data()) == nil)
    }
}
