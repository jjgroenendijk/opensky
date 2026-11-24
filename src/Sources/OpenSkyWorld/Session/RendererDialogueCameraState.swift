// What the dialogue camera override holds between frames.

public import OpenSkyPlayer
public import OpenSkyRenderCore
public import OpenSkyWorldInterface

/// Everything the override owns, in one value: extensions cannot add stored
/// properties, and these three are one thing.
public struct RendererDialogueCameraState {
    /// The live focus, or nil when no conversation is framing anybody.
    public var focus: DialogueCameraFocus?
    /// The framing math and its collision readout.
    public var camera = DialogueCamera()
    /// The player's own view pose, held while the override stands in for it.
    /// Non-nil exactly while the swap is applied.
    public var restorePose: FreeFlyCamera?
    /// The speaker's look-at point while a conversation is open.
    public var speakerAim: SIMD3<Float>?
    /// The first-person turn to the speaker, set up when the conversation starts.
    public var turn: DialogueTurn?
    /// The menu pointer and the view size while a conversation is open, for the edge look.
    public var pointer: (location: SIMD2<Float>, viewSize: SIMD2<Float>)?
}
