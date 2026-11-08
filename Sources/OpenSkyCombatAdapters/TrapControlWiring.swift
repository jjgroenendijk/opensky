// `TrapControlAdapter` joins the started session: what `wire` registered.

import OpenSkyFormatsESM
import OpenSkyMagic
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldState

/// Connects `TrapControlAdapter` to the started session.
public struct TrapControlWiring {
    public init(_ adapter: TrapControlAdapter, renderer: Renderer) {
        renderer.worldOverlaySources
            .register(identifier: "trap-selection") { [weak adapter] _, list in
                guard let position = adapter?.selectedEntry?.placedReference?.placement.position
                else {
                    return
                }
                list.addMarker(
                    at: position,
                    size: TrapControlAdapter.markerSize,
                    color: WorldOverlayMarkerColour.trap
                )
            }
    }
}
