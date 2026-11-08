// App side of the Traps section: reads the trap scripts, trigger occupancy, the
// enable-parent chain, and the hazards from the session systems, and fires or
// disarms through the same paths a walk or a use-key press takes. No trap rules
// live here; the shipped scripts decide (docs/engine/traps.md).

import OpenSkyDiagnostics
public import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRendering
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldState

/// What the Traps section reads. The streamer is a closure, because a reload
/// replaces it.
public struct TrapControlDependencies {
    public let streamer: () -> CellStreamer?

    public init(
        streamer: @escaping () -> CellStreamer?
    ) {
        self.streamer = streamer
    }
}

public final class TrapControlAdapter {
    public static let markerSize: Float = 48
    public static let markerColor = SIMD4<Float>(1, 0.3, 0.2, 1)

    private let dependencies: TrapControlDependencies
    public private(set) var selected: ReferenceKey?

    public init(_ dependencies: TrapControlDependencies) {
        self.dependencies = dependencies
    }

    public func wire(renderer: Renderer) {
        renderer.worldOverlaySources.register(identifier: "trap-selection") { [weak self] _, list in
            guard let position = self?.selectedEntry?.placedReference?.placement.position else {
                return
            }
            list.addMarker(at: position, size: Self.markerSize, color: Self.markerColor)
        }
    }

    private var selectedEntry: RuntimeReferenceEntry? {
        selected.flatMap { dependencies.streamer()?.referenceEntry(key: $0) }
    }
}

extension TrapControlAdapter: TrapControlPort {}
