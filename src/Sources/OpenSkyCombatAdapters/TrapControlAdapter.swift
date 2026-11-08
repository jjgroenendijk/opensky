// App side of the Traps section: reads the trap scripts, trigger occupancy, the
// enable-parent chain, and the hazards from the session systems, and fires or
// disarms through the same paths a walk or a use-key press takes. No trap rules
// live here; the shipped scripts decide (docs/engine/traps.md).

public import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
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

    private let dependencies: TrapControlDependencies
    public private(set) var selected: ReferenceKey?

    public init(_ dependencies: TrapControlDependencies) {
        self.dependencies = dependencies
    }

    var selectedEntry: RuntimeReferenceEntry? {
        selected.flatMap { dependencies.streamer()?.referenceEntry(key: $0) }
    }
}
