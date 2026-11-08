import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM

/// One actor's graph, or why it runs none.
nonisolated public struct ActorGraphReadout: Equatable, Sendable {
    /// `running`, `loading`, `failed: <reason>`, or `waiting for playback`.
    public let status: String
    public let project: String
    public let activeStates: [String]
    public let isWaitingForClip: Bool
    /// False while the graph has published no pose, so the actor draws its clip.
    public let hasPose: Bool
    public let steps: Int
    public let rate: String
    public let recentEvents: [String]
    public let unresolvedClips: [String]
    public let clipsLoaded: Int
    public let clipsMissed: Int
    /// The first rig bone that bone LOD holds, and every bone after it; nil moves all.
    public var heldFromBone: String?
    /// The graph tags the drunk state.
    public var isDrunk = false
    /// The graph's `iState`, and the value its state tagging generators publish.
    public var state: Int32?
    public var stateTag: Int32?
    /// `weapAdj` and the body-weight layer weights the graph derives from it; empty when the
    /// graph declares none of them.
    public var bodyWeight: [String: Float] = [:]

    public init(
        status: String,
        project: String,
        activeStates: [String],
        isWaitingForClip: Bool,
        hasPose: Bool,
        steps: Int,
        rate: String,
        recentEvents: [String],
        unresolvedClips: [String],
        clipsLoaded: Int,
        clipsMissed: Int,
        heldFromBone: String? = nil,
        isDrunk: Bool = false,
        state: Int32? = nil,
        stateTag: Int32? = nil,
        bodyWeight: [String: Float] = [:]
    ) {
        self.status = status
        self.project = project
        self.activeStates = activeStates
        self.isWaitingForClip = isWaitingForClip
        self.hasPose = hasPose
        self.steps = steps
        self.rate = rate
        self.recentEvents = recentEvents
        self.unresolvedClips = unresolvedClips
        self.clipsLoaded = clipsLoaded
        self.clipsMissed = clipsMissed
        self.heldFromBone = heldFromBone
        self.isDrunk = isDrunk
        self.state = state
        self.stateTag = stateTag
        self.bodyWeight = bodyWeight
    }
}
