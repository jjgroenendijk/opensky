// One stop of the benchmark tour: where it goes, the light it sets, and the
// camera move it measures. The catalog is in `BenchmarkTour`.

import Foundation
import simd

nonisolated public enum BenchmarkSceneGroup: String, Codable, CaseIterable, Sendable {
    case city
    case wilderness
    case interior
    case dlc

    public var title: String {
        switch self {
        case .city: "Cities"
        case .wilderness: "Wilderness"
        case .interior: "Interiors"
        case .dlc: "DLC worlds"
        }
    }
}

nonisolated public enum BenchmarkPlace: Equatable, Sendable {
    /// The origin is the ground under `x`, `y`, so offsets read as heights above it.
    case exterior(worldspace: String, x: Float, y: Float)
    /// Shot points are cell coordinates, so each shot stands in its main room.
    case interior(cell: String)

    public var label: String {
        switch self {
        case let .exterior(worldspace, x, y): "\(worldspace) (\(Int(x)), \(Int(y)))"
        case let .interior(cell): cell
        }
    }
}

nonisolated public struct BenchmarkScene: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let group: BenchmarkSceneGroup
    public let place: BenchmarkPlace
    /// The street height a city shot is written over. A city on meshes hides the
    /// terrain under it, so no ground sample gives its height.
    public let streetLevel: Float?
    /// Game hour, 0 to 24.
    public let hour: Float
    /// A weather editor ID; nil keeps the region's own weather.
    public let weather: String?
    public let shot: BenchmarkShot
    /// The plugin the scene needs, such as `Dawnguard.esm`; nil for the base game.
    public let requiredPlugin: String?

    public init(
        id: String, title: String, group: BenchmarkSceneGroup, place: BenchmarkPlace,
        streetLevel: Float? = nil, hour: Float, weather: String?, shot: BenchmarkShot,
        requiredPlugin: String? = nil
    ) {
        self.id = id
        self.title = title
        self.group = group
        self.place = place
        self.streetLevel = streetLevel
        self.hour = hour
        self.weather = weather
        self.shot = shot
        self.requiredPlugin = requiredPlugin
    }
}

/// How long a tour runs. Each preset is a fixed scene list, so two runs of it compare.
nonisolated public enum BenchmarkPreset: String, Codable, CaseIterable, Sendable {
    /// One scene per base-game group.
    case quick
    /// Every base-game scene.
    case standard
    /// Every scene, the DLC worlds included.
    case full

    public var title: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .full: "Full"
        }
    }

    public func scenes(in catalog: [BenchmarkScene] = BenchmarkTour.scenes) -> [BenchmarkScene] {
        switch self {
        case .quick:
            BenchmarkTour.quickSceneIDs.compactMap { id in catalog.first { $0.id == id } }
        case .standard:
            catalog.filter { $0.group != .dlc }
        case .full:
            catalog
        }
    }
}
