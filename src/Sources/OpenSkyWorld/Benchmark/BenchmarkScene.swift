import Foundation
public import OpenSkyWorldInterface
import simd

nonisolated extension BenchmarkPreset {
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
