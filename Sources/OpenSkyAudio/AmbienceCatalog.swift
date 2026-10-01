// Per-cell ambient sound bed resolution, pure over the REGN/ASPC stores.
//   Exterior: CELL XCLR -> REGN -> type-7 RDAT sound area (RDSA: SNDR/SOUN)
//   Interior: CELL XCAS -> ASPC SNAM (SNDR), plus an optional borrowed RDAT region
// Sources: xEdit wbDefinitionsCommon.pas (REGN.RDSA), wbDefinitionsTES5.pas (ASPC).

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// Identity of the cell whose ambience should be playing. The streamer emits a
/// fresh value whenever the center cell changes (exterior recenter, interior
/// enter/exit). Pure value, Sendable; the director owns no streaming state.
nonisolated public struct AmbienceContext: Equatable, Sendable {
    /// XCLR REGN FormIDs for exterior ambience; empty for interiors.
    public let regions: [FormID]
    /// XCAS acoustic-space FormID for interior ambience; nil for exteriors.
    public let acousticSpace: FormID?
    public let isInterior: Bool

    public static let empty = AmbienceContext(regions: [], acousticSpace: nil, isInterior: false)

    public init(regions: [FormID], acousticSpace: FormID?, isInterior: Bool) {
        self.regions = regions
        self.acousticSpace = acousticSpace
        self.isInterior = isInterior
    }
}

/// Resolved ambient bed: the SNDR/SOUN FormIDs that should be the positional
/// loop set for the current context. Order is preserved (record order in
/// REGN.RDSA, then ASPC.SNAM before ASPC.RDAT borrow) so the director's diff
/// stays deterministic.
nonisolated public struct AmbienceBed: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// SNDR descriptor or SOUN legacy marker. The director resolves the
        /// SOUN -> SNDR hop through SoundRecordStore before playback.
        public let sound: FormID
    }

    public let entries: [Entry]

    public static let empty = AmbienceBed(entries: [])

    public static func resolve(
        context: AmbienceContext,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?
    ) -> AmbienceBed {
        if context.isInterior {
            return resolveInterior(
                acousticSpace: context.acousticSpace,
                weatherStore: weatherStore,
                aspcStore: aspcStore
            )
        }
        return resolveExterior(
            regions: context.regions, weatherStore: weatherStore
        )
    }

    private static func resolveInterior(
        acousticSpace: FormID?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?
    ) -> AmbienceBed {
        guard let acousticSpace, let aspc = aspcStore?.acousticSpace(acousticSpace) else {
            return .empty
        }
        var entries: [Entry] = []
        if let direct = aspc.ambientSound {
            entries.append(Entry(sound: direct))
        }
        if
            let borrowed = aspc.borrowedRegion,
            let region = weatherStore?.region(borrowed)
        {
            entries.append(contentsOf: region.soundList.map { Entry(sound: $0.sound) })
        }
        return AmbienceBed(entries: entries)
    }

    private static func resolveExterior(
        regions: [FormID],
        weatherStore: WeatherStore?
    ) -> AmbienceBed {
        var entries: [Entry] = []
        for regionID in regions {
            guard let region = weatherStore?.region(regionID) else { continue }
            entries.append(contentsOf: region.soundList.map { Entry(sound: $0.sound) })
        }
        return AmbienceBed(entries: entries)
    }
}
