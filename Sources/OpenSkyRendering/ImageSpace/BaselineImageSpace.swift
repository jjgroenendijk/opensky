// Which `IMGS` applies right now. An exterior blends the four `WTHR` `IMSP`
// slots with the time-of-day weights of the sky colors, across a weather
// transition too. An interior uses its `CELL` `XCIM`. Pure.
// See docs/formats/image-spaces.md, section "Resolution".

import Foundation
import OpenSkyFormatsESM

/// One weather and how much of the current look it makes.
nonisolated public struct WeightedWeatherImageSpaces: Equatable, Sendable {
    public let imageSpaces: TimeOfDayValues<FormID?>?
    public let weight: Float

    public init(imageSpaces: TimeOfDayValues<FormID?>?, weight: Float) {
        self.imageSpaces = imageSpaces
        self.weight = weight
    }
}

nonisolated public enum ImageSpaceContext: Equatable, Sendable {
    /// No weather and no cell: nothing to apply.
    case none
    case exterior(weathers: [WeightedWeatherImageSpaces], timeOfDay: TimeOfDayWeights)
    /// The `XCIM` link, or nil when the cell names none.
    case interior(cellImageSpace: FormID?)
}

/// One `IMGS` in the blend. A nil key is a slot that names no record, which counts as neutral.
nonisolated public struct ImageSpaceSource: Equatable, Sendable {
    public let key: ReferenceKey?
    public let name: String
    public let weight: Float
}

nonisolated public struct BaselineImageSpace: Equatable, Sendable {
    public let sources: [ImageSpaceSource]
    public let parameters: ImageSpaceParameters

    public static let none = BaselineImageSpace(sources: [], parameters: .neutral)

    /// The source with the most weight, for a one-line readout.
    public var dominantName: String {
        sources.max { $0.weight < $1.weight }?.name ?? "none"
    }
}

/// A resolved `IMGS` link.
nonisolated public struct ResolvedImageSpace: Equatable, Sendable {
    public let key: ReferenceKey
    public let record: ImageSpace

    public init(key: ReferenceKey, record: ImageSpace) {
        self.key = key
        self.record = record
    }
}

nonisolated public enum BaselineImageSpaceResolver {
    public static func resolve(
        _ context: ImageSpaceContext,
        lookup: (FormID) -> ResolvedImageSpace?
    ) -> BaselineImageSpace {
        let slots: [(id: FormID?, weight: Float)]
        switch context {
        case .none:
            return .none
        case let .interior(cellImageSpace):
            slots = [(cellImageSpace, 1)]
        case let .exterior(weathers, timeOfDay):
            slots = weathers.flatMap { weather in
                let links = weather.imageSpaces
                return [
                    (links?.sunrise, timeOfDay.sunrise), (links?.day, timeOfDay.day),
                    (links?.sunset, timeOfDay.sunset), (links?.night, timeOfDay.night)
                ].map { (id: $0.0, weight: $0.1 * weather.weight) }
            }
        }
        var sources: [ImageSpaceSource] = []
        var parts: [(value: ImageSpaceParameters, weight: Float)] = []
        for slot in slots where slot.weight > 0 {
            let resolved = slot.id.flatMap(lookup)
            parts.append((
                resolved.map { ImageSpaceParameters($0.record) } ?? .neutral,
                slot.weight
            ))
            let name = resolved.map { $0.record.editorID ?? $0.key.description } ?? "none"
            if let index = sources.firstIndex(where: { $0.key == resolved?.key }) {
                let merged = sources[index].weight + slot.weight
                sources[index] = ImageSpaceSource(key: resolved?.key, name: name, weight: merged)
            } else {
                sources.append(ImageSpaceSource(
                    key: resolved?.key,
                    name: name,
                    weight: slot.weight
                ))
            }
        }
        guard !parts.isEmpty else { return .none }
        return BaselineImageSpace(sources: sources, parameters: .blend(parts))
    }
}
