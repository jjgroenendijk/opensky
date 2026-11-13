// The frame schedules and callbacks through which the streamer reports what changed.

public import OpenSkyAudio
public import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTerrain
public import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// The frame schedules and callbacks through which the streamer reports what changed.
public final class CellStreamerEvents {
    /// Fires with the new worldspace after the exterior switched to it.
    public let onWorldspaceChanged = FrameSchedule<WorldspaceChangeStep, String>()
    /// Fires with the center cell's REGN FormIDs when they change, for region weather.
    /// The app wires it to `GameSession.weather.setRegions`.
    public var onCenterRegionsChanged: (([FormID]) -> Void)?
    /// Last region set pushed through `onCenterRegionsChanged`; nil = never
    /// emitted. Guards against re-firing an unchanged set every frame.
    var lastEmittedRegions: [FormID]?
    /// Fires with the current cell's ambience identity when it changes.
    public var onAmbienceContextChanged: ((AmbienceContext) -> Void)?
    /// Last ambience key pushed; nil = never emitted. Guards against re-firing.
    /// Internal for the CellStreamerAmbience satellite to read/write.
    public var lastEmittedAmbienceKey: AmbienceKey?
    /// Fires with the current cell's music identity when it changes.
    public var onMusicContextChanged: ((MusicContext) -> Void)?
    public var musicFeed = MusicFeed()
    /// Fires when view-ray target identity, text, or hit details change.
    public var onInteractionTargetChanged: ((InteractionTarget?) -> Void)?
    /// Use-key event, delivered in `InteractionStep` order. No handler owns the
    /// raycast or door behavior.
    public let onInteraction = FrameSchedule<InteractionStep, InteractionEvent>()
    /// Player-driven door motion boundaries. World audio consumes these to
    /// start the authored movement loop, retire it, and play the close sound.
    public var onInteractionAnimation: ((InteractionAnimationEvent) -> Void)?
    /// The player used a load door, which swings open while the transition holds.
    public var onLoadDoorUsed: ((FormID) -> Void)?
    /// A cell joined the live world. Emitted in CellStreamerPapyrus.
    public let onCellAttached = FrameSchedule<CellAttachStep, CellAttachment>()
    /// A cell left the live world: unloaded off the grid, dropped by a
    /// coverage transition, or replaced by a door transition.
    public let onCellDetached = FrameSchedule<CellDetachStep, CellSceneLocation>()
    /// A door transition was queued. The loading screen covers the view from here.
    public var onDoorTransitionStarted: (() -> Void)?
    /// A door transition ended: the destination scene, or nil when it failed.
    public var onDoorTransitionFinished: ((CellScene?) -> Void)?
    /// A live cell's placed hazards changed: attached, rebuilt, or detached.
    public let cellHazards = FrameSchedule<CellHazardStep, CellHazardEvent>()
    /// The player entered or left a trigger volume. Emitted in CellStreamerTriggers.
    public let onTriggerTransition = FrameSchedule<TriggerTransitionStep, TriggerTransitionEvent>()
    /// A body came to rest and its transform should be persisted under the
    /// reference's `.transform` component. `bind(to:)` wires it to the store.
    public var onBodySettled: SettledBodyHandler?
    /// Where simulated bodies have moved, published each physics tick. The app wires it to
    /// `GameSession.instancePoses.dynamicDeltas`.
    public var onDynamicPosesChanged: (([UInt32: float4x4]) -> Void)?

    public init() {}
}
