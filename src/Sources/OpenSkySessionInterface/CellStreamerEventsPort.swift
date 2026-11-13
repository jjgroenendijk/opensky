// The frame schedules through which the streamer reports what changed.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// The frame schedules through which the streamer reports what changed. Part of `CellStreamerPort`.
public protocol CellStreamerEventsPort {
    var onCellDetached: FrameSchedule<CellDetachStep, CellSceneLocation> { get }
    var onInteraction: FrameSchedule<InteractionStep, InteractionEvent> { get }
}
