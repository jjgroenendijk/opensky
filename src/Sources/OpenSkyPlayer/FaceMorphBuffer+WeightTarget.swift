public import OpenSkyRenderResources
public import OpenSkyWorldInterface

extension FaceMorphBuffer: FaceMorphWeightTarget {
    nonisolated public var targetNames: [String] {
        targets.map(\.name)
    }
}

nonisolated extension FaceMorphPlayback {
    /// The GPU buffers behind the bindings, which the render placements draw with.
    public var renderBuffers: [ObjectIdentifier: FaceMorphBuffer] {
        bindings.compactMapValues { $0 as? FaceMorphBuffer }
    }
}
