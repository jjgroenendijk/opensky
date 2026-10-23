// App side of the Traps section: reads the trap scripts, trigger occupancy, the
// enable-parent chain, and the hazards from the session systems, and fires or
// disarms through the same paths a walk or a use-key press takes. No trap rules
// live here; the shipped scripts decide (docs/engine/traps.md).

import OpenSkyDiagnostics
import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

/// What the Traps section reads. The streamer is a closure, because a reload
/// replaces it.
struct TrapControlDependencies {
    let hazards: HazardCoordinator
    let scripts: ScriptCoordinator
    let worldState: WorldStateStore
    let streamer: () -> CellStreamer?
}

final class TrapControlAdapter {
    static let markerSize: Float = 48
    static let markerColor = SIMD4<Float>(1, 0.3, 0.2, 1)

    private let dependencies: TrapControlDependencies
    private(set) var selected: ReferenceKey?

    init(_ dependencies: TrapControlDependencies) {
        self.dependencies = dependencies
    }

    func wire(renderer: Renderer) {
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
