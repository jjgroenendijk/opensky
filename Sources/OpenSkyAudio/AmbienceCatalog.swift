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

/// The region sounds for the current context, in record order (REGN.RDSA, then
/// ASPC.SNAM before the ASPC.RDAT borrow), so the director's diff stays deterministic.
/// Which of them loop and which play now and then is the director's call.
nonisolated public struct AmbienceBed: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        /// SNDR descriptor or SOUN legacy marker. The director resolves the
        /// SOUN -> SNDR hop through SoundRecordStore before playback.
        public let sound: FormID
        /// The weather the entry plays in; empty plays in all weather.
        public var weather: Region.SoundEntry.Conditions = []
        /// The chance a one-shot plays at each roll; a loop ignores it.
        public var chance: Float = 1

        public init(sound: FormID, weather: Region.SoundEntry.Conditions = [], chance: Float = 1) {
            self.sound = sound
            self.weather = weather
            self.chance = chance
        }

        init(_ entry: Region.SoundEntry) {
            self.init(sound: entry.sound, weather: entry.conditions, chance: entry.chance)
        }

        /// No weather, such as indoors, lets every entry play.
        public func plays(in weather: Weather.Precipitation) -> Bool {
            switch weather {
            case .none: true
            case .pleasant: self.weather.isEmpty || self.weather.contains(.pleasant)
            case .cloudy: self.weather.isEmpty || self.weather.contains(.cloudy)
            case .rainy: self.weather.isEmpty || self.weather.contains(.rainy)
            case .snow: self.weather.isEmpty || self.weather.contains(.snowy)
            }
        }
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
            entries.append(contentsOf: region.soundList.map(Entry.init))
        }
        return AmbienceBed(entries: entries)
    }

    /// A region whose sound area has the override flag replaces the others, and the
    /// highest priority override wins. [WARNING] Inferred from the Creation Kit's
    /// region editor, not from an open spec: docs/engine/world-sfx.md#region-sounds.
    private static func resolveExterior(
        regions: [FormID],
        weatherStore: WeatherStore?
    ) -> AmbienceBed {
        let withSounds = regions.compactMap { weatherStore?.region($0) }
            .filter { !$0.soundList.isEmpty }
        let overriding = withSounds.filter(\.soundOverride)
            .max { ($0.soundPriority ?? 0) < ($1.soundPriority ?? 0) }
        let chosen = overriding.map { [$0] } ?? withSounds
        return AmbienceBed(entries: chosen.flatMap { $0.soundList.map(Entry.init) })
    }
}
