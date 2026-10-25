// The Idles section's seam: the idle markers of the loaded cell, their idle
// lists and trees, and the last selection for one actor with its trace.

import OpenSkyFormatsESM

/// One placed idle marker, as the readout lists it.
nonisolated public struct IdleMarkerReadout: Equatable, Sendable {
    public let editorID: String
    /// IDLA editor IDs, in file order.
    public let idles: [String]
    /// The actor standing at or walking to it.
    public let claimedBy: ReferenceKey?
}

/// What the last selection for one actor did.
nonisolated public struct IdleReport: Sendable {
    public let actor: ReferenceKey
    /// The marker's editor ID, or "fired" for a readout request.
    public let source: String
    public let trace: [IdleCandidateTrace]
    public let chosen: String?
    public let plan: IdlePlaybackPlan?
    /// Seconds the clip plays, after the loop count.
    public let seconds: Float
    /// Why nothing played, when nothing did.
    public let failure: String?
}

nonisolated public struct IdleControlSnapshot: Sendable {
    public let isAvailable: Bool
    public let markers: [IdleMarkerReadout]
    /// Actors standing at a marker.
    public let idlingActorCount: Int
    public let report: IdleReport?

    public static let unavailable = IdleControlSnapshot(
        isAvailable: false, markers: [], idlingActorCount: 0, report: nil
    )

    public init(
        isAvailable: Bool,
        markers: [IdleMarkerReadout],
        idlingActorCount: Int,
        report: IdleReport?
    ) {
        self.isAvailable = isAvailable
        self.markers = markers
        self.idlingActorCount = idlingActorCount
        self.report = report
    }
}
