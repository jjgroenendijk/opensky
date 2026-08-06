// Per-cell ambient sound bed resolution (M9.2.2). Pure value logic over the
// decoded REGN/ASPC stores; the runtime director diffs a freshly resolved bed
// against its active sources and starts/stops as needed.
//
// Resolution paths:
//   Exterior CELL -> XCLR REGN set -> each region's type-7 RDAT sound area
//                                       (RDSA entries: SNDR/SOUN FormIDs).
//   Interior CELL -> XCAS ASPC     -> ASPC.SNAM (direct SNDR) plus optionally
//                                       ASPC.RDAT (a borrowed region whose
//                                       sound area drives this interior).
//
// Sources:
//   REGN.RDSA structure: xEdit dev-4.1.6 wbDefinitionsCommon.pas:8729-8747.
//   ASPC record body:    xEdit wbDefinitionsTES5.pas:5401-5407.

import Foundation
import simd

/// Identity of the cell whose ambience should be playing. The streamer emits a
/// fresh value whenever the center cell changes (exterior recenter, interior
/// enter/exit). Pure value, Sendable; the director owns no streaming state.
nonisolated struct AmbienceContext: Equatable, Sendable {
    /// XCLR REGN FormIDs for exterior ambience; empty for interiors.
    let regions: [FormID]
    /// XCAS acoustic-space FormID for interior ambience; nil for exteriors.
    let acousticSpace: FormID?
    let isInterior: Bool

    static let empty = AmbienceContext(regions: [], acousticSpace: nil, isInterior: false)
}

/// Resolved ambient bed: the SNDR/SOUN FormIDs that should be the positional
/// loop set for the current context. Order is preserved (record order in
/// REGN.RDSA, then ASPC.SNAM before ASPC.RDAT borrow) so the director's diff
/// stays deterministic.
nonisolated struct AmbienceBed: Equatable {
    struct Entry: Equatable {
        /// SNDR descriptor or SOUN legacy marker. The director resolves the
        /// SOUN -> SNDR hop through SoundRecordStore before playback.
        let sound: FormID
    }

    let entries: [Entry]

    static let empty = AmbienceBed(entries: [])

    static func resolve(
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
